# 🚀 AWS 순수 비동기 Eye Tracking 완전 배포 가이드

## 📋 전체 아키텍처 완성

```
Flutter App → API Gateway → Upload Lambda → S3 + SQS
                                              ↓
                                        Process Lambda
                                              ↓
                                         DynamoDB
                                              ↑
Flutter App ← API Gateway ← Status Lambda ←─┘
```

## 📁 생성된 파일들

### 🔧 Lambda 함수들 (FastAPI/Firebase 제거)
- `lambda_upload.py` - 비디오 업로드 및 SQS 큐 전송
- `lambda_process.py` - MediaPipe 기반 eye tracking 분석 
- `lambda_status.py` - 상태 조회 및 결과 반환

### 📱 Flutter 클라이언트
- `aws_async_eye_tracking_service.dart` - AWS 순수 비동기 서비스
- `aws_async_eye_tracking_screen.dart` - UI 화면

## 🛠️ AWS 리소스 설정

### 1. DynamoDB 테이블 생성
```bash
aws dynamodb create-table \
    --table-name eye-tracking-results \
    --attribute-definitions \
        AttributeName=analysis_id,AttributeType=S \
    --key-schema \
        AttributeName=analysis_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-west-1
```

### 2. S3 버킷 생성
```bash
aws s3 mb s3://eye-tracking-videos --region us-west-1

# CORS 설정
aws s3api put-bucket-cors \
    --bucket eye-tracking-videos \
    --cors-configuration file://s3-cors.json
```

`s3-cors.json`:
```json
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 3000
        }
    ]
}
```

### 3. SQS 큐 생성
```bash
aws sqs create-queue \
    --queue-name eye-tracking-queue \
    --attributes file://sqs-attributes.json \
    --region us-west-1
```

`sqs-attributes.json`:
```json
{
    "VisibilityTimeoutSeconds": "960",
    "MessageRetentionPeriod": "1209600",
    "MaxReceiveCount": "3"
}
```

### 4. IAM 역할 생성

#### Lambda 실행 역할
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
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::eye-tracking-videos/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:us-west-1:*:table/eye-tracking-results"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-west-1:*:eye-tracking-queue"
    }
  ]
}
```

## 🚀 Lambda 함수 배포

### 1. Layer 생성 (공통 의존성)
```bash
# Windows
create_lambda_layer.bat

# 또는 Linux/Mac
./create_lambda_layer.sh

# Layer 업로드
aws lambda publish-layer-version \
    --layer-name eye-tracking-dependencies \
    --description "OpenCV, MediaPipe, NumPy, Pandas for Eye Tracking" \
    --zip-file fileb://eye_tracking_layer.zip \
    --compatible-runtimes python3.9 \
    --region us-west-1
```

### 2. Lambda 함수들 배포

#### Upload 함수
```bash
zip lambda_upload.zip lambda_upload.py

aws lambda create-function \
    --function-name eye-tracking-upload \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda-execution-role \
    --handler lambda_upload.lambda_handler \
    --zip-file fileb://lambda_upload.zip \
    --timeout 120 \
    --memory-size 512 \
    --environment Variables='{
        "S3_BUCKET":"eye-tracking-videos",
        "SQS_QUEUE_URL":"https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT/eye-tracking-queue",
        "DYNAMODB_TABLE":"eye-tracking-results"
    }' \
    --layers arn:aws:lambda:us-west-1:YOUR_ACCOUNT_ID:layer:eye-tracking-dependencies:1 \
    --region us-west-1
```

#### Process 함수
```bash
zip lambda_process.zip lambda_process.py

aws lambda create-function \
    --function-name eye-tracking-process \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda-execution-role \
    --handler lambda_process.lambda_handler \
    --zip-file fileb://lambda_process.zip \
    --timeout 900 \
    --memory-size 3008 \
    --environment Variables='{
        "S3_BUCKET":"eye-tracking-videos",
        "DYNAMODB_TABLE":"eye-tracking-results"
    }' \
    --layers arn:aws:lambda:us-west-1:YOUR_ACCOUNT_ID:layer:eye-tracking-dependencies:1 \
    --region us-west-1

# SQS 트리거 연결
aws lambda create-event-source-mapping \
    --function-name eye-tracking-process \
    --event-source-arn arn:aws:sqs:us-west-1:YOUR_ACCOUNT_ID:eye-tracking-queue \
    --batch-size 1 \
    --region us-west-1
```

#### Status 함수
```bash
zip lambda_status.zip lambda_status.py

