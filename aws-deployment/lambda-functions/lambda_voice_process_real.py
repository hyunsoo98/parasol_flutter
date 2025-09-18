"""
AWS Lambda: Voice Analysis 실제 MultiBranch 모델 처리
- 다운로드된 실제 PyTorch 모델 사용
- CNN + BiGRU + MLP 통합 아키텍처
- HC/PD/MSA/PSP 다중 분류
"""

import json
import boto3
import time
import tempfile
import numpy as np
import os
from typing import Any, Dict, List, Optional
import traceback

# AWS 클라이언트 초기화
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# 환경 변수
S3_BUCKET = os.environ.get('S3_BUCKET', 'seoul-ht-09')
S3_PREFIX = os.environ.get('S3_PREFIX', 'audio/voice-analysis/')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'voice-analysis-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# 실제 MultiBranch 모델 로딩
try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    import librosa
    from scipy.stats import skew, kurtosis

    # 모델 파일 경로
    MODEL_PATH = os.environ.get('MODEL_PATH', 'model_ensemble_avg.pt')

    # 모델 로딩 플래그
    model_loaded = False
    voice_model = None
    label2idx = None
    cfg = None

except ImportError as e:
    print(f"Model libraries not available: {e}")
    model_loaded = False

class MultiBranchNet(nn.Module):
    """실제 다운로드된 모델과 동일한 아키텍처"""

    def __init__(self, tab_dim: int, num_classes: int = 2):
        super().__init__()
        self.tab_dim = tab_dim
        self.num_classes = num_classes

        # CNN branch (Mel-spectrogram)
        self.cnn_conv1 = nn.Conv2d(1, 32, kernel_size=(3, 3), padding=1)
        self.cnn_conv2 = nn.Conv2d(32, 64, kernel_size=(3, 3), padding=1)
        self.cnn_conv3 = nn.Conv2d(64, 128, kernel_size=(3, 3), padding=1)
        self.cnn_pool = nn.AdaptiveAvgPool2d((1, 1))
        self.cnn_dropout = nn.Dropout(0.4)

        # BiGRU branch (MFCC sequences)
        mfcc_dim = 40 * 3  # MFCC + Δ + ΔΔ
        self.rnn = nn.GRU(mfcc_dim, 64, num_layers=2, batch_first=True,
                         dropout=0.3, bidirectional=True)
        self.rnn_dropout = nn.Dropout(0.4)

        # MLP branch (Tabular features)
        self.mlp = nn.Sequential(
            nn.Linear(tab_dim, 128),
            nn.ReLU(),
            nn.Dropout(0.4),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Dropout(0.3)
        )

        # Final classifier
        combined_dim = 128 + 128 + 64  # CNN + BiGRU + MLP
        self.classifier = nn.Sequential(
            nn.Linear(combined_dim, 128),
            nn.ReLU(),
            nn.Dropout(0.5),
            nn.Linear(128, num_classes)
        )

    def forward(self, mel_spec, mfcc_seq, tabular):
        # CNN branch
        cnn_out = F.relu(self.cnn_conv1(mel_spec))
        cnn_out = F.max_pool2d(cnn_out, 2)
        cnn_out = F.relu(self.cnn_conv2(cnn_out))
        cnn_out = F.max_pool2d(cnn_out, 2)
        cnn_out = F.relu(self.cnn_conv3(cnn_out))
        cnn_out = self.cnn_pool(cnn_out)
        cnn_out = cnn_out.view(cnn_out.size(0), -1)
        cnn_out = self.cnn_dropout(cnn_out)

        # BiGRU branch
        rnn_out, _ = self.rnn(mfcc_seq)
        rnn_out = rnn_out[:, -1, :]  # Last timestep
        rnn_out = self.rnn_dropout(rnn_out)

        # MLP branch
        mlp_out = self.mlp(tabular)

        # Combine all branches
        combined = torch.cat([cnn_out, rnn_out, mlp_out], dim=1)
        output = self.classifier(combined)

        return output

