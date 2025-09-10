#!/usr/bin/env python3
"""
FastAPI 서버 - 파킨슨병 진단 Eye Tracking API
"""
from fastapi import FastAPI, File, UploadFile, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import sys
import tempfile
import uuid
import time
import math
import json
from typing import Dict, Any, Optional, Tuple, List
import cv2
import numpy as np
import pandas as pd
import mediapipe as mp
from mediapipe.solutions import face_mesh as mp_face_mesh
from mediapipe.solutions.face_mesh_connections import (
    FACEMESH_LEFT_IRIS,
    FACEMESH_RIGHT_IRIS,
)

# FastAPI 앱 초기화
app = FastAPI(
    title="Parkinson's Disease Eye Tracking API",
    description="MediaPipe 기반 눈 추적 분석 API",
    version="1.0.0"
)

# CORS 설정 (Flutter 앱에서 접근 가능하도록)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 실제 운영에서는 구체적인 도메인 지정
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MediaPipe 유틸리티 함수들 (eye_model.py에서 복사)
def _uniq_indices(connections: List[Tuple[int, int]]) -> List[int]:
    s = set()
    for a, b in connections:
        s.add(a); s.add(b)
    return sorted(list(s))

LEFT_IRIS_IDXS  = _uniq_indices(FACEMESH_LEFT_IRIS)
RIGHT_IRIS_IDXS = _uniq_indices(FACEMESH_RIGHT_IRIS)

# 눈 모서리/윗/아랫눈꺼풀 대표 랜드마크
L_CORNER_OUT, L_CORNER_IN = 33, 133
L_LID_TOP,   L_LID_BOT    = 159, 145
R_CORNER_OUT, R_CORNER_IN = 362, 263
R_LID_TOP,   R_LID_BOT    = 386, 374

def _px(landmark, w, h) -> Tuple[float, float]:
    return landmark.x * w, landmark.y * h

def _iris_center(landmarks, idxs, w, h) -> Tuple[float, float]:
    xs, ys = [], []
    for i in idxs:
        x, y = _px(landmarks[i], w, h)
        xs.append(x); ys.append(y)
    if not xs:
        return np.nan, np.nan
    return float(np.mean(xs)), float(np.mean(ys))

def _eye_metrics(landmarks, w, h, is_left=True) -> Dict[str, float]:
    if is_left:
        c_out, c_in = L_CORNER_OUT, L_CORNER_IN
        lid_top, lid_bot = L_LID_TOP, L_LID_BOT
        iris_idxs = LEFT_IRIS_IDXS
    else:
        c_out, c_in = R_CORNER_OUT, R_CORNER_IN
        lid_top, lid_bot = R_LID_TOP, R_LID_BOT
        iris_idxs = RIGHT_IRIS_IDXS

    # 가로폭(정규화 기준)
    x_out, y_out = _px(landmarks[c_out], w, h)
    x_in,  y_in  = _px(landmarks[c_in],  w, h)
    eye_width = max(1e-6, math.hypot(x_out - x_in, y_out - y_in))

    # 세로 개폐도
    x_t, y_t = _px(landmarks[lid_top], w, h)
    x_b, y_b = _px(landmarks[lid_bot], w, h)
    eye_open = math.hypot(x_t - x_b, y_t - y_b) / eye_width

    # 홍채 중심과 눈 중앙/높이 기준 정규화 위치
    ix, iy = _iris_center(landmarks, iris_idxs, w, h)
    cx, cy = (x_out + x_in) / 2.0, (y_out + y_in) / 2.0
    eye_height = max(1e-6, math.hypot(x_t - x_b, y_t - y_b))
    v_offset_norm = (iy - cy) / eye_height

    return {
        "eye_width": eye_width,
        "eye_open": eye_open,
        "iris_cx": ix,
        "iris_cy": iy,
        "eye_cx": cx,
        "eye_cy": cy,
        "v_offset_norm": v_offset_norm,
    }

def count_blinks(openness_series: List[float], thresh: float = 0.18, min_frames: int = 2) -> int:
    closed = False
    hold = 0
    count = 0
    for v in openness_series:
        if np.isnan(v):
            if closed and hold >= min_frames:
                count += 1
            closed, hold = False, 0
            continue

        if v < thresh:
            if closed:
                hold += 1
            else:
                closed = True
                hold = 1
        else:
            if closed and hold >= min_frames:
                count += 1
            closed, hold = False, 0

    if closed and hold >= min_frames:
        count += 1
    return count

@app.get("/")
async def root():
    return {"message": "Parkinson's Eye Tracking API Server"}

@app.get("/health")
async def health_check():
    return {"status": "ok", "message": "서버가 정상 작동 중입니다"}

