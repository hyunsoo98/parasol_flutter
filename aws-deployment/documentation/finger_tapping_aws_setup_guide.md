# 🤏 Finger Tapping AWS Lambda 완전 설정 가이드

## 📋 현재 상황 분석
- ✅ Lambda 함수 코드 작성 완료 (`lambda_finger_*.py`)
- ❌ SQS 큐 및 트리거 설정 필요
- ❌ DynamoDB 테이블 생성 필요
- ❌ IAM 권한 설정 필요
- ❌ API Gateway 연결 필요

## 🛠️ 필수 AWS 리소스 설정

### 1. DynamoDB 테이블 생성

#### 테이블 생성 명령어
```bash
aws dynamodb create-table \
    --table-name finger-tapping-results \
    --attribute-definitions \
        AttributeName=analysis_id,AttributeType=S \
    --key-schema \
        AttributeName=analysis_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-west-1
```

#### 테이블 스키마
```
테이블명: finger-tapping-results
Primary Key: analysis_id (String)
Attributes:
- user_id (String): 사용자 ID
- status (String): processing | completed | failed
- timestamp (Number): 분석 시작 시간
- s3_key (String): S3 비디오 파일 경로
- parameters (Map): 분석 파라미터
- results (Map): 분석 결과
  - tap_count: 탭 횟수
  - rhythm_consistency: 리듬 일관성
  - hand_coordination: 손 협응성
  - parkinson_probability: 파킨슨병 확률
- processing_time (Number): 처리 시간 (초)
- error_message (String): 오류 메시지 (실패시)
```

### 2. SQS 큐 생성 및 설정

#### 큐 생성
```bash
aws sqs create-queue \
    --queue-name finger-tapping-queue \
    --region us-west-1
```

#### 큐 속성 설정
```bash
aws sqs set-queue-attributes \
    --queue-url https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT_ID/finger-tapping-queue \
    --attributes '{
        "VisibilityTimeoutSeconds": "960",
        "MessageRetentionPeriod": "1209600",
        "MaxReceiveCount": "3",
        "DelaySeconds": "0"
    }'
```

### 3. S3 버킷 설정 (기존 seoul-ht-09 사용)

#### CORS 설정 확인
```json
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 3000
        }
    ]
}
```

## 🔐 IAM 역할 및 권한 설정

### 1. Lambda 실행 역할 생성

#### Trust Policy (AssumeRolePolicyDocument)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

#### 권한 정책
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:us-west-1:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::seoul-ht-09/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:us-west-1:*:table/finger-tapping-results"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-west-1:*:finger-tapping-queue"
    }
  ]
}
```

## 🚀 Lambda 함수 배포

### 1. 의존성 Layer 생성 (기존 eye-tracking layer 활용 가능)

```bash
# MediaPipe, OpenCV, NumPy, Pandas, Scikit-learn 포함
aws lambda publish-layer-version \
    --layer-name finger-tapping-dependencies \
    --description "MediaPipe, OpenCV, ML libraries for Finger Tapping" \
    --zip-file fileb://finger_tapping_layer.zip \
    --compatible-runtimes python3.9 \
    --region us-west-1
```

### 2. Upload Lambda 함수 배포

```bash
# 함수 생성
zip lambda_finger_upload.zip lambda_finger_upload.py

aws lambda create-function \
    --function-name finger-tapping-upload \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/finger-tapping-lambda-role \
    --handler lambda_finger_upload.lambda_handler \
    --zip-file fileb://lambda_finger_upload.zip \
    --timeout 120 \
    --memory-size 512 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "S3_PREFIX":"finger-tapping/",
        "SQS_QUEUE_URL":"https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT_ID/finger-tapping-queue",
        "DYNAMODB_TABLE":"finger-tapping-results"
    }' \
    --region us-west-1
```

### 3. Process Lambda 함수 배포

```bash
# 모델 파일과 함께 패키징
zip lambda_finger_process.zip lambda_finger_process.py best_pipeline_recall_AdaBoost.joblib feature_extraction.py

aws lambda create-function \
    --function-name finger-tapping-process \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/finger-tapping-lambda-role \
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
    --layers arn:aws:lambda:us-west-1:YOUR_ACCOUNT_ID:layer:finger-tapping-dependencies:1 \
    --region us-west-1
```

### 4. Status Lambda 함수 배포

```bash
zip lambda_finger_status.zip lambda_finger_status.py

aws lambda create-function \
    --function-name finger-tapping-status \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/finger-tapping-lambda-role \
    --handler lambda_finger_status.lambda_handler \
    --zip-file fileb://lambda_finger_status.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"finger-tapping-results"
    }' \
    --region us-west-1
```

## 🔗 SQS 트리거 연결

### Process Lambda에 SQS 트리거 추가
```bash
aws lambda create-event-source-mapping \
    --function-name finger-tapping-process \
    --event-source-arn arn:aws:sqs:us-west-1:YOUR_ACCOUNT_ID:finger-tapping-queue \
    --batch-size 1 \
    --maximum-batching-window-in-seconds 0 \
    --region us-west-1
```

### 트리거 상태 확인
```bash
aws lambda list-event-source-mappings \
    --function-name finger-tapping-process \
    --region us-west-1
