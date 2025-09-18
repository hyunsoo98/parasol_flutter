# 🚀 통합 AWS Lambda 배포 가이드 (Eye Tracking + Finger Tapping + Voice Analysis)

## 📋 통합 아키텍처

### 🔄 **통합 API 구조**
```
/api/v1/
├── /upload                    (POST) → lambda_unified_upload
├── /status/{analysis_id}      (GET)  → lambda_unified_status
├── /status?user_id=xxx        (GET)  → lambda_unified_status
└── /results/{analysis_id}     (GET)  → lambda_unified_status
```

### 🛠️ **Lambda 함수 구성**
```
통합 함수:
- lambda_unified_upload.py    → 모든 분석 타입 업로드
- lambda_unified_status.py    → 모든 분석 타입 상태/결과 조회

분석별 처리 함수:
- lambda_process.py           → Eye tracking 분석
- lambda_finger_process.py    → Finger tapping 분석
- lambda_voice_process.py     → Voice analysis 분석
```

## 🎯 **1단계: SQS 큐 생성**

### Eye Tracking 큐 (기존)
```bash
aws sqs create-queue \
    --queue-name eye-tracking-queue \
    --region us-west-1
```

### Finger Tapping 큐 (신규)
```bash
aws sqs create-queue \
    --queue-name finger-tapping-queue \
    --region us-west-1
```

### Voice Analysis 큐 (신규)
```bash
aws sqs create-queue \
    --queue-name voice-analysis-queue \
    --region us-west-1
```

### DynamoDB 테이블 생성
```bash
# Voice Analysis 테이블
aws dynamodb create-table --cli-input-json file://voice_analysis_table.json --region us-west-1
```

## 🎯 **2단계: Lambda 함수 패키징**

### 통합 Upload 함수
```bash
zip lambda_unified_upload.zip lambda_unified_upload.py
```

### 통합 Status 함수 (기존 파일 사용)
```bash
zip lambda_unified_status.zip lambda_unified_status.py
```

### Finger Tapping Process 함수
```bash
zip lambda_finger_process.zip lambda_finger_process.py best_pipeline_recall_AdaBoost.joblib feature_extraction.py
```

### Voice Analysis Process 함수 (Multi-branch models 포함)
```bash
# 모델 파일과 함께 패키징
zip lambda_voice_process.zip lambda_voice_process.py voice_cnn_model.h5 voice_bigru_model.h5 voice_mlp_model.h5

# requirements.txt도 포함 (Layer 없이 배포시)
# pip install -r voice_requirements.txt -t ./package/
# zip -r lambda_voice_process.zip lambda_voice_process.py voice_*.h5 package/
```

## 🎯 **3단계: Lambda 함수 배포**

### 1) 통합 Upload Lambda
```bash
aws lambda create-function \
    --function-name unified-upload \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_unified_upload.lambda_handler \
    --zip-file fileb://lambda_unified_upload.zip \
    --timeout 120 \
    --memory-size 512 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "EYE_SQS_QUEUE_URL":"https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue",
        "FINGER_SQS_QUEUE_URL":"https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue",
        "VOICE_SQS_QUEUE_URL":"https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue"
    }' \
    --region us-west-1
```

### 2) 통합 Status Lambda (기존 업데이트)
```bash
# 기존 함수가 있다면 업데이트
aws lambda update-function-code \
    --function-name unified-status \
    --zip-file fileb://lambda_unified_status.zip \
    --region us-west-1

# 또는 새로 생성
aws lambda create-function \
    --function-name unified-status \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_unified_status.lambda_handler \
    --zip-file fileb://lambda_unified_status.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "EYE_TRACKING_TABLE":"eye-tracking-results",
        "FINGER_TAPPING_TABLE":"finger-tapping-results",
        "VOICE_ANALYSIS_TABLE":"voice-analysis-results"
    }' \
    --region us-west-1
```

### 3) Finger Tapping Process Lambda
```bash
aws lambda create-function \
    --function-name finger-tapping-process \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_finger_process.lambda_handler \
    --zip-file fileb://lambda_finger_process.zip \
    --timeout 900 \
    --memory-size 3008 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "S3_PREFIX":"finger-tapping/",
        "DYNAMODB_TABLE":"finger-tapping-results",
        "MODEL_FILE":"best_pipeline_recall_AdaBoost.joblib"
    }' \
    --region us-west-1
```

### 4) Voice Analysis Process Lambda
```bash
aws lambda create-function \
    --function-name voice-analysis-process \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_voice_process.lambda_handler \
    --zip-file fileb://lambda_voice_process.zip \
    --timeout 600 \
    --memory-size 1024 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "S3_PREFIX":"audio/voice-analysis/",
        "DYNAMODB_TABLE":"voice-analysis-results",
        "CNN_MODEL_PATH":"voice_cnn_model.h5",
        "BIGRU_MODEL_PATH":"voice_bigru_model.h5",
        "MLP_MODEL_PATH":"voice_mlp_model.h5"
    }' \
    --region us-west-1
```

## 🎯 **4단계: SQS 트리거 연결**

### Finger Tapping Process Lambda에 SQS 트리거 추가
```bash
aws lambda create-event-source-mapping \
    --function-name finger-tapping-process \
    --event-source-arn arn:aws:sqs:us-west-1:327784329358:finger-tapping-queue \
    --batch-size 1 \
    --region us-west-1
```

