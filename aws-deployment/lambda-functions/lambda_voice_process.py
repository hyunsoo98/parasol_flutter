"""
AWS Lambda: Voice Analysis 오디오 분석 처리
- SQS에서 메시지 수신
- S3에서 오디오 다운로드
- 음성 분석 수행 (음성 특성, 파킨슨병 징후 분석)
- 결과를 DynamoDB에 저장
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
S3_PREFIX = os.environ.get('S3_PREFIX', 'voice-analysis/')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'voice-analysis-results')

# DynamoDB 테이블 참조
table = dynamodb.Table(DYNAMODB_TABLE)

# Multi-branch 모델 로딩
try:
    import tensorflow as tf
    import librosa

    # TensorFlow 로깅 레벨 설정
    tf.get_logger().setLevel('ERROR')

    # 모델 파일 경로
    CNN_MODEL_PATH = os.environ.get('CNN_MODEL_PATH', 'voice_cnn_model.h5')
    BIGRU_MODEL_PATH = os.environ.get('BIGRU_MODEL_PATH', 'voice_bigru_model.h5')
    MLP_MODEL_PATH = os.environ.get('MLP_MODEL_PATH', 'voice_mlp_model.h5')

    # 모델 로딩 플래그
    models_loaded = False
    cnn_model = None
    bigru_model = None
    mlp_model = None

except ImportError as e:
    print(f"Model libraries not available: {e}")
    models_loaded = False

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    SQS 트리거로 실행되는 메인 핸들러

    SQS 메시지 형식:
    {
        "analysis_id": "uuid",
        "user_id": "user123",
        "s3_bucket": "seoul-ht-09",
        "s3_key": "voice-analysis/user123/uuid_timestamp.wav",
        "analysis_type": "voice-analysis",
        "parameters": {...},
        "timestamp": 1234567890
    }
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
            if not models_loaded:
                print("Loading multi-branch models...")
                load_models()

            # DynamoDB 상태 업데이트: processing
            update_status(analysis_id, 'processing', progress=10)

            try:
                # S3에서 오디오 파일 다운로드
                with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                    s3_client.download_fileobj(s3_bucket, s3_key, temp_file)
                    temp_audio_path = temp_file.name

                update_status(analysis_id, 'processing', progress=30)

                # 음성 분석 수행
                analysis_result = analyze_voice(temp_audio_path, parameters)

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

                # 임시 파일 삭제 (에러가 나도 정리)
                try:
                    os.unlink(temp_audio_path)
                except:
                    pass

        return {'statusCode': 200, 'body': 'Processing completed'}

    except Exception as e:
        print(f"Lambda handler error: {str(e)}")
        print(traceback.format_exc())
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def analyze_voice(audio_path: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
    """
    Multi-branch 모델을 사용한 음성 분석 수행

    Models:
    1. CNN: 스펙트로그램 기반 특성 추출
    2. BiGRU: 시계열 음성 특성 분석
    3. MLP: 통계적 특성 분류
    """

    # 기본 분석 결과 구조
    result = {
        'basic_features': {},
        'model_predictions': {},
        'ensemble_result': {},
        'voice_quality': {},
        'overall_assessment': {}
    }

    try:
        # 1. 오디오 특성 추출
        features = extract_voice_features(audio_path)
        result['basic_features'] = features

        # 2. Multi-branch 모델 예측
        if models_loaded:
            model_predictions = run_multi_branch_models(features)
            result['model_predictions'] = model_predictions

            # 3. 앙상블 결과
            ensemble_result = ensemble_predictions(model_predictions)
            result['ensemble_result'] = ensemble_result
        else:
            # 모델이 로드되지 않은 경우 기본 분석
            print("Models not loaded, using traditional analysis")
            ensemble_result = traditional_voice_analysis(features)
            result['ensemble_result'] = ensemble_result

        # 4. 음성 품질 지표
        result['voice_quality'] = analyze_voice_quality(features)

        # 5. 종합 평가
        result['overall_assessment'] = create_overall_assessment(
            result['ensemble_result'],
            result['voice_quality']
        )

        return result

    except Exception as e:
        print(f"Voice analysis error: {str(e)}")
        return {
            'error': str(e),
            'analysis_status': 'failed'
        }

def load_models():
    """Multi-branch 모델들을 로드"""
    global models_loaded, cnn_model, bigru_model, mlp_model

    try:
        # CNN 모델 로드 (스펙트로그램용)
        if os.path.exists(CNN_MODEL_PATH):
            cnn_model = tf.keras.models.load_model(CNN_MODEL_PATH)
            print("CNN model loaded successfully")

        # BiGRU 모델 로드 (시계열용)
        if os.path.exists(BIGRU_MODEL_PATH):
            bigru_model = tf.keras.models.load_model(BIGRU_MODEL_PATH)
            print("BiGRU model loaded successfully")

        # MLP 모델 로드 (통계적 특성용)
        if os.path.exists(MLP_MODEL_PATH):
            mlp_model = tf.keras.models.load_model(MLP_MODEL_PATH)
            print("MLP model loaded successfully")

        models_loaded = True
        return True

    except Exception as e:
        print(f"Model loading failed: {str(e)}")
        models_loaded = False
        return False

def extract_voice_features(audio_path: str) -> Dict[str, Any]:
    """오디오에서 다양한 특성 추출"""

    features = {}

    try:
        # librosa로 오디오 로드
        y, sr = librosa.load(audio_path, sr=22050)

        # 1. 스펙트로그램 특성 (CNN용)
        mel_spec = librosa.feature.melspectrogram(y=y, sr=sr, n_mels=128)
        mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)
        features['mel_spectrogram'] = mel_spec_db

        # 2. 시계열 특성 (BiGRU용)
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
        features['mfcc_sequence'] = mfcc.T  # (time, features)

        # 3. 통계적 특성 (MLP용)
        features['statistical'] = {
            'mfcc_mean': np.mean(mfcc, axis=1),
            'mfcc_std': np.std(mfcc, axis=1),
            'spectral_centroid': np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)),
            'spectral_rolloff': np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr)),
            'zero_crossing_rate': np.mean(librosa.feature.zero_crossing_rate(y)),
            'rms_energy': np.mean(librosa.feature.rms(y=y))
        }

        # 4. 기본 음성 특성
        features['basic'] = {
            'duration': len(y) / sr,
            'pitch_mean': np.mean(librosa.yin(y, fmin=50, fmax=300)),
            'pitch_std': np.std(librosa.yin(y, fmin=50, fmax=300))
        }

        return features

    except Exception as e:
        print(f"Feature extraction error: {str(e)}")
        return {'error': str(e)}

def run_multi_branch_models(features: Dict[str, Any]) -> Dict[str, Any]:
    """Multi-branch 모델들로 예측 수행"""

    predictions = {}

    try:
        # 1. CNN 예측 (스펙트로그램)
        if cnn_model and 'mel_spectrogram' in features:
            mel_spec = features['mel_spectrogram']
            # 입력 형태 조정 (batch, height, width, channels)
            mel_input = np.expand_dims(mel_spec, axis=0)
            mel_input = np.expand_dims(mel_input, axis=-1)

            cnn_pred = cnn_model.predict(mel_input, verbose=0)
            predictions['cnn'] = {
                'parkinson_probability': float(cnn_pred[0][0]),
                'confidence': 'high' if abs(cnn_pred[0][0] - 0.5) > 0.3 else 'medium'
            }

        # 2. BiGRU 예측 (MFCC 시계열)
        if bigru_model and 'mfcc_sequence' in features:
            mfcc_seq = features['mfcc_sequence']
            # 입력 형태 조정 (batch, time, features)
            mfcc_input = np.expand_dims(mfcc_seq, axis=0)

            bigru_pred = bigru_model.predict(mfcc_input, verbose=0)
            predictions['bigru'] = {
                'parkinson_probability': float(bigru_pred[0][0]),
                'confidence': 'high' if abs(bigru_pred[0][0] - 0.5) > 0.3 else 'medium'
            }

        # 3. MLP 예측 (통계적 특성)
        if mlp_model and 'statistical' in features:
            stats = features['statistical']
            # 특성 벡터 구성
            feature_vector = np.concatenate([
                stats['mfcc_mean'],
                stats['mfcc_std'],
                [stats['spectral_centroid'], stats['spectral_rolloff'],
                 stats['zero_crossing_rate'], stats['rms_energy']]
            ])

            # 입력 형태 조정 (batch, features)
            mlp_input = np.expand_dims(feature_vector, axis=0)

            mlp_pred = mlp_model.predict(mlp_input, verbose=0)
            predictions['mlp'] = {
                'parkinson_probability': float(mlp_pred[0][0]),
                'confidence': 'high' if abs(mlp_pred[0][0] - 0.5) > 0.3 else 'medium'
            }

        return predictions

    except Exception as e:
        print(f"Model prediction error: {str(e)}")
        return {'error': str(e)}

def ensemble_predictions(model_predictions: Dict[str, Any]) -> Dict[str, Any]:
    """Multi-branch 모델 결과를 앙상블"""

    try:
        probabilities = []
        confidences = []

        # 각 모델의 예측값 수집
        for model_name, pred in model_predictions.items():
            if 'parkinson_probability' in pred:
                probabilities.append(pred['parkinson_probability'])
                confidences.append(pred['confidence'])

        if not probabilities:
            return {'error': 'No valid predictions available'}

        # 가중 평균 (신뢰도 기반)
        weights = {'high': 1.0, 'medium': 0.7, 'low': 0.5}
        weight_values = [weights.get(conf, 0.5) for conf in confidences]

        weighted_prob = np.average(probabilities, weights=weight_values)

        # 종합 평가
        if weighted_prob > 0.7:
            assessment = "파킨슨병 징후 강하게 의심"
            confidence = "high"
        elif weighted_prob > 0.4:
            assessment = "파킨슨병 징후 중등도 의심"
            confidence = "medium"
        elif weighted_prob > 0.2:
            assessment = "파킨슨병 징후 경미하게 의심"
            confidence = "low"
        else:
            assessment = "정상 범위"
            confidence = "medium"

        return {
            'ensemble_probability': float(weighted_prob),
            'individual_predictions': model_predictions,
            'assessment': assessment,
            'confidence': confidence,
            'model_agreement': calculate_model_agreement(probabilities)
        }

    except Exception as e:
        print(f"Ensemble prediction error: {str(e)}")
        return {'error': str(e)}

def calculate_model_agreement(probabilities: List[float]) -> float:
    """모델 간 일치도 계산"""
    if len(probabilities) < 2:
        return 1.0

    # 표준편차를 이용한 일치도 (낮을수록 일치도 높음)
    std_dev = np.std(probabilities)
    agreement = max(0, 1 - (std_dev * 2))  # 0-1 스케일
    return float(agreement)

def traditional_voice_analysis(features: Dict[str, Any]) -> Dict[str, Any]:
    """모델이 없을 때 전통적인 음성 분석"""

    try:
        # 기본 특성 기반 규칙 기반 분석
        basic = features.get('basic', {})
        stats = features.get('statistical', {})

        # 간단한 규칙 기반 점수
        score = 0

        if stats.get('zero_crossing_rate', 0) > 0.1:
            score += 1
        if stats.get('spectral_centroid', 0) < 1000:
            score += 1
        if basic.get('pitch_std', 0) < 10:
            score += 1

        probability = min(1.0, score / 3.0)

        return {
            'ensemble_probability': probability,
            'assessment': "기본 분석 결과",
            'confidence': "low",
            'model_agreement': 1.0
        }

    except Exception as e:
        return {'error': str(e)}

def analyze_voice_quality(features: Dict[str, Any]) -> Dict[str, Any]:
    """음성 품질 지표 분석"""

    try:
        stats = features.get('statistical', {})
        basic = features.get('basic', {})

        return {
            'rms_energy': float(stats.get('rms_energy', 0)),
            'spectral_centroid': float(stats.get('spectral_centroid', 0)),
            'spectral_rolloff': float(stats.get('spectral_rolloff', 0)),
            'zero_crossing_rate': float(stats.get('zero_crossing_rate', 0)),
            'duration': float(basic.get('duration', 0)),
            'pitch_variability': float(basic.get('pitch_std', 0))
        }

    except Exception as e:
        return {'error': str(e)}

def create_overall_assessment(ensemble_result: Dict[str, Any], voice_quality: Dict[str, Any]) -> Dict[str, Any]:
    """종합 평가 생성"""

    try:
        probability = ensemble_result.get('ensemble_probability', 0)
        assessment = ensemble_result.get('assessment', 'Unknown')
        confidence = ensemble_result.get('confidence', 'low')

        # 추천사항 생성
        recommendations = []

        if probability > 0.6:
            recommendations.append("신경과 전문의 상담을 권장합니다.")
        if voice_quality.get('rms_energy', 0) < 0.01:
            recommendations.append("발성 연습을 통해 음성 강도를 높여보세요.")
        if voice_quality.get('pitch_variability', 0) < 5:
            recommendations.append("다양한 억양으로 말하는 연습을 해보세요.")

        if not recommendations:
            recommendations.append("현재 음성 상태는 양호합니다. 정기적인 점검을 권장합니다.")

        return {
            'parkinson_probability': probability,
            'assessment': assessment,
            'confidence': confidence,
            'model_agreement': ensemble_result.get('model_agreement', 0),
            'recommendations': recommendations,
            'analysis_timestamp': int(time.time())
        }

    except Exception as e:
        return {'error': str(e)}

def generate_recommendations(analysis_result: Dict[str, Any]) -> List[str]:
    """분석 결과 기반 권장사항 생성"""

    recommendations = []

    voice_quality = analysis_result.get('voice_quality', {})
    parkinson_indicators = analysis_result.get('parkinson_indicators', {})

    if voice_quality.get('jitter_percent', 0) > 1.0:
        recommendations.append("음성 떨림이 관찰됩니다. 음성 치료를 고려해보세요.")

    if voice_quality.get('harmonic_to_noise_ratio', 20) < 15:
        recommendations.append("목소리 기식성이 높습니다. 발성 연습을 권장합니다.")

    if parkinson_indicators.get('dysphonia_score', 0) >= 4:
        recommendations.append("신경과 전문의 상담을 권장합니다.")

    if len(recommendations) == 0:
        recommendations.append("현재 음성 상태는 양호합니다. 정기적인 점검을 권장합니다.")

    return recommendations

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