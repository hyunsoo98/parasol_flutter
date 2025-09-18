# app/routers/eye.py
from __future__ import annotations

import io
import os
import cv2
import math
import time
import uuid
import base64
import tempfile
import numpy as np
import pandas as pd
from typing import Any, Dict, List, Optional, Tuple

from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status, Query

# 프로젝트 의존 (Firebase 클라이언트들)
from app.core.auth import get_current_user  # Firebase(구글/카카오) 인증
from app.core.firebase import db, bucket
from firebase_admin import firestore as fb_fs  # SERVER_TIMESTAMP

router = APIRouter(prefix="/eye", tags=["Eye"])

# ──────────────────────────────────────────────────────────────────────────────
# MediaPipe (solutions 경로 폴백 포함) + 싱글톤 FaceMesh
# ──────────────────────────────────────────────────────────────────────────────
try:
    from mediapipe.solutions import face_mesh as mp_face_mesh
    from mediapipe.solutions.face_mesh_connections import (
        FACEMESH_LEFT_IRIS, FACEMESH_RIGHT_IRIS,
    )
except ModuleNotFoundError:
    from mediapipe.python.solutions import face_mesh as mp_face_mesh
    from mediapipe.python.solutions.face_mesh_connections import (
        FACEMESH_LEFT_IRIS, FACEMESH_RIGHT_IRIS,
    )

_fm: Optional[mp_face_mesh.FaceMesh] = None
def _get_fm() -> mp_face_mesh.FaceMesh:
    global _fm
    if _fm is None:
        _fm = mp_face_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=True,     # iris landmarks 포함
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    return _fm

# ──────────────────────────────────────────────────────────────────────────────
# 분석 유틸
# ──────────────────────────────────────────────────────────────────────────────
def _px(lm, w: int, h: int) -> Tuple[float, float]:
    return lm.x * w, lm.y * h

def _uniq_indices(conns: List[Tuple[int, int]]) -> List[int]:
    s = set()
    for a, b in conns:
        s.add(a); s.add(b)
    return sorted(list(s))

LEFT_IRIS_IDXS  = _uniq_indices(FACEMESH_LEFT_IRIS)
RIGHT_IRIS_IDXS = _uniq_indices(FACEMESH_RIGHT_IRIS)

# 대표 랜드마크 인덱스 (안정 쌍)
L_CORNER_OUT, L_CORNER_IN = 33, 133
L_LID_TOP,   L_LID_BOT    = 159, 145
R_CORNER_OUT, R_CORNER_IN = 362, 263
R_LID_TOP,   R_LID_BOT    = 386, 374

def _iris_center(landmarks, idxs, w, h) -> Tuple[float, float]:
    xs, ys = [], []
    for i in idxs:
        x, y = _px(landmarks[i], w, h)
        xs.append(x); ys.append(y)
    if not xs:
        return float("nan"), float("nan")
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

    x_out, y_out = _px(landmarks[c_out], w, h)
    x_in,  y_in  = _px(landmarks[c_in],  w, h)
    eye_width = max(1e-6, math.hypot(x_out - x_in, y_out - y_in))

    x_t, y_t = _px(landmarks[lid_top], w, h)
    x_b, y_b = _px(landmarks[lid_bot], w, h)
    eyelid_dist = math.hypot(x_t - x_b, y_t - y_b)

    eye_open = eyelid_dist / eye_width  # 정규화 개폐도
    ix, iy = _iris_center(landmarks, iris_idxs, w, h)

    cx, cy = (x_out + x_in) / 2.0, (y_out + y_in) / 2.0
    eye_height = max(1e-6, eyelid_dist)
    v_offset_norm = (iy - cy) / eye_height  # 위 음수, 아래 양수

    return {
        "iris_cx": ix, "iris_cy": iy,
        "eye_open": eye_open,
        "v_offset": v_offset_norm,
    }

