# AWS Lambda 시선 추적 함수 배포 가이드

## 📋 개요
`lambda_eye_tracking.py` 코드를 AWS Lambda 함수로 배포하는 단계별 가이드입니다.

## 🔧 1단계: Lambda 함수 생성

### 1.1 AWS Lambda 콘솔 접속
1. [AWS Lambda 콘솔](https://console.aws.amazon.com/lambda/) 접속
2. "함수 생성" 클릭

### 1.2 함수 설정
- **함수 이름**: `parkinson-eye-tracking`
- **런타임**: `Python 3.9`
- **아키텍처**: `x86_64`
- **실행 역할**: "기본 실행 역할이 있는 새 역할 생성"

## ⚙️ 2단계: 환경 변수 설정

### 2.1 환경 변수 추가
Lambda 함수 → **구성** → **환경 변수** 탭:

| 키 | 값 | 설명 |
|---|---|---|
| `S3_BUCKET` | `seoul-ht-09` | S3 버킷명 |
| `DYNAMODB_TABLE` | `parkinson-analysis` | DynamoDB 테이블명 |

## 🔐 3단계: IAM 권한 설정

### 3.1 실행 역할 권한 추가
Lambda 함수 → **구성** → **권한** 탭 → **실행 역할** 클릭

### 3.2 정책 연결
다음 정책들을 연결하거나 인라인 정책 생성:

#### S3 권한 정책:
```json
{
    "Version": "2012-10-17",
    "Statement": [
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
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::seoul-ht-09"
        }
    ]
}
```

#### DynamoDB 권한 정책:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:us-west-1:*:table/parkinson-analysis"
        }
    ]
}
```

## 📚 4단계: Lambda Layer 설정

### 4.1 필요한 라이브러리
다음 라이브러리들이 필요합니다:
- `opencv-python`
- `mediapipe`
- `numpy`
- `pandas`

### 4.2 Layer 생성 방법

#### 옵션 1: 공개 Layer 사용
1. Lambda 함수 → **레이어** → **레이어 추가**
2. 다음 ARN들을 검색하여 추가:
   - OpenCV: `arn:aws:lambda:us-west-1:770693421928:layer:Klayers-p39-opencv-python:1`
   - NumPy/Pandas: `arn:aws:lambda:us-west-1:770693421928:layer:Klayers-p39-pandas:1`

#### 옵션 2: 커스텀 Layer 생성
```bash
# 로컬에서 라이브러리 패키징
mkdir python
pip install opencv-python mediapipe numpy pandas -t python/
zip -r opencv-mediapipe-layer.zip python/

# Layer 업로드 및 함수에 연결
```

## 💻 5단계: 함수 코드 배포

### 5.1 코드 업로드
1. Lambda 함수 → **코드** 탭
2. 코드 편집기에서 기존 `lambda_function.py` 삭제
3. `lambda_eye_tracking.py` 내용을 복사하여 붙여넣기
4. 파일명을 `lambda_function.py`로 변경
5. **Deploy** 버튼 클릭

### 5.2 핸들러 설정
**런타임 설정**에서 핸들러가 `lambda_function.lambda_handler`인지 확인

## ⚡ 6단계: 함수 구성 최적화

### 6.1 메모리 및 타임아웃 설정
Lambda 함수 → **구성** → **일반 구성**:
- **메모리**: `1024 MB` (이미지 처리용)
- **제한 시간**: `5분` (동영상 처리용)
- **임시 스토리지**: `512 MB`

### 6.2 동시 실행 설정
- **예약된 동시 실행**: `10` (비용 제어)
- **프로비저닝된 동시 실행**: 필요시 설정

## 🔗 7단계: API Gateway 연동

### 7.1 트리거 추가
1. Lambda 함수 → **함수 개요** → **트리거 추가**
2. **API Gateway** 선택
3. **API 유형**: REST API
4. **보안**: API 키 (선택사항)

### 7.2 API Gateway 설정
생성된 API Gateway에서:
1. **리소스** → **작업** → **CORS 활성화**
2. **작업** → **API 배포**
3. **배포 스테이지**: `dev`

## 🧪 8단계: 테스트

### 8.1 Lambda 콘솔에서 테스트
테스트 이벤트 생성:
```json
{
    "action": "analyze_image",
    "file_data": "base64_encoded_image_data_here",
    "user_id": "test_user_123",
    "parameters": {}
}
```

### 8.2 API Gateway 테스트
```bash
# 헬스체크 (GET)
curl -X GET https://[api-id].execute-api.us-west-1.amazonaws.com/dev/

