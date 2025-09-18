# AWS Lambda Eye Tracking 배포 가이드

## 🚀 완전한 배포 절차

### 1단계: 준비 작업

#### 필요한 도구 설치
```bash
# AWS CLI 설치
pip install awscli

# AWS 계정 설정
aws configure
```

#### 환경 변수 설정
```bash
# 환경 변수 예시
export S3_BUCKET=your-bucket-name
export DYNAMODB_TABLE=parkinson-analysis
export AWS_REGION=ap-northeast-2
```

---

### 2단계: Lambda Layer 생성

#### Windows에서 실행:
```cmd
cd D:\parkinson
create_lambda_layer.bat
```

#### Linux/Mac에서 실행:
```bash
cd /path/to/parkinson
chmod +x create_lambda_layer.sh
./create_lambda_layer.sh
```

생성된 `eye_tracking_layer.zip` 파일이 Lambda Layer로 사용됩니다.

---

### 3단계: AWS 리소스 생성

#### 1) S3 버킷 생성
```bash
aws s3 mb s3://your-bucket-name --region ap-northeast-2
```

#### 2) DynamoDB 테이블 생성
```bash
aws dynamodb create-table \
    --table-name parkinson-analysis \
    --attribute-definitions \
        AttributeName=analysisId,AttributeType=S \
    --key-schema \
        AttributeName=analysisId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region ap-northeast-2
```

#### 3) IAM 역할 생성 (Lambda용)
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

필요한 권한:
- `AWSLambdaBasicExecutionRole`
- S3 읽기/쓰기 권한
- DynamoDB 읽기/쓰기 권한

---

### 4단계: Lambda 함수 배포

#### 1) Lambda Layer 업로드
```bash
aws lambda publish-layer-version \
    --layer-name eye-tracking-dependencies \
    --description "OpenCV, MediaPipe, NumPy, Pandas for Eye Tracking" \
    --zip-file fileb://eye_tracking_layer.zip \
    --compatible-runtimes python3.9 python3.10 python3.11 \
    --region ap-northeast-2
```

#### 2) Lambda 함수 코드 패키징
```bash
# lambda_eye_tracking.py만 압축
zip lambda_function.zip lambda_eye_tracking.py
```

#### 3) Lambda 함수 생성
```bash
aws lambda create-function \
    --function-name eye-tracking-analyzer \
    --runtime python3.9 \
    --role arn:aws:iam::YOUR_ACCOUNT_ID:role/lambda-execution-role \
    --handler lambda_eye_tracking.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --timeout 900 \
    --memory-size 3008 \
    --environment Variables='{
        "S3_BUCKET":"your-bucket-name",
        "DYNAMODB_TABLE":"parkinson-analysis"
    }' \
    --region ap-northeast-2
```

#### 4) Layer 연결
```bash
# Layer ARN 확인 후
aws lambda update-function-configuration \
    --function-name eye-tracking-analyzer \
    --layers arn:aws:lambda:ap-northeast-2:YOUR_ACCOUNT_ID:layer:eye-tracking-dependencies:1 \
    --region ap-northeast-2
```

---

### 5단계: API Gateway 설정

#### 1) REST API 생성
```bash
aws apigateway create-rest-api \
    --name "Eye-Tracking-API" \
    --description "Parkinson Eye Tracking Analysis API" \
    --region ap-northeast-2
```

#### 2) 리소스 및 메서드 생성

**AWS 콘솔에서 진행 (권장):**

1. **API Gateway 콘솔 접속**
2. **"Eye-Tracking-API" 선택**
3. **리소스 생성:**
   - `/analyze` (POST)
   - `/status/{analysisId}` (GET)

4. **메서드 설정:**
   ```
   Method: POST
   Integration type: Lambda Function
   Lambda Function: eye-tracking-analyzer
   Use Lambda Proxy integration: ✅
   ```

5. **CORS 활성화:**
   ```
   Access-Control-Allow-Origin: *
   Access-Control-Allow-Headers: Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token
   Access-Control-Allow-Methods: GET,POST,OPTIONS
   ```