def analyze_frame(frame_bgr: np.ndarray) -> Dict[str, Any]:
    """단일 프레임(BGR) 분석 → 간단 지표 반환."""
    if frame_bgr is None or frame_bgr.size == 0:
        return {"detected": False, "reason": "empty_frame"}

    h, w = frame_bgr.shape[:2]
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    res = _get_fm().process(rgb)
    if not res.multi_face_landmarks:
        return {"detected": False, "reason": "no_face"}

    lm = res.multi_face_landmarks[0].landmark
    L = _eye_metrics(lm, w, h, is_left=True)
    R = _eye_metrics(lm, w, h, is_left=False)

    eye_open = float(np.nanmean([L["eye_open"], R["eye_open"]]))
    v_offset = float(np.nanmean([L["v_offset"], R["v_offset"]]))
    blink_prob = float(max(0.0, min(1.0, (0.18 - eye_open) / 0.18)))  # 간단 근사

    landmarks_px: List[Dict[str, int]] = []
    for (x, y) in [(L["iris_cx"], L["iris_cy"]), (R["iris_cx"], R["iris_cy"])]:
        if not (np.isnan(x) or np.isnan(y)):
            landmarks_px.append({"x": int(x), "y": int(y)})

    return {
        "detected": True,
        "left": L,
        "right": R,
        "eye_open": eye_open,
        "v_offset": v_offset,
        "blink_prob": blink_prob,
        "landmarks": landmarks_px,
    }