aws lambda create-function \
    --function-name eye-tracking-status \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda-execution-role \
    --handler lambda_status.lambda_handler \
    --zip-file fileb://lambda_status.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables='{
        "S3_BUCKET":"eye-tracking-videos",
        "DYNAMODB_TABLE":"eye-tracking-results"
    }' \
    --region us-west-1
```

## 🌐 API Gateway 설정

### 1. REST API 생성
```bash
aws apigateway create-rest-api \
    --name "EyeTrackingAPI" \
    --description "AWS Async Eye Tracking Analysis API" \
    --region us-west-1
```

### 2. 리소스 및 메서드 설정

**AWS 콘솔에서 진행:**

#### `/upload` 리소스
- Method: POST
- Integration: Lambda Function (eye-tracking-upload)
- Enable CORS

#### `/status/{analysis_id}` 리소스  
- Method: GET
- Integration: Lambda Function (eye-tracking-status)
- Enable CORS

#### `/status` 리소스 (사용자별 목록)
- Method: GET  
- Integration: Lambda Function (eye-tracking-status)
- Enable CORS

### 3. CORS 설정
모든 메서드에서 CORS 활성화:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token
Access-Control-Allow-Methods: GET,POST,OPTIONS
```

### 4. API 배포
```bash
aws apigateway create-deployment \
    --rest-api-id YOUR_API_ID \
    --stage-name prod \
    --region us-west-1
```

## 📱 Flutter 앱 설정

### 1. API URL 업데이트
`lib/services/aws_async_eye_tracking_service.dart`:
```dart
static const String _baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';
```

### 2. 사용 예시
```dart
// 전체 분석 프로세스
final result = await AwsAsyncEyeTrackingService.analyzeVideoComplete(
  videoFile: videoFile,
  userId: 'user123',
  onProgress: (phase, progress, message) {
    print('$phase: $progress% - $message');
  },
);

// 또는 단계별 실행
final startResult = await AwsAsyncEyeTrackingService.startAnalysis(
  videoFile: videoFile,
  userId: 'user123',
);

final finalResult = await AwsAsyncEyeTrackingService.waitForCompletion(
  analysisId: startResult.analysisId,
);
```

## 📊 모니터링 및 로그

### CloudWatch 로그 그룹들
- `/aws/lambda/eye-tracking-upload`
- `/aws/lambda/eye-tracking-process`  
- `/aws/lambda/eye-tracking-status`

### 주요 메트릭
- Lambda 실행 시간 및 메모리 사용량
- SQS 메시지 처리량
- DynamoDB 읽기/쓰기 용량
- S3 저장소 사용량

## 💰 비용 최적화

### 예상 비용 (월간)
- Lambda: $5-20 (사용량에 따라)
- S3: $1-5 (저장 용량에 따라)
- DynamoDB: $2-10 (요청량에 따라)
- API Gateway: $1-5 (호출량에 따라)

### 절약 팁
1. **S3 Lifecycle 정책**: 30일 후 분석 파일 삭제
2. **DynamoDB TTL**: 분석 결과 자동 만료
3. **Lambda 메모리 최적화**: 실제 사용량에 맞게 조정

## 🧪 테스트

### 1. 로컬 테스트 이벤트
```json
{
  "video_data": "base64_encoded_video_data",
  "user_id": "test_user",
  "parameters": {
    "step": 1,
    "vpp_thresh": 0.06,
    "blink_thresh": 0.18,
    "max_frames": 1000
  }
}
```

### 2. 통합 테스트
```bash
# Upload 테스트
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/upload \
  -H "Content-Type: application/json" \
  -d '{"video_data":"...","user_id":"test"}'

# Status 테스트  
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/status/ANALYSIS_ID
```

## ✅ 배포 완료 체크리스트

- [ ] DynamoDB 테이블 생성
- [ ] S3 버킷 생성 및 CORS 설정
- [ ] SQS 큐 생성
- [ ] IAM 역할 및 권한 설정
- [ ] Lambda Layer 업로드
- [ ] 3개 Lambda 함수 배포
- [ ] SQS 트리거 연결
- [ ] API Gateway 설정
- [ ] CORS 활성화
- [ ] API 배포
- [ ] Flutter 앱 API URL 업데이트
- [ ] 전체 플로우 테스트

🎉 **배포 완료!** 이제 AWS 순수 환경에서 확장 가능한 비동기 eye tracking 분석 시스템이 준비되었습니다!