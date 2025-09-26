# EC2 Eye Tracking Worker - SQS 기반
# 기존 lambda_eye_process.py를 EC2 SQS 워커로 전환

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
import time
import logging
import tempfile
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime
import traceback

# 로깅 설정
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# AWS 서비스 클라이언트 초기화
s3_client = boto3.client('s3', region_name='us-west-1')
dynamodb = boto3.resource('dynamodb', region_name='us-west-1')
sqs = boto3.client('sqs', region_name='us-west-1')

# 환경 변수에서 설정 읽기
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'analyses')
SQS_QUEUE_NAME = 'eye-tracking-queue'

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# SQS 큐 URL 가져오기
try:
    response = sqs.get_queue_url(QueueName=SQS_QUEUE_NAME)
    QUEUE_URL = response['QueueUrl']
    logger.info(f"Connected to SQS queue: {SQS_QUEUE_NAME}")
except Exception as e:
    logger.error(f"Failed to connect to SQS queue {SQS_QUEUE_NAME}: {e}")
    QUEUE_URL = None

# MediaPipe 초기화 (EC2 환경에서 싱글톤 패턴 사용)
try:
    import mediapipe as mp
    mp_face_mesh = mp.solutions.face_mesh
    from mediapipe.python.solutions.face_mesh_connections import (
        FACEMESH_LEFT_IRIS, FACEMESH_RIGHT_IRIS,
    )
    logger.info("MediaPipe successfully imported")
except ImportError:
    logger.error("MediaPipe import failed - will use fallback")
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
        logger.info("FaceMesh model initialized")
    return _face_mesh_model

# 유틸리티 함수들 (기존 lambda와 동일)
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

def download_s3_to_file(s3_path: str, local_path: str) -> bool:
    """S3에서 파일로 직접 다운로드"""
    try:
        # s3://bucket/key 형식에서 bucket과 key 분리
        if s3_path.startswith('s3://'):
            s3_path = s3_path[5:]

        if '/' in s3_path:
            bucket, key = s3_path.split('/', 1)
        else:
            bucket = S3_BUCKET
            key = s3_path

        s3_client.download_file(bucket, key, local_path)
        logger.info(f"Downloaded {s3_path} to {local_path}")
        return True
    except Exception as e:
        logger.error(f"S3 download failed: {e}")
        return False

def save_to_dynamodb(analysis_id: str, user_id: str, result_data: Dict[str, Any], status: str = 'completed') -> None:
    """DynamoDB에 분석 결과 저장"""
    try:
        table.update_item(
            Key={'analysis_id': analysis_id},
            UpdateExpression="SET #status = :status, updated_at = :timestamp, results = :results",
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': status,
                ':timestamp': int(datetime.now().timestamp()),
                ':results': result_data
            }
        )
        logger.info(f"Saved results to DynamoDB for {analysis_id}")
    except Exception as e:
        logger.error(f"DynamoDB save failed: {e}")
        raise Exception(f"DynamoDB save failed: {str(e)}")

def update_status(analysis_id: str, status: str) -> None:
    """DynamoDB 상태만 업데이트"""
    try:
        table.update_item(
            Key={'analysis_id': analysis_id},
            UpdateExpression="SET #status = :status, updated_at = :timestamp",
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': status,
                ':timestamp': int(datetime.now().timestamp())
            }
        )
        logger.info(f"Updated status to {status} for {analysis_id}")
    except Exception as e:
        logger.error(f"Status update failed: {e}")