### Voice Analysis Process Lambda에 SQS 트리거 추가
```bash
aws lambda create-event-source-mapping \
    --function-name voice-analysis-process \
    --event-source-arn arn:aws:sqs:us-west-1:327784329358:voice-analysis-queue \
    --batch-size 1 \
    --region us-west-1
```

## 🎯 **5단계: API Gateway 업데이트**

### 기존 API Gateway에서 업데이트

#### 1) `/upload` 엔드포인트 수정
- **Integration**: `unified-upload` Lambda로 변경
- **CORS** 설정 유지

#### 2) `/status` 엔드포인트 수정
- **Integration**: `unified-status` Lambda로 변경
- **CORS** 설정 유지

#### 3) `/results` 엔드포인트 (신규 또는 기존)
- **Integration**: `unified-status` Lambda
- **CORS** 설정 추가

## 🧪 **6단계: 테스트**

### Upload 테스트 (Eye Tracking)
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{
    "analysis_type": "eye-tracking",
    "video_data": "base64_encoded_video_data",
    "user_id": "test_user",
    "parameters": {
      "step": 1,
      "vpp_thresh": 0.06,
      "blink_thresh": 0.18,
      "max_frames": 1000
    }
  }'
```

### Upload 테스트 (Finger Tapping)
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{
    "analysis_type": "finger-tapping",
    "video_data": "base64_encoded_video_data",
    "user_id": "test_user",
    "parameters": {
      "target_taps": 10,
      "max_duration": 30,
      "hand_preference": "both"
    }
  }'
```

### Upload 테스트 (Voice Analysis)
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{
    "analysis_type": "voice-analysis",
    "video_data": "base64_encoded_audio_data",
    "user_id": "test_user",
    "parameters": {
      "language": "ko",
      "task_type": "syllable_repetition",
      "duration": 30
    }
  }'
```

### Status 테스트
```bash
# 특정 분석 조회
curl "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status/ANALYSIS_ID"

# 사용자별 목록 조회
curl "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status?user_id=test_user"

# 타입별 필터링
curl "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status?user_id=test_user&analysis_type=finger-tapping"
curl "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status?user_id=test_user&analysis_type=voice-analysis"
```

## 🔧 **Flutter 앱 업데이트**

### aws_config.dart 업데이트
```dart
// 통합 엔드포인트 사용
static String getUploadUrl() => getFullUrl('/api/v1/upload');
static String getStatusUrl() => getFullUrl('/api/v1/status');
static String getResultsUrl() => getFullUrl('/api/v1/results');
```

### 사용 예시
```dart
// Eye Tracking 분석
final eyeResponse = await http.post(
  Uri.parse(AWSConfig.getUploadUrl()),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'analysis_type': 'eye-tracking',
    'video_data': base64VideoData,
    'user_id': userId,
    'parameters': {
      'step': 1,
      'vpp_thresh': 0.06,
      'blink_thresh': 0.18,
      'max_frames': 1000
    }
  }),
);

// Finger Tapping 분석
final fingerResponse = await http.post(
  Uri.parse(AWSConfig.getUploadUrl()),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'analysis_type': 'finger-tapping',
    'video_data': base64VideoData,
    'user_id': userId,
    'parameters': {
      'target_taps': 10,
      'max_duration': 30,
      'hand_preference': 'both'
    }
  }),
);

// Voice Analysis 분석
final voiceResponse = await http.post(
  Uri.parse(AWSConfig.getUploadUrl()),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'analysis_type': 'voice-analysis',
    'video_data': base64AudioData,  // 실제로는 오디오 데이터
    'user_id': userId,
    'parameters': {
      'language': 'ko',
      'task_type': 'syllable_repetition',
      'duration': 30
    }
  }),
);
```

## ✅ **배포 완료 체크리스트**

### AWS 리소스
- [ ] `finger-tapping-queue` SQS 큐 생성
- [ ] `voice-analysis-queue` SQS 큐 생성
- [ ] `finger-tapping-results` DynamoDB 테이블 생성 ✅
- [ ] `voice-analysis-results` DynamoDB 테이블 생성

### Lambda 함수
- [ ] `unified-upload` Lambda 배포
- [ ] `unified-status` Lambda 업데이트
- [ ] `finger-tapping-process` Lambda 배포
- [ ] `voice-analysis-process` Lambda 배포
- [ ] SQS 트리거 연결 (finger-tapping, voice-analysis)

### API Gateway
- [ ] `/upload` 엔드포인트 → `unified-upload` 연결
- [ ] `/status` 엔드포인트 → `unified-status` 연결
- [ ] `/results` 엔드포인트 → `unified-status` 연결
- [ ] CORS 설정 확인

### 테스트
- [ ] Eye tracking 업로드 테스트
- [ ] Finger tapping 업로드 테스트
- [ ] Voice analysis 업로드 테스트
- [ ] 상태 조회 테스트
- [ ] 결과 조회 테스트

## 🎉 **배포 완료!**

이제 하나의 `/upload` 엔드포인트로 **Eye Tracking, Finger Tapping, Voice Analysis** 세 가지 분석을 모두 처리할 수 있습니다!

### 🎵 **통합 시스템의 장점**
- **단일 API**: `/upload` 하나로 3가지 분석 타입 지원
- **확장성**: 새로운 분석 타입 추가 시 패턴 재사용
- **일관성**: 동일한 요청/응답 구조
- **유지보수성**: 중앙집중식 관리