# 이미지 분석 (POST)
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "analyze_image",
    "file_data": "base64_image_data",
    "user_id": "test_user"
  }'
```

## 📊 9단계: 모니터링 설정

### 9.1 CloudWatch 대시보드
Lambda 함수 → **모니터링** 탭에서 확인:
- 호출 횟수
- 오류율
- 지속 시간
- 메모리 사용률

### 9.2 로그 확인
CloudWatch Logs에서 `/aws/lambda/parkinson-eye-tracking` 로그 그룹 모니터링

## 🚨 10단계: 문제 해결

### 10.1 일반적인 오류

#### "Unable to import module 'lambda_function'"
- **해결**: Layer가 제대로 연결되었는지 확인
- **해결**: `requirements.txt` 없이 직접 코드만 업로드했는지 확인

#### "Task timed out after 3.00 seconds"
- **해결**: 제한 시간을 5분으로 증가
- **해결**: 메모리를 1024MB 이상으로 설정

#### "Access Denied" 오류
- **해결**: IAM 역할에 S3, DynamoDB 권한 추가
- **해결**: 리소스 ARN이 올바른지 확인

#### MediaPipe Import 오류
- **해결**: MediaPipe Layer 추가 또는 커스텀 Layer 생성
- **해결**: ARM64 대신 x86_64 아키텍처 사용

### 10.2 성능 최적화

#### 콜드 스타트 개선
- 프로비저닝된 동시 실행 설정
- 글로벌 변수로 모델 캐싱 (이미 구현됨)

#### 메모리 사용량 최적화
```python
# 큰 변수는 명시적으로 삭제
del large_numpy_array
import gc
gc.collect()
```

## 📝 11단계: API 문서

### 11.1 지원 액션
- `analyze_image`: 단일 이미지 분석
- `analyze_video`: 동영상 프레임별 분석  
- `process_s3_file`: S3 파일 직접 처리

### 11.2 요청 형식
```json
{
    "action": "analyze_video",
    "file_data": "base64_encoded_data",
    "user_id": "user_identifier",
    "file_name": "video.mp4",
    "parameters": {
        "step": 1,
        "vpp_thresh": 0.06,
        "blink_thresh": 0.18,
        "max_frames": 12000,
        "blink_min_frames": 2
    }
}
```

### 11.3 응답 형식
```json
{
    "analysis_id": "uuid-string",
    "summary": {
        "frames_processed": 1500,
        "psp_suspected": false,
        "blink_count": 45,
        "vertical_peak_to_peak": 0.12
    },
    "video_path": "s3://bucket/path/to/video",
    "csv_path": "s3://bucket/path/to/results.csv",
    "status": "success"
}
```

## ✅ 완료!

이제 `parkinson-eye-tracking` Lambda 함수가 성공적으로 배포되어 시선 추적 분석을 수행할 수 있습니다.

**다음 단계**: Flutter 앱에서 이 API를 호출하여 실제 파킨슨병 스크리닝 기능을 구현하세요.

## 🔗 관련 문서
- [AWS Lambda 개발자 가이드](https://docs.aws.amazon.com/lambda/)
- [API Gateway 설정 가이드](../AWS_SETUP_GUIDE.md#5단계-api-gateway-설정)
- [Flutter 앱 연동 가이드](../AWS_SETUP_GUIDE.md#7단계-flutter-앱-설정)