```

## 🌐 API Gateway 설정

### 기존 API에 Finger Tapping 리소스 추가

#### 1. 리소스 구조
```
/api/v1/analyze/finger-tapping  (POST) → finger-tapping-upload
/api/v1/upload                  (POST) → finger-tapping-upload
/api/v1/status/{analysis_id}    (GET)  → finger-tapping-status
/api/v1/status                  (GET)  → finger-tapping-status
```

#### 2. Integration 설정
각 리소스에서:
- **Integration Type**: Lambda Function
- **Lambda Region**: us-west-1
- **Lambda Function**: 해당 함수명
- **Use Lambda Proxy integration**: ✅ 체크

#### 3. CORS 설정
모든 메서드에서 Enable CORS:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token
Access-Control-Allow-Methods: GET,POST,OPTIONS
```

### API 배포
```bash
aws apigateway create-deployment \
    --rest-api-id YOUR_API_ID \
    --stage-name prod \
    --description "Finger Tapping analysis endpoints added" \
    --region us-west-1
```

## 📊 환경 변수 완전 설정

### Upload Lambda 환경 변수
```
S3_BUCKET=seoul-ht-09
S3_PREFIX=finger-tapping/
SQS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT_ID/finger-tapping-queue
DYNAMODB_TABLE=finger-tapping-results
```

### Process Lambda 환경 변수
```
S3_BUCKET=seoul-ht-09
S3_PREFIX=finger-tapping/
DYNAMODB_TABLE=finger-tapping-results
MODEL_FILE=best_pipeline_recall_AdaBoost.joblib
```

### Status Lambda 환경 변수
```
S3_BUCKET=seoul-ht-09
DYNAMODB_TABLE=finger-tapping-results
```

## 🧪 테스트 가이드

### 1. Upload 함수 테스트
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/analyze/finger-tapping \
  -H "Content-Type: application/json" \
  -d '{
    "video_data": "base64_encoded_video_data",
    "user_id": "test_user",
    "parameters": {
      "target_taps": 10,
      "max_duration": 30,
      "hand_preference": "both"
    }
  }'
```

### 2. Status 함수 테스트
```bash
# 특정 분석 ID 조회
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status/ANALYSIS_ID

# 사용자별 목록 조회
curl "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status?user_id=test_user"
```

### 3. SQS 메시지 확인
```bash
aws sqs receive-message \
    --queue-url https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT_ID/finger-tapping-queue \
    --region us-west-1
```

### 4. DynamoDB 데이터 확인
```bash
aws dynamodb scan \
    --table-name finger-tapping-results \
    --region us-west-1
```

## ⚠️ 문제 해결 가이드

### 자주 발생하는 문제들

#### 1. SQS 트리거가 작동하지 않는 경우
```bash
# 트리거 상태 확인
aws lambda list-event-source-mappings --function-name finger-tapping-process

# 트리거 삭제 후 재생성
aws lambda delete-event-source-mapping --uuid MAPPING_UUID
aws lambda create-event-source-mapping --function-name finger-tapping-process --event-source-arn SQS_ARN
```

#### 2. DynamoDB 권한 오류
- IAM 역할에 DynamoDB 권한 추가 확인
- 테이블 이름 및 리전 확인

#### 3. S3 업로드 실패
- S3 버킷 정책 및 CORS 설정 확인
- Lambda 실행 역할에 S3 권한 추가

#### 4. 모델 로딩 실패
- `best_pipeline_recall_AdaBoost.joblib` 파일이 Lambda 패키지에 포함되어 있는지 확인
- `feature_extraction.py` 파일 포함 확인

## ✅ 완료 체크리스트

### AWS 리소스 설정
- [ ] DynamoDB 테이블 생성 (`finger-tapping-results`)
- [ ] SQS 큐 생성 (`finger-tapping-queue`)
- [ ] S3 버킷 CORS 설정 확인
- [ ] IAM 역할 및 권한 정책 생성

### Lambda 함수 배포
- [ ] Layer 생성 (의존성 패키지)
- [ ] Upload Lambda 함수 배포
- [ ] Process Lambda 함수 배포 (모델 파일 포함)
- [ ] Status Lambda 함수 배포
- [ ] 환경 변수 설정 완료

### 트리거 및 연결
- [ ] SQS → Process Lambda 트리거 연결
- [ ] API Gateway 리소스 및 메서드 생성
- [ ] CORS 설정 활성화
- [ ] API 배포 완료

### 테스트 및 검증
- [ ] Upload API 테스트
- [ ] SQS 메시지 전송 확인
- [ ] Process Lambda 실행 확인
- [ ] DynamoDB 결과 저장 확인
- [ ] Status API 테스트
- [ ] 전체 플로우 통합 테스트

## 🎯 다음 단계: Voice Analysis 준비

Finger Tapping 설정 완료 후, 같은 패턴으로 Voice Analysis 구성:
1. `voice-analysis-results` DynamoDB 테이블
2. `voice-analysis-queue` SQS 큐
3. 3개 Lambda 함수 (`voice_upload`, `voice_process`, `voice_status`)
4. API Gateway `/api/v1/analyze/voice` 엔드포인트

🎉 **설정 완료 후 Finger Tapping 분석 시스템이 완전히 작동합니다!**