def load_voice_model():
    """실제 사전 훈련된 모델 로드"""
    global model_loaded, voice_model, label2idx, cfg

    try:
        if not os.path.exists(MODEL_PATH):
            print(f"Model file not found: {MODEL_PATH}")
            return False

        # 모델 체크포인트 로드
        checkpoint = torch.load(MODEL_PATH, map_location='cpu')

        # 설정 정보 추출
        label2idx = checkpoint['label2idx']
        cfg = checkpoint.get('cfg', {})
        tab_dim = checkpoint['tab_dim']
        num_classes = len(label2idx)

        # 모델 인스턴스 생성 및 가중치 로드
        voice_model = MultiBranchNet(tab_dim=tab_dim, num_classes=num_classes)
        voice_model.load_state_dict(checkpoint['model'])
        voice_model.eval()

        print(f"Voice model loaded successfully")
        print(f"Classes: {label2idx}")
        print(f"Tab dim: {tab_dim}")

        model_loaded = True
        return True

    except Exception as e:
        print(f"Model loading failed: {str(e)}")
        model_loaded = False
        return False

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    SQS 트리거로 실행되는 메인 핸들러
    """

    try:
        # SQS 메시지 처리
        for record in event['Records']:
            message_body = json.loads(record['body'])

            analysis_id = message_body['analysis_id']
            user_id = message_body['user_id']
            s3_bucket = message_body['s3_bucket']
            s3_key = message_body['s3_key']
            parameters = message_body.get('parameters', {})

            print(f"Processing voice analysis: {analysis_id}")

            # 모델 로딩 (처음 한 번만)
            if not model_loaded:
                print("Loading voice model...")
                if not load_voice_model():
                    raise Exception("Failed to load voice model")

            # DynamoDB 상태 업데이트: processing
            update_status(analysis_id, 'processing', progress=10)

            try:
                # S3에서 오디오 파일 다운로드
                with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                    s3_client.download_fileobj(s3_bucket, s3_key, temp_file)
                    temp_audio_path = temp_file.name

                update_status(analysis_id, 'processing', progress=30)

                # 실제 음성 분석 수행
                analysis_result = analyze_voice_real(temp_audio_path, parameters)

                update_status(analysis_id, 'processing', progress=80)

                # 결과를 DynamoDB에 저장
                save_results(analysis_id, user_id, analysis_result)

                update_status(analysis_id, 'completed', progress=100)

                print(f"Voice analysis completed: {analysis_id}")

                # 임시 파일 삭제
                os.unlink(temp_audio_path)

            except Exception as e:
                error_msg = f"Voice analysis failed: {str(e)}"
                print(f"Error in {analysis_id}: {error_msg}")
                print(traceback.format_exc())

                # 실패 상태로 업데이트
                update_status(analysis_id, 'failed', error_message=error_msg)

                # 임시 파일 정리
                try:
                    os.unlink(temp_audio_path)
                except:
                    pass

        return {'statusCode': 200, 'body': 'Processing completed'}

    except Exception as e:
        print(f"Lambda handler error: {str(e)}")
        print(traceback.format_exc())
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def analyze_voice_real(audio_path: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
    """실제 MultiBranch 모델을 사용한 음성 분석"""

    if not model_loaded or voice_model is None:
        raise Exception("Voice model not loaded")

    try:
        # 1. 오디오 특성 추출
        features = extract_multibranch_features(audio_path)

        # 2. 모델 예측
        with torch.no_grad():
            mel_input = torch.FloatTensor(features['mel_spectrogram']).unsqueeze(0)
            mfcc_input = torch.FloatTensor(features['mfcc_sequence']).unsqueeze(0)
            tab_input = torch.FloatTensor(features['tabular']).unsqueeze(0)

            # 모델 예측
            logits = voice_model(mel_input, mfcc_input, tab_input)
            probabilities = F.softmax(logits, dim=1)
            predicted_class = torch.argmax(probabilities, dim=1).item()

        # 3. 결과 해석
        classes = [k for k, v in sorted(label2idx.items(), key=lambda x: x[1])]
        predicted_label = classes[predicted_class]
        confidence_scores = {
            classes[i]: float(probabilities[0][i])
            for i in range(len(classes))
        }

        # 4. 파킨슨병 확률 계산
        parkinson_probability = calculate_parkinson_probability(
            predicted_label, confidence_scores
        )

        # 5. 결과 구성
        result = {
            'model_prediction': {
                'predicted_class': predicted_label,
                'confidence': float(probabilities[0][predicted_class]),
                'class_probabilities': confidence_scores
            },
            'parkinson_assessment': {
                'parkinson_probability': parkinson_probability,
                'assessment': get_assessment_text(parkinson_probability),
                'confidence_level': get_confidence_level(float(probabilities[0][predicted_class]))
            },
            'voice_features': {
                'mel_spectrogram_shape': features['mel_spectrogram'].shape,
                'mfcc_sequence_shape': features['mfcc_sequence'].shape,
                'tabular_features': len(features['tabular'])
            },
            'analysis_info': {
                'model_type': 'MultiBranch CNN+BiGRU+MLP',
                'classes_available': classes,
                'audio_duration': features.get('duration', 0)
            }
        }

        return result

    except Exception as e:
        print(f"Voice analysis error: {str(e)}")
        return {
            'error': str(e),
            'analysis_status': 'failed'
        }

def extract_multibranch_features(audio_path: str) -> Dict[str, Any]:
    """실제 모델에 맞는 특성 추출"""

    try:
        # librosa로 오디오 로드
        y, sr = librosa.load(audio_path, sr=16000)  # 모델 설정에 맞춰 16kHz

        # 1. Mel-spectrogram (CNN용)
        mel_spec = librosa.feature.melspectrogram(
            y=y, sr=sr,
            n_mels=128,  # cfg에서 설정된 값
            n_fft=1024,
            hop_length=256,
            win_length=1024,
            fmin=20,
            fmax=7600
        )
        mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)

        # 256 프레임으로 크기 조정
        target_frames = 256
        if mel_spec_db.shape[1] > target_frames:
            mel_spec_db = mel_spec_db[:, :target_frames]
        else:
            # 패딩
            pad_width = target_frames - mel_spec_db.shape[1]
            mel_spec_db = np.pad(mel_spec_db, ((0, 0), (0, pad_width)), mode='constant')

        # (1, 128, 256) 형태로 변환
        mel_spec_final = mel_spec_db.reshape(1, 128, 256)

        # 2. MFCC + 델타 특성 (BiGRU용)
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=40)
        mfcc_delta = librosa.feature.delta(mfcc)
        mfcc_delta2 = librosa.feature.delta(mfcc, order=2)

        # 연결: (40 + 40 + 40, time) -> (time, 120)
        mfcc_combined = np.vstack([mfcc, mfcc_delta, mfcc_delta2]).T

        # 300 프레임으로 크기 조정
        target_rnn_frames = 300
        if mfcc_combined.shape[0] > target_rnn_frames:
            mfcc_combined = mfcc_combined[:target_rnn_frames, :]
        else:
            # 패딩
            pad_width = target_rnn_frames - mfcc_combined.shape[0]
            mfcc_combined = np.pad(mfcc_combined, ((0, pad_width), (0, 0)), mode='constant')

        # 3. 통계적 특성 (MLP용)
        tabular_features = extract_tabular_features(y, sr, mfcc, mel_spec_db)

        return {
            'mel_spectrogram': mel_spec_final,
            'mfcc_sequence': mfcc_combined,
            'tabular': tabular_features,
            'duration': len(y) / sr
        }

    except Exception as e:
        print(f"Feature extraction error: {str(e)}")
        raise

def extract_tabular_features(y: np.ndarray, sr: int, mfcc: np.ndarray, mel_spec: np.ndarray) -> np.ndarray:
    """통계적 특성 추출 (실제 모델의 tab_dim에 맞춤)"""

    features = []

    # 1. MFCC 통계
    features.extend(np.mean(mfcc, axis=1))  # 40개
    features.extend(np.std(mfcc, axis=1))   # 40개
    features.extend(np.median(mfcc, axis=1)) # 40개

    # 2. 스펙트럴 특성
    spectral_centroids = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
    features.append(np.mean(spectral_centroids))
    features.append(np.std(spectral_centroids))

    spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)[0]
    features.append(np.mean(spectral_rolloff))
    features.append(np.std(spectral_rolloff))

    spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)[0]
    features.append(np.mean(spectral_bandwidth))
    features.append(np.std(spectral_bandwidth))

    # 3. 기타 특성
    zero_crossing_rate = librosa.feature.zero_crossing_rate(y)[0]
    features.append(np.mean(zero_crossing_rate))
    features.append(np.std(zero_crossing_rate))

    rms_energy = librosa.feature.rms(y=y)[0]
    features.append(np.mean(rms_energy))
    features.append(np.std(rms_energy))

    # 4. 고차 통계량
    features.append(skew(y))
    features.append(kurtosis(y))

    # 5. Mel-spectrogram 통계
    features.append(np.mean(mel_spec))
    features.append(np.std(mel_spec))

    return np.array(features, dtype=np.float32)

def calculate_parkinson_probability(predicted_label: str, confidence_scores: Dict[str, float]) -> float:
    """클래스 예측 결과를 파킨슨병 확률로 변환"""

    # HC (Healthy Control) vs 병리적 상태 매핑
    if predicted_label == 'HC':
        # 건강한 상태로 예측된 경우
        return 1.0 - confidence_scores['HC']  # HC 확신도가 낮을수록 파킨슨병 의심
    elif predicted_label == 'PD':
        # 파킨슨병으로 직접 예측된 경우
        return confidence_scores['PD']
    elif predicted_label in ['MSA', 'PSP']:
        # 관련 질환으로 예측된 경우 (파킨슨병과 유사)
        return confidence_scores[predicted_label] * 0.8  # 가중치 적용
    else:
        # 기타 경우
        return 0.5

def get_assessment_text(probability: float) -> str:
    """확률에 따른 평가 텍스트"""
    if probability > 0.8:
        return "파킨슨병 징후 매우 강하게 의심"
    elif probability > 0.65:
        return "파킨슨병 징후 강하게 의심"
    elif probability > 0.4:
        return "파킨슨병 징후 중등도 의심"
    elif probability > 0.25:
        return "파킨슨병 징후 경미하게 의심"
    else:
        return "정상 범위"

def get_confidence_level(model_confidence: float) -> str:
    """모델 신뢰도 레벨"""
    if model_confidence > 0.9:
        return "very_high"
    elif model_confidence > 0.8:
        return "high"
    elif model_confidence > 0.6:
        return "medium"
    else:
        return "low"

def update_status(analysis_id: str, status: str, progress: int = 0, error_message: str = None):
    """DynamoDB 상태 업데이트"""
    try:
        update_expression = 'SET #status = :status, progress = :progress'
        expression_values = {
            ':status': status,
            ':progress': progress
        }
        expression_names = {'#status': 'status'}

        if error_message:
            update_expression += ', error_message = :error'
            expression_values[':error'] = error_message

        if status == 'completed':
            update_expression += ', completed_at = :completed_at'
            expression_values[':completed_at'] = int(time.time())

        table.update_item(
            Key={'analysis_id': analysis_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=expression_names,
            ExpressionAttributeValues=expression_values
        )
    except Exception as e:
        print(f"Status update failed for {analysis_id}: {str(e)}")

def save_results(analysis_id: str, user_id: str, analysis_result: Dict[str, Any]):
    """분석 결과를 DynamoDB에 저장"""
    try:
        table.update_item(
            Key={'analysis_id': analysis_id},
            UpdateExpression='SET results = :results, processing_time = :time',
            ExpressionAttributeValues={
                ':results': analysis_result,
                ':time': int(time.time())
            }
        )
    except Exception as e:
        print(f"Failed to save results for {analysis_id}: {str(e)}")
        raise