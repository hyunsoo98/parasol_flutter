"""
AWS Lambda: Finger Tapping 비디오 분석 처리
- SQS에서 메시지 수신
- S3에서 비디오 다운로드  
- MediaPipe로 손 감지 및 finger tapping 분석
- 기존 AdaBoost 모델로 파킨슨병 예측
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
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'finger-tapping-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# MediaPipe 초기화
try:
    import mediapipe as mp
    mp_hands = mp.solutions.hands
    mp_draw = mp.solutions.drawing_utils
    HAND_CONNECTIONS = mp_hands.HAND_CONNECTIONS
except ImportError:
    mp_hands = None
    mp_draw = None
    HAND_CONNECTIONS = []

# ML 모델 로딩
try:
    from joblib import load
    import feature_extraction as fe
    # 모델은 /opt/에서 로드 (Lambda 레이어에 포함)
    MODEL_PATH = "best_pipeline_recall_AdaBoost.joblib"
except ImportError:
    load = None
    fe = None
    MODEL_PATH = None

# 전역 변수로 모델 캐시
_model = None

def get_model():
    """모델 싱글톤"""
    global _model
    if _model is None and load is not None and os.path.exists(MODEL_PATH):
        _model = load(MODEL_PATH)
    return _model

# 기존 코드에서 핵심 함수들 가져오기
def distance(x0, y0, x1, y1):
    """거리 계산"""
    return math.sqrt((x0-x1)**2+(y0-y1)**2)

def angle_deg(ax, ay, bx, by):
    """각도 계산 (degree)"""
    dot = ax*bx + ay*by
    na = np.hypot(ax, ay)
    nb = np.hypot(bx, by)
    if na == 0 or nb == 0:
        return -1.0
    c = np.clip(dot/(na*nb), -1.0, 1.0)
    return float(np.degrees(np.arccos(c)))

def collect_timeseries(session_landmarks, frame_size, duration_s):
    """시계열 데이터 수집 및 전처리"""
    w, h = frame_size
    per_hand = {}

    for hand, frames in session_landmarks.items():
        D_raw, W_raw = [], []

        for lm in frames:
            if lm is None:
                D_raw.append(np.nan)
                W_raw.append((np.nan, np.nan))
                continue

            # MediaPipe 랜드마크 인덱스: wrist(0), cmc(1), thumb_tip(4), index_tip(8)
            w_lm, cmc, th, idx = lm[0], lm[1], lm[4], lm[8]
            wx, wy = int(w_lm.x * w), int(w_lm.y * h)
            tx, ty = int(th.x * w), int(th.y * h)
            ix, iy = int(idx.x * w), int(idx.y * h)

            # 각도 계산 (엄지-손목-검지)
            ang = angle_deg(tx - wx, ty - wy, ix - wx, iy - wy)
            D_raw.append(ang)

            # 정규화된 위치
            cmx, cmy = int(cmc.x * w), int(cmc.y * h)
            wnorm = distance(wx, wy, cmx, cmy) or np.nan
            W_raw.append((wx / wnorm, wy / wnorm) if not np.isnan(wnorm) else (np.nan, np.nan))

        # NaN 보간 처리
        df_tmp = pd.DataFrame({
            "D_raw": D_raw,
            "W_raw_x": [w[0] for w in W_raw],
            "W_raw_y": [w[1] for w in W_raw]
        })
        df_tmp = df_tmp.interpolate(limit_direction="both")

        # numpy로 변환
        D_raw = df_tmp["D_raw"].to_numpy()
        W_raw = list(zip(df_tmp["W_raw_x"], df_tmp["W_raw_y"]))

        per_hand[hand] = {
            "D_raw": D_raw,
            "W_raw": W_raw,
            "num_frames": len(frames),
            "duration": float(duration_s)
        }

    return per_hand

def process_video_analysis(video_path: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
    """비디오 분석 메인 함수"""
    
    # 파라미터 추출
    target_taps = parameters.get('target_taps', 10)
    max_duration = parameters.get('max_duration', 30)
    threshold = parameters.get('threshold', 0.50)
    delta = parameters.get('delta', 0.05)
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise Exception("비디오 파일을 열 수 없습니다")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

    session_landmarks = {"Left": [], "Right": []}
    last_release = {"Left": True, "Right": True}
    count = {"Left": 0, "Right": 0}
    frame_idx = 0
    
    hands = None
    if mp_hands:
        hands = mp_hands.Hands(
            static_image_mode=False,
            max_num_hands=2,
            model_complexity=1,
            min_detection_confidence=0.6,
            min_tracking_confidence=0.8
        )
    else:
        raise Exception("MediaPipe를 사용할 수 없습니다")

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
                
            if frame_idx >= total_frames:
                break

            h, w = frame.shape[:2]
            min_side = min(w, h)
            on_th = min_side * 0.035  # 접촉 임계값
            off_th = min_side * 0.06  # 해제 임계값

            # MediaPipe 처리
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = hands.process(rgb)

            current = {"Left": None, "Right": None}

            if results.multi_hand_landmarks and results.multi_handedness:
                for i, hd in enumerate(results.multi_handedness):
                    label = hd.classification[0].label  # 'Left' 또는 'Right'
                    score = hd.classification[0].score
                    if score < 0.5:
                        continue
                    
                    lm = results.multi_hand_landmarks[i].landmark
                    current[label] = lm

                    # 탭 감지 (엄지-검지 거리)
                    tx, ty = int(lm[4].x * w), int(lm[4].y * h)
                    ix, iy = int(lm[8].x * w), int(lm[8].y * h)
                    dpx = float(np.hypot(tx - ix, ty - iy))
                    
                    touching = dpx < on_th
                    if last_release[label] and touching:
                        count[label] += 1
                        last_release[label] = False
                    if dpx > off_th:
                        last_release[label] = True

            session_landmarks["Left"].append(current["Left"])
            session_landmarks["Right"].append(current["Right"])
            
            frame_idx += 1
            
            # 최대 시간 체크
            elapsed = frame_idx / fps
            if elapsed >= max_duration:
                break
                
            # 목표 달성 체크
            if count["Left"] >= target_taps and count["Right"] >= target_taps:
                break

    finally:
        cap.release()
        if hands:
            hands.close()

    if frame_idx == 0:
        raise Exception("처리된 프레임이 없습니다")

    # 특징 추출
    frame_size = (width, height)
    duration = frame_idx / fps
    
    data_by_hand = collect_timeseries(session_landmarks, frame_size, duration)
    
    # 각 손별 특징 추출
    hand_features = []
    for label in ["Left", "Right"]:
        try:
            if fe and hasattr(fe, 'get_final_features'):
                feats = fe.get_final_features(data_by_hand[label])
                feats["hand"] = label.lower()
                hand_features.append(feats)
            else:
                # 기본 특징들만 추출
                basic_feats = {
                    "hand": label.lower(),
                    "tap_count": count[label],
                    "duration": duration,
                    "tap_rate": count[label] / duration if duration > 0 else 0
                }
                hand_features.append(basic_feats)
        except Exception as e:
            print(f"[WARN] {label} 특징 추출 실패: {e}")
            basic_feats = {
                "hand": label.lower(),
                "tap_count": count[label],
                "duration": duration,
                "tap_rate": count[label] / duration if duration > 0 else 0
            }
            hand_features.append(basic_feats)

    # 모델 예측
    predictions = []
    model = get_model()
    
    if model is not None and hand_features:
        try:
            df_features = pd.DataFrame(hand_features)
            
            # 모델 예측
            if hasattr(model, 'predict_proba'):
                y_prob = model.predict_proba(df_features)[:, 1]
                y_pred = (y_prob >= threshold).astype(int)
            else:
                y_pred = model.predict(df_features)
                y_prob = y_pred.astype(float)
            
            # 결과 정리
            for i, (_, row) in enumerate(df_features.iterrows()):
                pred_result = {
                    "hand": row["hand"],
                    "probability": float(y_prob[i]) if len(y_prob) > i else 0.0,
                    "prediction": int(y_pred[i]) if len(y_pred) > i else 0,
                    "tap_count": count[row["hand"].title()],
                    "label": "파킨슨병(PD)" if (y_pred[i] if len(y_pred) > i else 0) == 1 else "정상(HC)"
                }
                predictions.append(pred_result)
            
            # Noisy-OR 결합
            probs = [p["probability"] for p in predictions]
            combined_prob = 1.0 - np.prod([1.0 - p for p in probs]) if probs else 0.0
            final_prediction = int(combined_prob >= threshold)
            
        except Exception as e:
            print(f"모델 예측 실패: {e}")
            # 폴백: 간단한 규칙 기반 예측
            predictions = []
            for label in ["Left", "Right"]:
                tap_rate = count[label] / duration if duration > 0 else 0
                # 간단한 규칙: 탭 속도가 너무 느리면 파킨슨병 의심
                prob = 1.0 - min(1.0, tap_rate / 2.0)  # 2탭/초 이하면 의심
                pred = int(prob >= threshold)
                predictions.append({
                    "hand": label.lower(),
                    "probability": prob,
                    "prediction": pred,
                    "tap_count": count[label],
                    "label": "파킨슨병(PD)" if pred == 1 else "정상(HC)"
                })
            
            probs = [p["probability"] for p in predictions]
            combined_prob = 1.0 - np.prod([1.0 - p for p in probs]) if probs else 0.0
            final_prediction = int(combined_prob >= threshold)
    
    else:
        # 모델이 없는 경우 기본 분석만
        predictions = []
        for label in ["Left", "Right"]:
            predictions.append({
                "hand": label.lower(),
                "probability": 0.0,
                "prediction": 0,
                "tap_count": count[label],
                "label": "분석불가"
            })
        combined_prob = 0.0
        final_prediction = 0

    return {
        "video_meta": {
            "width": width,
            "height": height,
            "fps": fps,
            "total_frames": total_frames,
            "analyzed_frames": frame_idx
        },
        "analysis_params": parameters,
        "duration_sec": duration,
        "tap_counts": count,
        "hand_predictions": predictions,
        "combined_result": {
            "probability": combined_prob,
            "prediction": final_prediction,
            "label": "파킨슨병(PD)" if final_prediction == 1 else "정상(HC)"
        },
        "raw_features": hand_features
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
            
            print(f"Finger Tapping 분석 시작: {analysis_id}")
            
            # 진행률 업데이트 (10%)
            update_progress(analysis_id, 10, "비디오 다운로드 중...")
            
            # S3에서 비디오 다운로드
            with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp_file:
                try:
                    s3_client.download_fileobj(s3_bucket, s3_key, tmp_file)
                    tmp_file.flush()
                    video_path = tmp_file.name
                    
                    # 진행률 업데이트 (30%)
                    update_progress(analysis_id, 30, "Finger Tapping 분석 중...")
                    
                    # 비디오 분석 실행
                    result = process_video_analysis(video_path, parameters)
                    
                    # 진행률 업데이트 (80%)
                    update_progress(analysis_id, 80, "결과 저장 중...")
                    
                    # 결과 CSV를 S3에 저장
                    if 'raw_features' in result:
                        csv_df = pd.DataFrame(result['raw_features'])
                        csv_buffer = io.StringIO()
                        csv_df.to_csv(csv_buffer, index=False)
                        csv_data = csv_buffer.getvalue().encode('utf-8')
                        
                        csv_s3_key = f"{S3_PREFIX}results/{user_id}/finger-tapping/{analysis_id}/analysis_results.csv"
                        s3_client.put_object(
                            Bucket=s3_bucket,
                            Key=csv_s3_key,
                            Body=csv_data,
                            ContentType='text/csv'
                        )
                        result['csv_s3_key'] = csv_s3_key
                        
                        # raw_features는 DynamoDB에 저장하지 않음 (크기 제한)
                        del result['raw_features']
                    
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
                    
                    print(f"Finger Tapping 분석 완료: {analysis_id}")
                    
                finally:
                    # 임시 파일 정리
                    if os.path.exists(tmp_file.name):
                        os.unlink(tmp_file.name)
                        
        except Exception as e:
            error_message = f"Finger Tapping 분석 실패: {str(e)}"
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