def render_overlay(frame_bgr: np.ndarray, result: Dict[str, Any]) -> np.ndarray:
    """간단 오버레이(홍채 점 + 텍스트)."""
    vis = frame_bgr.copy()
    for pt in result.get("landmarks", []):
        cv2.circle(vis, (int(pt["x"]), int(pt["y"])), 3, (0, 255, 0), -1)
    cv2.putText(vis, f"eye_open:{result.get('eye_open', float('nan')):.3f}", (10, 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.75, (50, 220, 50), 2, cv2.LINE_AA)
    cv2.putText(vis, f"v_off:{result.get('v_offset', float('nan')):+.3f}", (10, 54),
                cv2.FONT_HERSHEY_SIMPLEX, 0.75, (50, 220, 50), 2, cv2.LINE_AA)
    return vis

def count_blinks(openness_series: List[float], thresh: float = 0.18, min_frames: int = 2) -> int:
    """블링크 카운트 (임계치 하강 → 상승 한 사이클 = 1회)."""
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
                closed = True; hold = 1
        else:
            if closed and hold >= min_frames:
                count += 1
            closed, hold = False, 0
    if closed and hold >= min_frames:
        count += 1
    return count

# ──────────────────────────────────────────────────────────────────────────────
# Firebase Storage 유틸
# ──────────────────────────────────────────────────────────────────────────────
def _build_download_url(path: str, token: str) -> str:
    from urllib.parse import quote
    bucket_name = bucket.name
    return f"https://firebasestorage.googleapis.com/v0/b/{bucket_name}/o/{quote(path, safe='')}?alt=media&token={token}"

def upload_bytes_to_storage(data: bytes, path: str, content_type: str) -> Dict[str, str]:
    """Firebase Storage 업로드 + downloadURL 구성."""
    token = str(uuid.uuid4())
    blob = bucket.blob(path)
    blob.upload_from_string(data, content_type=content_type)
    blob.metadata = {"firebaseStorageDownloadTokens": token}
    blob.patch()
    return {"path": path, "token": token, "url": _build_download_url(path, token)}

# ──────────────────────────────────────────────────────────────────────────────
# 이미지 엔드포인트 (분석/저장/재분석)
# ──────────────────────────────────────────────────────────────────────────────
@router.post("/analyze")
async def analyze_eye(file: UploadFile = File(...), user=Depends(get_current_user)):
    """단일 이미지 프레임 분석(서버 저장 없음)."""
    try:
        if file.content_type not in {"image/jpeg", "image/png", "image/webp"}:
            raise HTTPException(415, "Use jpg/png/webp")
        img_bytes = await file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("Invalid image data")
        out = analyze_frame(frame)
        return {"ok": True, "result": out}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/save")
async def save_eye_record(
    file: UploadFile = File(...),
    store_vis: bool = Query(True, description="분석 시각화(annotated) 이미지도 저장"),
    user=Depends(get_current_user),
):
    """이미지 분석 → 원본/시각화 Storage 저장 → Firestore 메타 기록."""
    try:
        uid = user.get("uid") if isinstance(user, dict) else getattr(user, "uid", None)
        if not uid:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user")
        if file.content_type not in {"image/jpeg", "image/png", "image/webp"}:
            raise HTTPException(415, "Use jpg/png/webp")

        img_bytes = await file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("Invalid image data")

        h, w = frame.shape[:2]

        # 분석 + (옵션)오버레이
        result: Dict[str, Any] = analyze_frame(frame)
        vis = render_overlay(frame, result) if store_vis else None

        # 인코딩
        ok_raw, raw_buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
        if not ok_raw:
            raise ValueError("Failed to encode raw image")
        vis_buf = None
        if store_vis and vis is not None:
            ok_vis, vis_buf_np = cv2.imencode(".jpg", vis, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
            if not ok_vis:
                raise ValueError("Failed to encode annotated image")
            vis_buf = vis_buf_np.tobytes()

        # 업로드 경로
        ts = int(time.time() * 1000)
        record_id = str(uuid.uuid4())
        base_path = f"users/{uid}/eye/{record_id}"
        raw_path = f"{base_path}/raw_{ts}.jpg"
        vis_path = f"{base_path}/vis_{ts}.jpg" if store_vis else None

        # Storage 업로드
        up_raw = upload_bytes_to_storage(raw_buf.tobytes(), raw_path, content_type="image/jpeg")
        up_vis: Optional[Dict[str, str]] = None
        if store_vis and vis_buf is not None:
            up_vis = upload_bytes_to_storage(vis_buf, vis_path, content_type="image/jpeg")

        # Firestore 메타데이터
        doc_ref = db.collection("users").document(uid).collection("eye_records").document(record_id)
        payload = {
            "record_id": record_id,
            "user_id": uid,
            "created_at": fb_fs.SERVER_TIMESTAMP,
            "width": w,
            "height": h,
            "analysis": result,
            "storage_path_raw": up_raw["path"],
            "download_token_raw": up_raw["token"],
            "url_raw": up_raw["url"],
            "kind": "image",
        }
        if up_vis is not None:
            payload.update({
                "storage_path_vis": up_vis["path"],
                "download_token_vis": up_vis["token"],
                "url_vis": up_vis["url"],
            })
        doc_ref.set(payload)

        return {
            "ok": True,
            "record_id": record_id,
            "urls": {"raw": up_raw["url"], "vis": up_vis["url"] if up_vis else None},
            "result": result,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/load_predict")
async def load_predict(
    record_id: str = Query(..., description="users/{uid}/eye_records/{record_id}"),
    source: str = Query("raw", pattern=r"^(raw|vis)$", description="분석 대상 이미지(raw|vis)"),
    user=Depends(get_current_user),
):
    """저장된 레코드에서 이미지를 다시 불러와 재분석."""
    try:
        uid = user.get("uid") if isinstance(user, dict) else getattr(user, "uid", None)
        if not uid:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user")

        doc_ref = db.collection("users").document(uid).collection("eye_records").document(record_id)
        snap = doc_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="record not found")
        doc = snap.to_dict()

        storage_key = "storage_path_raw" if source == "raw" else "storage_path_vis"
        path = doc.get(storage_key)
        if not path:
            raise HTTPException(status_code=400, detail=f"no {source} image for this record")

        blob = bucket.blob(path)
        img_bytes = blob.download_as_bytes()

        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("Invalid stored image data")

        result = analyze_frame(frame)

        # 결과 업데이트(옵션)
        doc_ref.update({f"analysis_{source}_recomputed": result, "updated_at": fb_fs.SERVER_TIMESTAMP})

        return {"ok": True, "record_id": record_id, "source": source, "result": result}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# ──────────────────────────────────────────────────────────────────────────────
# 동영상 엔드포인트 (PSP 스크리닝 + CSV 저장)
# ──────────────────────────────────────────────────────────────────────────────
@router.post(
    "/process",
    summary="video→MediaPipe→CSV→rule-based PSP screening",
    status_code=status.HTTP_200_OK,
)
async def process_eye_video(
    file: UploadFile = File(..., description="동영상 파일(mp4/avi/mov/webm 등)"),
    save: bool = Query(True, description="원본 영상/CSV/요약 결과를 Firebase에 저장"),
    return_overlay: bool = Query(False, description="대표 프레임 오버레이 PNG(base64) 포함"),
    step: int = Query(1, ge=1, le=10, description="프레임 샘플링 간격(성능 조절)"),
    vpp_thresh: float = Query(0.06, gt=0, description="PSP 의심 판정용 수직 피크투피크(정규화) 임계값"),
    blink_thresh: float = Query(0.18, gt=0, description="눈꺼풀 닫힘 판정 임계치(eye_open)"),
    blink_min_frames: int = Query(2, ge=1, description="블링크로 인정할 닫힘 최소 프레임"),
    max_frames: int = Query(12000, ge=10, description="최대 처리 프레임(안전장치)"),
    user=Depends(get_current_user),
):
    allowed = {
        "video/mp4", "video/avi", "video/quicktime", "video/x-matroska",
        "video/webm", "application/octet-stream"
    }
    if not file.content_type or file.content_type not in allowed:
        if (file.filename or "").lower().endswith(".wav"):
            raise HTTPException(415, detail="입력이 .wav 오디오입니다. 영상(mp4/avi/mov/webm) 파일을 업로드하세요.")
        raise HTTPException(415, detail=f"Unsupported content type: {file.content_type}")

    # 유저/경로 메타
    uid = user.get("uid") if isinstance(user, dict) else getattr(user, "uid", None)
    if not uid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user")
    now_ms = int(time.time() * 1000)
    record_id = str(uuid.uuid4())
    base_path = f"users/{uid}/eye/{record_id}"

    # 1) 원본 동영상 확보
    raw_bytes = await file.read()
    if not raw_bytes:
        raise HTTPException(400, detail="빈 파일입니다.")
    ext = os.path.splitext(file.filename or "")[1] or ".mp4"
    raw_video_path = f"{base_path}/raw_{now_ms}{ext}"

    # 2) 임시파일로 OpenCV 캡처
    with tempfile.NamedTemporaryFile(delete=True, suffix=ext) as tmp:
        tmp.write(raw_bytes); tmp.flush()
        cap = cv2.VideoCapture(tmp.name)
        if not cap.isOpened():
            raise HTTPException(400, detail="동영상을 열 수 없습니다.")

        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)

        rows: List[Dict[str, Any]] = []
        overlay_png_b64: Optional[str] = None

        fidx = 0
        kept = 0
        fm = _get_fm()
        while kept < max_frames:
            ok, frame = cap.read()
            if not ok:
                break
            if fidx % step != 0:
                fidx += 1
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            res = fm.process(rgb)
            t_sec = fidx / max(1e-6, fps)

            if res.multi_face_landmarks:
                lm = res.multi_face_landmarks[0].landmark
                L = _eye_metrics(lm, width, height, is_left=True)
                R = _eye_metrics(lm, width, height, is_left=False)
                v_offset = float(np.nanmean([L["v_offset"], R["v_offset"]]))
                eye_open = float(np.nanmean([L["eye_open"], R["eye_open"]]))

                rows.append({
                    "frame_idx": fidx,
                    "time_sec": t_sec,
                    # 왼쪽
                    "L_iris_cx": L["iris_cx"], "L_iris_cy": L["iris_cy"],
                    "L_eye_open": L["eye_open"], "L_v_offset": L["v_offset"],
                    # 오른쪽
                    "R_iris_cx": R["iris_cx"], "R_iris_cy": R["iris_cy"],
                    "R_eye_open": R["eye_open"], "R_v_offset": R["v_offset"],
                    # 대표
                    "eye_open": eye_open,
                    "v_offset": v_offset,
                })

                if return_overlay and overlay_png_b64 is None:
                    vis = frame.copy()
                    for (x, y) in [(L["iris_cx"], L["iris_cy"]), (R["iris_cx"], R["iris_cy"])]:
                        if not (np.isnan(x) or np.isnan(y)):
                            cv2.circle(vis, (int(x), int(y)), 3, (0, 255, 0), -1)
                    cv2.putText(vis, f"v_offset(avg): {v_offset:+.3f}", (10, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (50, 220, 50), 2, cv2.LINE_AA)
                    cv2.putText(vis, f"eye_open(avg): {eye_open:.3f}", (10, 60),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (50, 220, 50), 2, cv2.LINE_AA)
                    ok2, buf = cv2.imencode(".png", vis)
                    if ok2:
                        overlay_png_b64 = base64.b64encode(buf.tobytes()).decode("utf-8")
            else:
                rows.append({
                    "frame_idx": fidx,
                    "time_sec": t_sec,
                    "L_iris_cx": np.nan, "L_iris_cy": np.nan,
                    "L_eye_open": np.nan, "L_v_offset": np.nan,
                    "R_iris_cx": np.nan, "R_iris_cy": np.nan,
                    "R_eye_open": np.nan, "R_v_offset": np.nan,
                    "eye_open": np.nan, "v_offset": np.nan,
                })

            kept += 1
            fidx += 1

        cap.release()

    if len(rows) == 0:
        raise HTTPException(400, detail="유효한 프레임을 처리하지 못했습니다.")

    # 3) CSV 생성
    df = pd.DataFrame(rows).sort_values("frame_idx").reset_index(drop=True)

    # 4) 요약 통계 및 규칙 기반 판정(PSP 스크리닝)
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
    psp_reason = f"vertical_peak_to_peak({v_ptp:.3f}) < threshold({vpp_thresh:.3f})" if psp_suspected else "criteria_not_met"

    summary = {
        "frames_processed": int(len(df)),
        "fps": float(fps),
        "duration_sec_est": dur_sec,
        "vertical_offset_std": v_std,
        "vertical_peak_to_peak": v_ptp,
        "blink_count": int(blink_count),
        "blink_rate_per_min": blink_rate_per_min,
        "psp_suspected": psp_suspected,
        "psp_rule_reason": psp_reason,
        "params": {
            "step": step,
            "vpp_thresh": vpp_thresh,
            "blink_thresh": blink_thresh,
            "blink_min_frames": blink_min_frames,
            "max_frames": max_frames,
        },
    }

    # 5) (옵션) 저장
    storage_info = {
        "raw_video_path": None,
        "csv_path": None,
        "overlay_path": None,
        "raw_video_url": None,
        "csv_url": None,
        "overlay_url": None,
    }
    firestore_doc_id = None

    if save:
        # 동영상 업로드
        up_raw = upload_bytes_to_storage(raw_bytes, raw_video_path, content_type=file.content_type or "video/mp4")
        storage_info["raw_video_path"] = up_raw["path"]
        storage_info["raw_video_url"] = up_raw["url"]

        # CSV 업로드
        csv_path = f"{base_path}/trace_{now_ms}.csv"
        csv_buf = io.StringIO()
        df.to_csv(csv_buf, index=False)
        up_csv = upload_bytes_to_storage(csv_buf.getvalue().encode("utf-8"), csv_path, content_type="text/csv")
        storage_info["csv_path"] = up_csv["path"]
        storage_info["csv_url"] = up_csv["url"]

        # Firestore 문서
        doc = {
            "record_id": record_id,
            "user_id": uid,
            "created_at": fb_fs.SERVER_TIMESTAMP,
            "kind": "video",
            "video_meta": {"width": width, "height": height, "fps": fps},
            "summary": summary,
            "storage_path_raw_video": up_raw["path"],
            "url_raw_video": up_raw["url"],
            "storage_path_csv": up_csv["path"],
            "url_csv": up_csv["url"],
        }
        ref = db.collection("users").document(uid).collection("eye_records").document(record_id)
        ref.set(doc)
        firestore_doc_id = record_id

    return {
        "ok": True,
        "saved": save,
        "record_id": firestore_doc_id,
        "storage": storage_info,
        "summary": summary,
        "overlay_base64_png": overlay_png_b64 if return_overlay else None,
    }
