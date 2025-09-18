# 🏗️ 파킨슨 분석 API 전체 구조도

## 📐 **시스템 아키텍처**

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │───▶│  API Gateway     │───▶│  Lambda         │
│                 │    │  (REST API)      │    │  Functions      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │   CloudWatch     │    │  SQS Queues     │
                       │   (Monitoring)   │    │  (Async Proc)   │
                       └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   DynamoDB      │◀───│     S3 Bucket    │◀───│  Processing     │
│   (Metadata)    │    │   (File Store)   │    │  Lambda         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🌐 **API Gateway 엔드포인트 구조**

### **Base URL**: `https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod`

```
RestAPI: ParkinsonAnalysisAPI
└── /api/v1/
    ├── upload                     (POST, OPTIONS)
    │   └── 📤 통합 업로드 엔드포인트
    │
    ├── status/
    │   ├── {analysis_id}          (GET, OPTIONS)
    │   │   └── 📊 개별 분석 상태 조회
    │   └── ?user_id={user_id}     (GET, OPTIONS)
    │       └── 👤 사용자별 분석 목록
    │
    ├── results/
    │   └── {analysis_id}          (GET, OPTIONS)
    │       └── 📋 분석 결과 조회
    │
    ├── diagnosis/
    │   ├── start                  (POST, OPTIONS)
    │   │   └── 🎯 종합 진단 시작
    │   ├── {session_id}           (GET, OPTIONS)
    │   │   └── 📈 진단 세션 상태
    │   ├── {session_id}/complete  (POST, OPTIONS)
    │   │   └── ✅ 진단 완료
    │   └── user/{user_id}         (GET, OPTIONS)
    │       └── 👥 사용자 진단 이력
    │
    └── health                     (GET, OPTIONS)
        └── 🏥 헬스 체크
```

## 🔄 **데이터 흐름**

### **1. 개별 분석 흐름**
```
1️⃣ Flutter App
   ↓ POST /api/v1/upload
2️⃣ API Gateway → unified-upload Lambda
   ↓ analysis_type 기반 라우팅
3️⃣ SQS Queue (eye/finger/voice)
   ↓ 트리거
4️⃣ Processing Lambda (분석 실행)
   ↓ 결과 저장
5️⃣ S3 + DynamoDB 업데이트
   ↓ 상태 변경
6️⃣ Flutter App ← GET /api/v1/status/{id}
```

### **2. 종합 진단 흐름**
```
1️⃣ Flutter App
   ↓ POST /api/v1/diagnosis/start
2️⃣ comprehensive-diagnosis Lambda
   ↓ 세션 생성
3️⃣ DynamoDB (diagnosis_sessions 테이블)
   ↓ 개별 분석들 실행
4️⃣ 3가지 분석 완료 대기
   ↓ 모든 결과 수집
5️⃣ POST /api/v1/diagnosis/{session_id}/complete
   ↓ 종합 결과 생성
6️⃣ Flutter App ← 통합 진단 결과
```

## 🗂️ **Lambda 함수 매핑**

| 엔드포인트 | Lambda 함수 | 역할 |
|-----------|-------------|------|
| `POST /upload` | `unified-upload` | 📤 파일 업로드 & 큐 전송 |
| `GET /status/*` | `unified-status` | 📊 상태/결과 조회 |
| `GET /results/*` | `unified-status` | 📋 결과만 반환 |
| `POST /diagnosis/start` | `comprehensive-diagnosis` | 🎯 종합 진단 시작 |
| `GET /diagnosis/*` | `comprehensive-diagnosis` | 📈 진단 세션 관리 |
| `POST /diagnosis/*/complete` | `comprehensive-diagnosis` | ✅ 진단 완료 |
| `SQS: eye-tracking-queue` | `eye-tracking-process` | 👁️ 아이 트래킹 분석 |
| `SQS: finger-tapping-queue` | `finger-tapping-process` | 👆 손가락 태핑 분석 |
| `SQS: voice-analysis-queue` | `voice-analysis-process` | 🎤 음성 분석 (PyTorch) |

## 🎯 **API 라우팅 로직**

### **unified-upload Lambda**
```python
def lambda_handler(event, context):
    analysis_type = body.get('analysis_type')

    if analysis_type == 'eye-tracking':
        queue_url = os.environ['EYE_TRACKING_QUEUE']
    elif analysis_type == 'finger-tapping':
        queue_url = os.environ['FINGER_TAPPING_QUEUE']
    elif analysis_type == 'voice-analysis':
        queue_url = os.environ['VOICE_ANALYSIS_QUEUE']

    # SQS로 메시지 전송
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
```

### **unified-status Lambda**
```python
def lambda_handler(event, context):
    path = event.get('path', '')

    if '/results' in path:
        return get_results_only(analysis_id)
    elif 'user_id' in event.get('queryStringParameters', {}):
        return get_user_analyses(user_id)
    else:
        return get_status_and_results(analysis_id)
```

## 🏪 **데이터 저장 구조**

### **DynamoDB 테이블**
```
analyses 테이블:
├── analysis_id (PK)
├── user_id (GSI)
├── analysis_type
├── status
├── created_at
├── updated_at
├── s3_paths
└── results

diagnosis_sessions 테이블:
├── session_id (PK)
├── user_id (GSI)
├── status
├── analyses []
├── created_at
├── updated_at
└── comprehensive_results
```

### **S3 버킷 구조**
```
parkinson-analysis-seoul-ht-09/
├── eye-tracking/
│   ├── raw/{analysis_id}/video.mp4
│   ├── processed/{analysis_id}/features.json
│   └── results/{analysis_id}/analysis.json
├── finger-tapping/
│   ├── raw/{analysis_id}/video.mp4
│   ├── processed/{analysis_id}/landmarks.json
│   └── results/{analysis_id}/analysis.json
└── voice-analysis/
    ├── raw/{analysis_id}/audio.wav
    ├── processed/{analysis_id}/features.json
    └── results/{analysis_id}/analysis.json
```

## 🔐 **보안 설정**

### **CORS 헤더**
```json
{
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Amz-Date, Authorization, X-Api-Key"
}
```

### **IAM 권한**
- Lambda 실행 역할: `lambda-execution-role`
- S3 읽기/쓰기 권한
- DynamoDB 읽기/쓰기 권한
- SQS 메시지 송/수신 권한
- CloudWatch 로그 권한

## 🚀 **배포 환경**
- **Region**: us-west-1
- **Account ID**: 327784329358
- **Stage**: prod
- **Runtime**: Python 3.9
- **Memory**: 512MB - 3008MB (함수별 차이)
- **Timeout**: 300s - 900s