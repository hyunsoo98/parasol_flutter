"""
AWS Lambda: Eye Tracking 비디오 분석 처리
- SQS에서 메시지 수신
- S3에서 비디오 다운로드
- MediaPipe로 eye tracking 분석
- 결과를 DynamoDB에 저장
- 처리된 데이터를 S3에 저장
"""

import json
import boto3
import cv2
import math
import time
import tempfile
import numpy as np
import pandas as pd
import io
import os
from typing import Any, Dict, List, Optional, Tuple
import traceback

# AWS 클라이언트 초기화
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'eye-tracking-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# MediaPipe 초기화 (Lambda 환경에서는 싱글톤 패턴 사용)
try:
    import mediapipe as mp
    mp_face_mesh = mp.solutions.face_mesh
    from mediapipe.solutions.face_mesh_connections import (
        FACEMESH_LEFT_IRIS, FACEMESH_RIGHT_IRIS,
    )
except ImportError:
    # MediaPipe가 없는 경우 대체 구현
    mp_face_mesh = None
    FACEMESH_LEFT_IRIS = []
    FACEMESH_RIGHT_IRIS = []

# 전역 변수로 FaceMesh 모델 캐시
_face_mesh_model = None

def get_face_mesh():
    """FaceMesh 모델 싱글톤"""
    global _face_mesh_model
    if _face_mesh_model is None and mp_face_mesh is not None:
        _face_mesh_model = mp_face_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    return _face_mesh_model

# eye.py에서 가져온 핵심 함수들 (FastAPI/Firebase 의존성 제거)
def _px(lm, w: int, h: int) -> Tuple[float, float]:
    """랜드마크를 픽셀 좌표로 변환"""
    return lm.x * w, lm.y * h

def _uniq_indices(conns: List[Tuple[int, int]]) -> List[int]:
    """연결점들에서 고유 인덱스 추출"""
    s = set()
    for a, b in conns:
        s.add(a)
        s.add(b)
    return sorted(list(s))

# 홍채 랜드마크 인덱스
LEFT_IRIS_IDXS = _uniq_indices(FACEMESH_LEFT_IRIS) if FACEMESH_LEFT_IRIS else []
RIGHT_IRIS_IDXS = _uniq_indices(FACEMESH_RIGHT_IRIS) if FACEMESH_RIGHT_IRIS else []

# 눈 랜드마크 인덱스
L_CORNER_OUT, L_CORNER_IN = 33, 133
L_LID_TOP, L_LID_BOT = 159, 145
R_CORNER_OUT, R_CORNER_IN = 362, 263
R_LID_TOP, R_LID_BOT = 386, 374

def _iris_center(landmarks, idxs, w, h) -> Tuple[float, float]:
    """홍채 중심점 계산"""
    xs, ys = [], []
    for i in idxs:
        x, y = _px(landmarks[i], w, h)
        xs.append(x)
        ys.append(y)
    if not xs:
        return float("nan"), float("nan")
    return float(np.mean(xs)), float(np.mean(ys))

def _eye_metrics(landmarks, w, h, is_left=True) -> Dict[str, float]:
    """눈 지표 계산"""
    if is_left:
        c_out, c_in = L_CORNER_OUT, L_CORNER_IN
        lid_top, lid_bot = L_LID_TOP, L_LID_BOT
        iris_idxs = LEFT_IRIS_IDXS
    else:
        c_out, c_in = R_CORNER_OUT, R_CORNER_IN
        lid_top, lid_bot = R_LID_TOP, R_LID_BOT
        iris_idxs = RIGHT_IRIS_IDXS

    x_out, y_out = _px(landmarks[c_out], w, h)
    x_in, y_in = _px(landmarks[c_in], w, h)
    eye_width = max(1e-6, math.hypot(x_out - x_in, y_out - y_in))

    x_t, y_t = _px(landmarks[lid_top], w, h)
    x_b, y_b = _px(landmarks[lid_bot], w, h)
    eyelid_dist = math.hypot(x_t - x_b, y_t - y_b)

    eye_open = eyelid_dist / eye_width
    ix, iy = _iris_center(landmarks, iris_idxs, w, h)

    cx, cy = (x_out + x_in) / 2.0, (y_out + y_in) / 2.0
    eye_height = max(1e-6, eyelid_dist)
    v_offset_norm = (iy - cy) / eye_height

    return {
        "iris_cx": ix, 
        "iris_cy": iy,
        "eye_open": eye_open,
        "v_offset": v_offset_norm,
    }