#### 3) API 배포
```bash
aws apigateway create-deployment \
    --rest-api-id YOUR_API_ID \
    --stage-name prod \
    --region ap-northeast-2
```

---

### 6단계: Flutter 앱 설정

#### 1) API Gateway URL 업데이트
`lib/services/lambda_eye_tracking_service.dart` 파일에서:
```dart
static const String _apiGatewayUrl = 'https://YOUR_API_ID.execute-api.ap-northeast-2.amazonaws.com/prod';
```

#### 2) 테스트 실행
```dart
// 테스트 코드 예시
final result = await LambdaEyeTrackingService.analyzeVideo(
  videoFile: videoFile,
  userId: 'test_user',
);
```

---

### 7단계: 모니터링 및 로그

#### CloudWatch 로그 확인
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/eye-tracking-analyzer"
```

#### 성능 모니터링
- Lambda 실행 시간
- 메모리 사용량
- 에러율
- API Gateway 요청 수

---

## 🔧 주요 설정값

### Lambda 함수 설정
```
Runtime: Python 3.9
Memory: 3008 MB (최대)
Timeout: 15분 (900초)
Environment Variables:
  - S3_BUCKET: your-bucket-name
  - DYNAMODB_TABLE: parkinson-analysis
```

### API Gateway 설정
```
Request Timeout: 29초 (최대)
Payload Size: 10MB (최대)
CORS: 활성화
Binary Media Types: */*
```

---

## 🚨 주의사항

### 1. 파일 크기 제한
- Lambda: 6MB (request body)
- API Gateway: 10MB (payload)
- 큰 파일은 S3 업로드 후 처리 권장

### 2. 실행 시간 제한
- Lambda: 최대 15분
- API Gateway: 최대 29초
- 장시간 처리는 비동기 패턴 사용

### 3. 비용 최적화
```bash
# 사용하지 않는 리소스 정리
aws lambda delete-function --function-name eye-tracking-analyzer
aws s3 rb s3://your-bucket-name --force
aws dynamodb delete-table --table-name parkinson-analysis
```

---

## 📱 Flutter 통합

### pubspec.yaml 의존성
```yaml
dependencies:
  http: ^1.1.0
  camera: ^0.10.5
  path_provider: ^2.1.1
```

### 사용 예시
```dart
import 'package:your_app/services/lambda_eye_tracking_service.dart';
import 'package:your_app/screens/lambda_eye_tracking_screen.dart';

// 화면 네비게이션
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const LambdaEyeTrackingScreen(),
  ),
);
```

---

## 🔍 트러블슈팅

### 자주 발생하는 오류들

#### 1. "Module not found" 오류
**해결방법:** Layer가 제대로 연결되었는지 확인
```bash
aws lambda get-function --function-name eye-tracking-analyzer
```

#### 2. "Request timeout" 오류
**해결방법:** 
- 파일 크기 줄이기
- 비동기 처리 패턴 적용
- Step 값 증가 (프레임 건너뛰기)

#### 3. "Permission denied" 오류
**해결방법:** IAM 역할 권한 확인
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-2:*:table/parkinson-analysis"
    }
  ]
}
```

#### 4. CORS 오류
**해결방법:** API Gateway에서 CORS 재설정
```bash
# OPTIONS 메서드 추가 필요
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id YOUR_RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE
```

---

## ✅ 배포 완료 체크리스트

- [ ] AWS CLI 설정 완료
- [ ] S3 버킷 생성
- [ ] DynamoDB 테이블 생성
- [ ] IAM 역할 및 권한 설정
- [ ] Lambda Layer 업로드
- [ ] Lambda 함수 배포
- [ ] Layer 연결 확인
- [ ] API Gateway 설정
- [ ] CORS 활성화
- [ ] API 배포
- [ ] Flutter 앱에서 API URL 업데이트
- [ ] 테스트 실행 성공

배포가 완료되면 Flutter 앱에서 AWS Lambda의 고성능 눈 추적 분석을 사용할 수 있습니다! 🎉