@app.post("/api/eye-tracking")
async def analyze_eye_tracking(
    file: UploadFile = File(..., description="mp4 비디오 파일"),
    step: int = Query(1, description="프레임 샘플링 간격"),
    vpp_thresh: float = Query(0.06, description="PSP 의심 판정용 수직 임계값"),
    blink_thresh: float = Query(0.18, description="눈꺼풀 닫힘 판정 임계치"),
    max_frames: int = Query(12000, description="최대 처리 프레임")
):
    """눈 추적 분석 API - Flutter 앱에서 호출"""
    
    # 파일 타입 검증
    if not file.content_type or not file.content_type.startswith('video/'):
        raise HTTPException(400, detail="비디오 파일만 허용됩니다")
    
    try:
        # 업로드된 파일 읽기
        content = await file.read()
        if not content:
            raise HTTPException(400, detail="빈 파일입니다")
        
        # 임시 파일 생성 및 비디오 처리
        with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp_file:
            tmp_file.write(content)
            tmp_file.flush()
            
            # OpenCV로 비디오 열기
            cap = cv2.VideoCapture(tmp_file.name)
            if not cap.isOpened():
                raise HTTPException(400, detail="비디오를 열 수 없습니다")
            
            fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
            
            # MediaPipe FaceMesh 초기화
            fm = mp_face_mesh.FaceMesh(
                static_image_mode=False,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
            
            # 프레임 처리
            rows = []
            fidx = 0
            kept = 0
            
            while kept < max_frames:
                ret, frame = cap.read()
                if not ret:
                    break
                    
                if fidx % step != 0:
                    fidx += 1
                    continue
                
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = fm.process(rgb)
                t_sec = fidx / max(1e-6, fps)
                
                if result.multi_face_landmarks:
                    landmarks = result.multi_face_landmarks[0].landmark
                    
                    # 좌/우 눈 메트릭 계산
                    L = _eye_metrics(landmarks, width, height, is_left=True)
                    R = _eye_metrics(landmarks, width, height, is_left=False)
                    
                    # 평균 값 계산
                    v_offset = np.nanmean([L["v_offset_norm"], R["v_offset_norm"]])
                    eye_open = np.nanmean([L["eye_open"], R["eye_open"]])
                    
                    rows.append({
                        "frame_idx": fidx,
                        "time_sec": t_sec,
                        "L_v_offset": L["v_offset_norm"],
                        "R_v_offset": R["v_offset_norm"],
                        "L_eye_open": L["eye_open"],
                        "R_eye_open": R["eye_open"],
                        "v_offset": v_offset,
                        "eye_open": eye_open,
                    })
                else:
                    # 얼굴이 감지되지 않은 프레임
                    rows.append({
                        "frame_idx": fidx,
                        "time_sec": t_sec,
                        "L_v_offset": np.nan,
                        "R_v_offset": np.nan,
                        "L_eye_open": np.nan,
                        "R_eye_open": np.nan,
                        "v_offset": np.nan,
                        "eye_open": np.nan,
                    })
                
                kept += 1
                fidx += 1
            
            cap.release()
            fm.close()
            
            # 임시 파일 삭제
            os.unlink(tmp_file.name)
        
        if not rows:
            raise HTTPException(400, detail="유효한 프레임을 처리하지 못했습니다")
        
        # 데이터 분석
        df = pd.DataFrame(rows)
        v_series = df["v_offset"].to_numpy(dtype=float)
        eye_open_series = df["eye_open"].to_numpy(dtype=float)
        
        # NaN 제거
        v_valid = v_series[~np.isnan(v_series)]
        open_valid = eye_open_series[~np.isnan(eye_open_series)]
        
        # 수직 움직임 분석
        def robust_ptp(x: np.ndarray) -> float:
            if x.size == 0:
                return float("nan")
            lo, hi = np.percentile(x, [5, 95])
            return float(hi - lo)
        
        v_ptp = robust_ptp(v_valid)
        v_std = float(np.nanstd(v_valid)) if v_valid.size else float("nan")
        
        # 블링크 분석
        blink_count = count_blinks(open_valid.tolist(), thresh=blink_thresh)
        dur_sec = float(df["time_sec"].max() - df["time_sec"].min()) if len(df) > 1 else 0.0
        blink_rate_per_min = (blink_count / dur_sec * 60.0) if dur_sec > 0 else 0.0
        
        # PSP 의심 판정
        psp_suspected = bool(v_ptp < vpp_thresh) if not math.isnan(v_ptp) else False
        
        # 결과 반환
        return {
            "success": True,
            "analysis_result": {
                "frames_processed": len(df),
                "duration_sec": dur_sec,
                "vertical_movement": {
                    "peak_to_peak": v_ptp,
                    "std_deviation": v_std
                },
                "blink_analysis": {
                    "count": blink_count,
                    "rate_per_minute": blink_rate_per_min
                },
                "psp_screening": {
                    "suspected": psp_suspected,
                    "threshold_used": vpp_thresh,
                    "vertical_ptp_measured": v_ptp
                }
            },
            "raw_data": rows[:100] if len(rows) > 100 else rows  # 처음 100프레임만 반환
        }
        
    except Exception as e:
        raise HTTPException(500, detail=f"분석 중 오류 발생: {str(e)}")

if __name__ == "__main__":
    print("🚀 파킨슨병 진단 Eye Tracking API 서버 시작")
    print("📊 MediaPipe 기반 눈 추적 분석")
    print("🌐 서버 주소: http://localhost:8000")
    print("📖 API 문서: http://localhost:8000/docs")
    
    uvicorn.run(app, host="0.0.0.0", port=8000)