def process_video_analysis(message_data: Dict[str, Any]) -> Dict[str, Any]:
    """비디오 분석 처리 - 기존 Lambda 로직을 EC2용으로 수정"""
    analysis_id = message_data['analysis_id']
    user_id = message_data['user_id']
    s3_path = message_data['s3_path']

    # 파라미터 추출
    params = message_data.get('parameters', {})
    step = params.get('step', 1)
    vpp_thresh = params.get('vpp_thresh', 0.06)
    blink_thresh = params.get('blink_thresh', 0.18)
    max_frames = params.get('max_frames', 12000)
    blink_min_frames = params.get('blink_min_frames', 2)

    logger.info(f"Starting video analysis for {analysis_id}")

    # 상태를 processing으로 변경
    update_status(analysis_id, 'processing')

    try:
        # 임시 파일로 비디오 다운로드
        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as tmp_file:
            video_path = tmp_file.name

        # S3에서 비디오 다운로드
        if not download_s3_to_file(s3_path, video_path):
            raise Exception("Failed to download video from S3")

        # OpenCV로 비디오 처리
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise Exception('Cannot open video file')

        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)

        rows = []
        frame_idx = 0
        processed = 0
        face_mesh = get_face_mesh()

        logger.info(f"Processing video: {width}x{height} at {fps} FPS")

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

            # 진행률 로깅 (매 1000프레임마다)
            if processed % 1000 == 0:
                logger.info(f"Processed {processed}/{max_frames} frames")

        cap.release()
        os.unlink(video_path)  # 임시 파일 정리

        if not rows:
            raise Exception('No valid frames processed')

        # CSV 생성 및 S3 업로드
        df = pd.DataFrame(rows).sort_values("frame_idx").reset_index(drop=True)
        csv_buffer = io.StringIO()
        df.to_csv(csv_buffer, index=False)
        csv_data = csv_buffer.getvalue().encode('utf-8')

        # S3에 결과 CSV 저장 (API 아키텍처 문서 구조에 맞춤)
        # parkinson-analysis-seoul-ht-09/eye-tracking/processed/{analysis_id}/
        csv_key = f"eye-tracking/processed/{analysis_id}/analysis_results.csv"
        features_key = f"eye-tracking/processed/{analysis_id}/features.json"
        results_key = f"eye-tracking/results/{analysis_id}/analysis.json"

        csv_s3_path = upload_to_s3(csv_data, csv_key, 'text/csv')

        # 추가로 features.json 형태로도 저장
        features_data = {
            "frames_data": df.to_dict('records'),
            "metadata": {
                "total_frames": len(df),
                "fps": fps,
                "video_dimensions": {"width": width, "height": height}
            }
        }
        features_json = json.dumps(features_data, ensure_ascii=False).encode('utf-8')
        features_s3_path = upload_to_s3(features_json, features_key, 'application/json')

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

        # API 아키텍처 문서 구조에 맞춰 results.json도 생성
        results_json_data = {
            "analysis_id": analysis_id,
            "user_id": user_id,
            "analysis_type": "eye-tracking",
            "timestamp": int(time.time()),
            "summary": summary,
            "parameters": params
        }
        results_json = json.dumps(results_json_data, ensure_ascii=False).encode('utf-8')
        results_s3_path = upload_to_s3(results_json, results_key, 'application/json')

        result_data = {
            'type': 'eye-tracking',
            'testType': 'eye-tracking',  # DynamoDB 스키마에 맞춤
            'summary': summary,
            'csv_path': csv_s3_path,
            's3_paths': {
                'raw': message_data.get('s3_path', ''),
                'processed': features_s3_path,
                'results': results_s3_path
            },
            'parameters': params,
            'analysis_type': 'eye-tracking'
        }

        # 결과를 DynamoDB에 저장
        save_to_dynamodb(analysis_id, user_id, result_data, 'completed')

        logger.info(f"Eye tracking analysis completed for {analysis_id}")
        return result_data

    except Exception as e:
        logger.error(f"Video analysis failed for {analysis_id}: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        update_status(analysis_id, 'failed')
        raise

class EyeTrackingWorker:
    """EC2 SQS 기반 Eye Tracking 워커"""

    def __init__(self):
        self.queue_url = QUEUE_URL
        if not self.queue_url:
            raise Exception("Failed to initialize SQS queue")

        # FaceMesh 모델 미리 로드
        face_mesh = get_face_mesh()
        if face_mesh:
            logger.info("Eye Tracking Worker initialized successfully")
        else:
            logger.warning("Eye Tracking Worker initialized without MediaPipe")

    def start_polling(self):
        """SQS 메시지 폴링 시작"""
        logger.info("Starting SQS message polling...")

        while True:
            try:
                # Long Polling으로 메시지 받기
                response = sqs.receive_message(
                    QueueUrl=self.queue_url,
                    MaxNumberOfMessages=1,
                    WaitTimeSeconds=20,  # Long polling
                    MessageAttributeNames=['All']
                )

                if 'Messages' in response:
                    for message in response['Messages']:
                        if self.process_message(message):
                            self.delete_message(message)
                        else:
                            logger.warning("Message processing failed, will retry")
                else:
                    logger.debug("No messages available, continuing to poll...")

            except Exception as e:
                logger.error(f"Error in polling loop: {e}")
                time.sleep(30)

    def process_message(self, message) -> bool:
        """SQS 메시지 처리"""
        try:
            message_body = json.loads(message['Body'])
            analysis_id = message_body.get('analysis_id')

            logger.info(f"Processing eye tracking analysis: {analysis_id}")

            # 비디오 분석 수행
            result = process_video_analysis(message_body)

            logger.info(f"Successfully completed analysis: {analysis_id}")
            return True

        except Exception as e:
            logger.error(f"Error processing message: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            return False

    def delete_message(self, message):
        """SQS 메시지 삭제"""
        try:
            sqs.delete_message(
                QueueUrl=self.queue_url,
                ReceiptHandle=message['ReceiptHandle']
            )
            logger.debug("Message deleted successfully")
        except Exception as e:
            logger.error(f"Error deleting message: {e}")

def main():
    """메인 실행 함수"""
    try:
        worker = EyeTrackingWorker()
        worker.start_polling()
    except KeyboardInterrupt:
        logger.info("Worker stopped by user")
    except Exception as e:
        logger.error(f"Worker failed: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")

if __name__ == "__main__":
    main()