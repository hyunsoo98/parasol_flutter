import json
import boto3
import base64
import cv2
import math
import numpy as np
import pandas as pd
import io
import os
import uuid
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime
import traceback

# AWS 서비스 클라이언트 초기화
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# 환경 변수에서 설정 읽기
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'parkinson-analysis')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# MediaPipe 초기화 (Lambda 환경에서는 싱글톤 패턴 사용)
try:
    import mediapipe as mp
    mp_face_mesh = mp.solutions.face_mesh
    from mediapipe.python.solutions.face_mesh_connections import (
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

# 유틸리티 함수들
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

def analyze_frame(frame_bgr: np.ndarray) -> Dict[str, Any]:
    """단일 프레임 분석"""
    if frame_bgr is None or frame_bgr.size == 0:
        return {"detected": False, "reason": "empty_frame"}

    face_mesh = get_face_mesh()
    if face_mesh is None:
        return {"detected": False, "reason": "mediapipe_unavailable"}

    h, w = frame_bgr.shape[:2]
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    
    try:
        results = face_mesh.process(rgb)
        if not results.multi_face_landmarks:
            return {"detected": False, "reason": "no_face"}

        landmarks = results.multi_face_landmarks[0].landmark
        left_metrics = _eye_metrics(landmarks, w, h, is_left=True)
        right_metrics = _eye_metrics(landmarks, w, h, is_left=False)

        eye_open = float(np.nanmean([left_metrics["eye_open"], right_metrics["eye_open"]]))
        v_offset = float(np.nanmean([left_metrics["v_offset"], right_metrics["v_offset"]]))
        blink_prob = float(max(0.0, min(1.0, (0.18 - eye_open) / 0.18)))

        landmarks_px = []
        for (x, y) in [(left_metrics["iris_cx"], left_metrics["iris_cy"]), 
                      (right_metrics["iris_cx"], right_metrics["iris_cy"])]:
            if not (np.isnan(x) or np.isnan(y)):
                landmarks_px.append({"x": int(x), "y": int(y)})

        return {
            "detected": True,
            "left": left_metrics,
            "right": right_metrics,
            "eye_open": eye_open,
            "v_offset": v_offset,
            "blink_prob": blink_prob,
            "landmarks": landmarks_px,
        }
    except Exception as e:
        return {"detected": False, "reason": f"analysis_error: {str(e)}"}

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

def upload_to_s3(data: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
    """S3에 데이터 업로드"""
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=data,
            ContentType=content_type
        )
        return f"s3://{S3_BUCKET}/{key}"
    except Exception as e:
        raise Exception(f"S3 upload failed: {str(e)}")

def download_from_s3(key: str) -> bytes:
    """S3에서 데이터 다운로드"""
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=key)
        return response['Body'].read()
    except Exception as e:
        raise Exception(f"S3 download failed: {str(e)}")

def save_to_dynamodb(analysis_id: str, user_id: str, result_data: Dict[str, Any]) -> None:
    """DynamoDB에 분석 결과 저장"""
    try:
        table.put_item(
            Item={
                'analysisId': analysis_id,
                'testType': 'eye-tracking',
                'userId': user_id,
                'timestamp': int(datetime.now().timestamp()),
                'results': result_data,
                'status': 'completed'
            }
        )
    except Exception as e:
        raise Exception(f"DynamoDB save failed: {str(e)}")

def lambda_handler(event, context):
    """
    AWS Lambda 메인 핸들러
    
    예상 입력:
    {
        "action": "analyze_image" | "analyze_video" | "process_file",
        "file_data": "base64_encoded_data",
        "file_name": "file.mp4",
        "user_id": "user123",
        "parameters": {
            "step": 1,
            "vpp_thresh": 0.06,
            "blink_thresh": 0.18,
            "max_frames": 12000
        }
    }
    """
    try:
        # CORS 헤더
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }

        # OPTIONS 요청 처리
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'OK'})
            }

        # 요청 본문 파싱
        if 'body' in event:
            if event.get('isBase64Encoded', False):
                body = base64.b64decode(event['body']).decode('utf-8')
            else:
                body = event['body']
            request_data = json.loads(body) if isinstance(body, str) else body
        else:
            request_data = event

        # 필수 파라미터 확인
        action = request_data.get('action')
        if not action:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing action parameter'})
            }

        user_id = request_data.get('user_id', 'anonymous')
        analysis_id = str(uuid.uuid4())

        # 액션별 처리
        if action == 'analyze_image':
            return handle_analyze_image(request_data, user_id, analysis_id, headers)
        elif action == 'analyze_video':
            return handle_analyze_video(request_data, user_id, analysis_id, headers)
        elif action == 'process_s3_file':
            return handle_process_s3_file(request_data, user_id, analysis_id, headers)
        else:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }

    except Exception as e:
        print(f"Lambda handler error: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }

def handle_analyze_image(request_data: Dict, user_id: str, analysis_id: str, headers: Dict) -> Dict:
    """이미지 분석 처리"""
    try:
        file_data = request_data.get('file_data')
        if not file_data:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing file_data'})
            }

        # Base64 디코딩
        image_data = base64.b64decode(file_data)
        
        # OpenCV로 이미지 디코딩
        nparr = np.frombuffer(image_data, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid image data'})
            }

        # 분석 수행
        result = analyze_frame(frame)
        
        # 결과 저장
        save_to_dynamodb(analysis_id, user_id, {
            'type': 'image',
            'analysis': result
        })

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'analysis_id': analysis_id,
                'result': result,
                'status': 'success'
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Image analysis failed: {str(e)}'})
        }

