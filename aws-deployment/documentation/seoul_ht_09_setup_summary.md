# 🎯 seoul-ht-09/parasol/ 버킷 활용 설정 요약

기존 `seoul-ht-09/parasol/` 구조를 활용한 완전한 설정 가이드입니다.

## 📁 최종 파일 구조

```
seoul-ht-09/parasol/
├── videos/                              # ✅ 기존 + Eye tracking 비디오
│   └── user123/
│       └── analysis-abc123/
│           └── input.mp4               # 업로드된 원본 비디오
├── results/                             # ✅ 기존 + Eye tracking 분석 결과  
│   └── user123/
│       └── analysis-abc123/
│           └── analysis_results.csv    # 분석 결과 CSV
├── tapping/                             # ✅ 기존 tapping 데이터
├── voice/                               # ✅ 기존 voice 데이터
└── temp/                                # ✅ 기존 임시 파일들
```

## 🔧 Lambda 함수 환경 변수 설정

### 모든 Lambda 함수 (Upload, Process, Status)에 공통 적용:

```
S3_BUCKET=seoul-ht-09
S3_PREFIX=parasol/
SQS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/계정번호/eye-tracking-queue
DYNAMODB_TABLE=eye-tracking-results
```

## 📝 코드 변경 완료 사항

### ✅ Upload Lambda (`lambda_upload.py`)
```python
# 환경 변수 추가
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')

# S3 키 생성
s3_key = f"{S3_PREFIX}videos/{user_id}/{analysis_id}/input.mp4"
# 결과: parasol/videos/user123/analysis-abc123/input.mp4
```

### ✅ Process Lambda (`lambda_process.py`)
```python  
# 환경 변수 추가
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')

# CSV 결과 저장
csv_s3_key = f"{S3_PREFIX}results/{user_id}/{analysis_id}/analysis_results.csv"
# 결과: parasol/results/user123/analysis-abc123/analysis_results.csv
```

### ✅ Status Lambda (`lambda_status.py`)
```python
# 환경 변수 추가
S3_PREFIX = os.environ.get('S3_PREFIX', 'parasol/')
```

## 🖥️ AWS 콘솔 설정 단계

### 1. DynamoDB 테이블 생성 (기존 가이드 동일)
- 테이블명: `eye-tracking-results`
- 파티션키: `analysis_id`

### 2. SQS 큐 생성 (기존 가이드 동일)  
- 큐명: `eye-tracking-queue`

### 3. S3 버킷 설정
#### 기존 `seoul-ht-09` 버킷 사용
1. **S3 콘솔 → `seoul-ht-09` 버킷 선택**
2. **권한 탭 → CORS 편집**
3. **기존 CORS 설정에 추가 (또는 새로 설정):**
```json
[
    {
        "AllowedHeaders": ["*"],
        "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
        "AllowedOrigins": ["*"],
        "ExposeHeaders": ["ETag"],
        "MaxAgeSeconds": 3000
    }
]
```

### 4. Lambda 함수 생성 및 환경 변수 설정

#### Upload 함수
- **함수명**: `eye-tracking-upload`
- **환경 변수**:
  - `S3_BUCKET`: `seoul-ht-09`
  - `S3_PREFIX`: `parasol/`
  - `SQS_QUEUE_URL`: `https://sqs.us-west-1.amazonaws.com/계정번호/eye-tracking-queue`
  - `DYNAMODB_TABLE`: `eye-tracking-results`

#### Process 함수  
- **함수명**: `eye-tracking-process`
- **환경 변수**: Upload와 동일 (SQS_QUEUE_URL 제외)
- **SQS 트리거 연결 필요**

#### Status 함수
- **함수명**: `eye-tracking-status`  
- **환경 변수**: 
  - `S3_BUCKET`: `seoul-ht-09`
  - `S3_PREFIX`: `parasol/`
  - `DYNAMODB_TABLE`: `eye-tracking-results`

### 5. API Gateway 설정 (기존 가이드 동일)
- `/upload` → Upload Lambda 연결
- `/status/{analysis_id}` → Status Lambda 연결

## 🎯 Flutter 앱 설정

`lib/services/aws_async_eye_tracking_service.dart` 에서:
```dart
static const String _baseUrl = 'https://실제API주소.execute-api.us-west-1.amazonaws.com/prod';
```

## ✅ 완료 체크리스트

- [ ] `seoul-ht-09` 버킷 CORS 설정 확인/업데이트
- [ ] DynamoDB 테이블 `eye-tracking-results` 생성  
- [ ] SQS 큐 `eye-tracking-queue` 생성
- [ ] Upload Lambda 함수 생성 + 환경변수 설정
- [ ] Process Lambda 함수 생성 + 환경변수 설정 + SQS 트리거
- [ ] Status Lambda 함수 생성 + 환경변수 설정
- [ ] API Gateway 생성 및 배포
- [ ] Flutter 앱 API URL 업데이트

## 🚀 주요 장점

- ✅ **기존 구조 활용** - 새 버킷 생성 불필요
- ✅ **권한 재사용** - 기존 IAM 설정 활용 가능
- ✅ **통합 관리** - 모든 파킨슨 데이터가 한 곳에
- ✅ **폴더 자동 생성** - 첫 업로드시 하위 폴더 자동 생성

## 🎉 설정 완료!

이제 기존 `seoul-ht-09/parasol/` 구조를 활용하여 AWS Lambda Eye Tracking 시스템을 사용할 수 있습니다!