def count_blinks(openness_series: List[float], thresh: float = 0.18, min_frames: int = 2) -> int:
    """블링크 카운트"""
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

def process_video_analysis(video_path: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
    """비디오 분석 메인 함수"""
    
    # 파라미터 추출
    step = parameters.get('step', 1)
    vpp_thresh = parameters.get('vpp_thresh', 0.06)
    blink_thresh = parameters.get('blink_thresh', 0.18)
    max_frames = parameters.get('max_frames', 12000)
    blink_min_frames = parameters.get('blink_min_frames', 2)
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise Exception("비디오 파일을 열 수 없습니다")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

    rows = []
    frame_idx = 0
    processed = 0
    face_mesh = get_face_mesh()

    try:
        while processed < max_frames:
            ret, frame = cap.read()
            if not ret:
                break
                
            if frame_idx % step != 0:
                frame_idx += 1
                continue

            t_sec = frame_idx / max(1e-6, fps)
            
            if face_mesh:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = face_mesh.process(rgb)
                
                if results.multi_face_landmarks:
                    landmarks = results.multi_face_landmarks[0].landmark
                    left_metrics = _eye_metrics(landmarks, width, height, is_left=True)
                    right_metrics = _eye_metrics(landmarks, width, height, is_left=False)
                    
                    v_offset = float(np.nanmean([left_metrics["v_offset"], right_metrics["v_offset"]]))
                    eye_open = float(np.nanmean([left_metrics["eye_open"], right_metrics["eye_open"]]))
                    
                    rows.append({
                        "frame_idx": frame_idx,
                        "time_sec": t_sec,
                        "L_iris_cx": left_metrics["iris_cx"],
                        "L_iris_cy": left_metrics["iris_cy"],
                        "L_eye_open": left_metrics["eye_open"],
                        "L_v_offset": left_metrics["v_offset"],
                        "R_iris_cx": right_metrics["iris_cx"],
                        "R_iris_cy": right_metrics["iris_cy"],
                        "R_eye_open": right_metrics["eye_open"],
                        "R_v_offset": right_metrics["v_offset"],
                        "eye_open": eye_open,
                        "v_offset": v_offset,
                    })
                else:
                    # 얼굴이 감지되지 않은 프레임
                    rows.append({
                        "frame_idx": frame_idx,
                        "time_sec": t_sec,
                        "L_iris_cx": np.nan, "L_iris_cy": np.nan,
                        "L_eye_open": np.nan, "L_v_offset": np.nan,
                        "R_iris_cx": np.nan, "R_iris_cy": np.nan,
                        "R_eye_open": np.nan, "R_v_offset": np.nan,
                        "eye_open": np.nan, "v_offset": np.nan,
                    })

            processed += 1
            frame_idx += 1

    finally:
        cap.release()

    if not rows:
        raise Exception("처리된 프레임이 없습니다")

    # DataFrame 생성 및 통계 계산
    df = pd.DataFrame(rows).sort_values("frame_idx").reset_index(drop=True)
    
    v_series = df["v_offset"].to_numpy(dtype=float)
    eye_open_series = df["eye_open"].to_numpy(dtype=float)
    v_valid = v_series[~np.isnan(v_series)]
    open_valid = eye_open_series[~np.isnan(eye_open_series)]

    def robust_ptp(x: np.ndarray) -> float:
        if x.size == 0:
            return float("nan")
        lo, hi = np.percentile(x, [5, 95])
        return float(hi - lo)

    v_ptp = robust_ptp(v_valid)
    v_std = float(np.nanstd(v_valid)) if v_valid.size else float("nan")
    blink_count = count_blinks(open_valid.tolist(), thresh=blink_thresh, min_frames=blink_min_frames)
    
    dur_sec = float(df["time_sec"].dropna().max() - df["time_sec"].dropna().min()) if df["time_sec"].notna().any() else float("nan")
    blink_rate_per_min = (blink_count / dur_sec * 60.0) if (dur_sec and not math.isnan(dur_sec) and dur_sec > 0) else float("nan")

    psp_suspected = bool(v_ptp < vpp_thresh) if not math.isnan(v_ptp) else False

    return {
        "frames_processed": len(df),
        "fps": fps,
        "duration_sec": dur_sec,
        "video_meta": {"width": width, "height": height, "fps": fps, "total_frames": total_frames},
        "vertical_movement": {
            "std": v_std,
            "peak_to_peak": v_ptp
        },
        "blink_analysis": {
            "count": blink_count,
            "rate_per_minute": blink_rate_per_min
        },
        "psp_screening": {
            "suspected": psp_suspected,
            "threshold_used": vpp_thresh,
            "vertical_ptp_measured": v_ptp
        },
        "raw_data": df.to_dict('records')
    }

def lambda_handler(event, context):
    """SQS에서 트리거되는 메인 핸들러"""
    
    for record in event['Records']:
        analysis_id = None
        try:
            # SQS 메시지 파싱
            message_body = json.loads(record['body'])
            analysis_id = message_body['analysis_id']
            user_id = message_body['user_id']
            s3_bucket = message_body['s3_bucket']
            s3_key = message_body['s3_key']
            parameters = message_body.get('parameters', {})
            
            print(f"분석 시작: {analysis_id}")
            
            # 진행률 업데이트 (10%)
            update_progress(analysis_id, 10, "비디오 다운로드 중...")
            
            # S3에서 비디오 다운로드
            with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp_file:
                try:
                    s3_client.download_fileobj(s3_bucket, s3_key, tmp_file)
                    tmp_file.flush()
                    video_path = tmp_file.name
                    
                    # 진행률 업데이트 (30%)
                    update_progress(analysis_id, 30, "비디오 분석 중...")
                    
                    # 비디오 분석 실행
                    result = process_video_analysis(video_path, parameters)
                    
                    # 진행률 업데이트 (80%)
                    update_progress(analysis_id, 80, "결과 저장 중...")
                    
                    # 결과 CSV를 S3에 저장
                    if 'raw_data' in result:
                        csv_df = pd.DataFrame(result['raw_data'])
                        csv_buffer = io.StringIO()
                        csv_df.to_csv(csv_buffer, index=False)
                        csv_data = csv_buffer.getvalue().encode('utf-8')
                        
                        csv_s3_key = f"{S3_PREFIX}results/{user_id}/{analysis_id}/analysis_results.csv"
                        s3_client.put_object(
                            Bucket=s3_bucket,
                            Key=csv_s3_key,
                            Body=csv_data,
                            ContentType='text/csv'
                        )
                        result['csv_s3_key'] = csv_s3_key
                        
                        # raw_data는 DynamoDB에 저장하지 않음 (크기 제한)
                        del result['raw_data']
                    
                    # 최종 결과를 DynamoDB에 저장
                    table.update_item(
                        Key={'analysis_id': analysis_id},
                        UpdateExpression='SET #status = :status, #result = :result, #progress = :progress, #completed_at = :completed_at',
                        ExpressionAttributeNames={
                            '#status': 'status',
                            '#result': 'result',
                            '#progress': 'progress',
                            '#completed_at': 'completed_at'
                        },
                        ExpressionAttributeValues={
                            ':status': 'completed',
                            ':result': result,
                            ':progress': 100,
                            ':completed_at': int(time.time())
                        }
                    )
                    
                    print(f"분석 완료: {analysis_id}")
                    
                finally:
                    # 임시 파일 정리
                    if os.path.exists(tmp_file.name):
                        os.unlink(tmp_file.name)
                        
        except Exception as e:
            error_message = f"분석 실패: {str(e)}"
            print(f"오류 발생 - {analysis_id}: {error_message}")
            print(f"Traceback: {traceback.format_exc()}")
            
            if analysis_id:
                # 실패 상태로 업데이트
                table.update_item(
                    Key={'analysis_id': analysis_id},
                    UpdateExpression='SET #status = :status, #error = :error, #failed_at = :failed_at',
                    ExpressionAttributeNames={
                        '#status': 'status',
                        '#error': 'error',
                        '#failed_at': 'failed_at'
                    },
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': error_message,
                        ':failed_at': int(time.time())
                    }
                )

def update_progress(analysis_id: str, progress: int, message: str):
    """진행률 업데이트"""
    try:
        table.update_item(
            Key={'analysis_id': analysis_id},
            UpdateExpression='SET #progress = :progress, #progress_message = :message',
            ExpressionAttributeNames={
                '#progress': 'progress',
                '#progress_message': 'progress_message'
            },
            ExpressionAttributeValues={
                ':progress': progress,
                ':message': message
            }
        )
    except Exception as e:
        print(f"진행률 업데이트 실패: {str(e)}")