def handle_analyze_video(request_data: Dict, user_id: str, analysis_id: str, headers: Dict) -> Dict:
    """동영상 분석 처리"""
    try:
        file_data = request_data.get('file_data')
        if not file_data:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing file_data'})
            }

        # 파라미터 추출
        params = request_data.get('parameters', {})
        step = params.get('step', 1)
        vpp_thresh = params.get('vpp_thresh', 0.06)
        blink_thresh = params.get('blink_thresh', 0.18)
        max_frames = params.get('max_frames', 12000)
        blink_min_frames = params.get('blink_min_frames', 2)

        # Base64 디코딩 및 임시 파일로 저장
        video_data = base64.b64decode(file_data)
        
        # S3에 원본 비디오 저장
        video_key = f"users/{user_id}/eye/{analysis_id}/raw_video.mp4"
        upload_to_s3(video_data, video_key, 'video/mp4')

        # 임시 파일로 비디오 처리
        import tempfile
        with tempfile.NamedTemporaryFile(delete=True, suffix='.mp4') as tmp:
            tmp.write(video_data)
            tmp.flush()
            
            cap = cv2.VideoCapture(tmp.name)
            if not cap.isOpened():
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({'error': 'Cannot open video file'})
                }

            fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)

            rows = []
            frame_idx = 0
            processed = 0
            face_mesh = get_face_mesh()

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

            cap.release()

        if not rows:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'No valid frames processed'})
            }

        # CSV 생성
        df = pd.DataFrame(rows).sort_values("frame_idx").reset_index(drop=True)
        csv_buffer = io.StringIO()
        df.to_csv(csv_buffer, index=False)
        csv_data = csv_buffer.getvalue().encode('utf-8')
        
        # S3에 CSV 저장
        csv_key = f"users/{user_id}/eye/{analysis_id}/analysis_results.csv"
        upload_to_s3(csv_data, csv_key, 'text/csv')

        # 통계 계산
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
            "frames_processed": len(df),
            "fps": fps,
            "duration_sec_est": dur_sec,
            "vertical_offset_std": v_std,
            "vertical_peak_to_peak": v_ptp,
            "blink_count": blink_count,
            "blink_rate_per_min": blink_rate_per_min,
            "psp_suspected": psp_suspected,
            "psp_rule_reason": psp_reason,
            "video_meta": {"width": width, "height": height, "fps": fps}
        }

        # 결과 저장
        save_to_dynamodb(analysis_id, user_id, {
            'type': 'video',
            'summary': summary,
            'video_path': video_key,
            'csv_path': csv_key
        })

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'analysis_id': analysis_id,
                'summary': summary,
                'video_path': video_key,
                'csv_path': csv_key,
                'status': 'success'
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Video analysis failed: {str(e)}'})
        }

def handle_process_s3_file(request_data: Dict, user_id: str, analysis_id: str, headers: Dict) -> Dict:
    """S3에 저장된 파일 처리"""
    try:
        s3_key = request_data.get('s3_key')
        if not s3_key:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing s3_key'})
            }

        # S3에서 파일 다운로드
        file_data = download_from_s3(s3_key)
        
        # 파일 타입에 따라 처리
        file_name = request_data.get('file_name', '')
        if file_name.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
            # 이미지 처리
            request_data['file_data'] = base64.b64encode(file_data).decode('utf-8')
            request_data['action'] = 'analyze_image'
            return handle_analyze_image(request_data, user_id, analysis_id, headers)
        else:
            # 비디오 처리
            request_data['file_data'] = base64.b64encode(file_data).decode('utf-8')
            request_data['action'] = 'analyze_video'
            return handle_analyze_video(request_data, user_id, analysis_id, headers)

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'S3 file processing failed: {str(e)}'})
        }