# 🏗️ AWS 아키텍처 흐름도

## 📐 **전체 시스템 아키텍처**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    PARASOL AWS ARCHITECTURE                              │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                  │    │                 │    │                 │
│  Flutter App    │───▶│  API Gateway     │───▶│  Lambda         │───▶│  DynamoDB       │
│                 │    │  (parasol-api)   │    │  (unified-*)    │    │  (analyses)     │
│                 │    │                  │    │                 │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                │                       ▼
                                │              ┌─────────────────┐
                                │              │  SQS Queues     │
                                │              │  - eye-queue    │
                                │              │  - finger-queue │
                                │              │  - voice-queue  │
                                │              └─────────────────┘
                                │                       │
                                │                       ▼
                                │              ┌─────────────────┐
                                │              │  Processing     │
                                │              │  Lambdas        │
                                │              │  - eye-process  │
                                │              │  - finger-proc  │
                                │              │  - voice-proc   │
                                │              └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │  S3 Bucket      │    │  CloudWatch     │
                       │  (seoul-ht-09)  │    │  (Logs/Monitor) │
                       │                 │    │                 │
                       └─────────────────┘    └─────────────────┘
```

## 🔄 **데이터 흐름 (순차 분석)**

### **Phase 1: 개별 분석 업로드**
```
1️⃣ Flutter App
   ↓ POST /api/v1/upload (analysis_type: "eye-tracking")

2️⃣ API Gateway (parasol-api)
   ↓ Route to unified-upload Lambda

3️⃣ unified-upload Lambda
   ├─ Save video to S3: eye-tracking/{analysis_id}/video.mp4
   ├─ Create record in DynamoDB: analyses table
   └─ Send message to SQS: eye-tracking-queue
   ↓ Return analysis_id to Flutter

4️⃣ SQS eye-tracking-queue
   ↓ Trigger (async)

5️⃣ eye-tracking-process Lambda
   ├─ Download video from S3
   ├─ Process with MediaPipe (eye movement analysis)
   ├─ Save results to S3: eye-tracking/{analysis_id}/result.json
   └─ Update DynamoDB: status = "completed"
```

### **Phase 2: 상태 확인**
```
1️⃣ Flutter App (polling)
   ↓ GET /api/v1/status/{analysis_id}

2️⃣ API Gateway
   ↓ Route to unified-status Lambda

3️⃣ unified-status Lambda
   ├─ Query DynamoDB for analysis status
   ├─ If completed: fetch results from S3
   └─ Return status + results to Flutter
```

### **Phase 3: 종합 진단**
```
1️⃣ Flutter App (after all 3 analyses complete)
   ↓ POST /api/v1/diagnosis/start

2️⃣ API Gateway
   ↓ Route to comprehensive-diagnosis Lambda

3️⃣ comprehensive-diagnosis Lambda
   ├─ Create diagnosis session in DynamoDB
   ├─ Collect all analysis results from S3
   ├─ Generate comprehensive report
   ├─ Save to S3: diagnosis/{session_id}/comprehensive.json
   └─ Return session_id to Flutter
```

## 🎯 **컴포넌트별 상세 흐름**

### **API Gateway Routes**
```
/api/v1/upload
├─ POST → unified-upload Lambda
└─ OPTIONS → CORS preflight

/api/v1/status/{analysis_id}
├─ GET → unified-status Lambda
└─ OPTIONS → CORS preflight

/api/v1/results/{analysis_id}
├─ GET → unified-status Lambda
└─ OPTIONS → CORS preflight

/api/v1/diagnosis/*
├─ POST/GET → comprehensive-diagnosis Lambda
└─ OPTIONS → CORS preflight
```

### **Lambda Functions 매핑**
```
Frontend Functions:
├─ unified-upload: File upload + SQS routing
├─ unified-status: Status/Results query
└─ comprehensive-diagnosis: Multi-modal analysis

Backend Processing:
├─ eye-tracking-process: MediaPipe analysis
├─ finger-tapping-process: AdaBoost ML model
└─ voice-analysis-process: PyTorch CNN+BiGRU+MLP
```

### **Data Storage 구조**
```
DynamoDB Tables:
├─ analyses: Individual analysis metadata
└─ diagnosis_sessions: Comprehensive diagnosis sessions

S3 Bucket (seoul-ht-09):
├─ eye-tracking/{analysis_id}/
│  ├─ video.mp4 (original)
│  └─ result.json (processed)
├─ finger-tapping/{analysis_id}/
│  ├─ video.mp4 (original)
│  └─ result.json (processed)
├─ voice-analysis/{analysis_id}/
│  ├─ audio.wav (original)
│  └─ result.json (processed)
└─ diagnosis/{session_id}/
   └─ comprehensive.json (final report)
```

## ⚡ **비동기 처리 흐름**

### **SQS Message Flow**
```
unified-upload Lambda
├─ analysis_type == "eye-tracking" → eye-tracking-queue
├─ analysis_type == "finger-tapping" → finger-tapping-queue
└─ analysis_type == "voice-analysis" → voice-analysis-queue

Queue Triggers:
├─ eye-tracking-queue → eye-tracking-process Lambda
├─ finger-tapping-queue → finger-tapping-process Lambda
└─ voice-analysis-queue → voice-analysis-process Lambda
```

### **Error Handling & Monitoring**
```
CloudWatch Logs:
├─ /aws/lambda/unified-upload
├─ /aws/lambda/unified-status
├─ /aws/lambda/comprehensive-diagnosis
├─ /aws/lambda/eye-tracking-process
├─ /aws/lambda/finger-tapping-process
└─ /aws/lambda/voice-analysis-process

CloudWatch Metrics:
├─ Lambda execution duration
├─ Lambda error rates
├─ SQS message counts
├─ API Gateway latency
└─ DynamoDB read/write capacity
```

## 🎨 **Architecture Diagram 요소들**

### **AWS 서비스 아이콘 배치**
```
Top Layer: Flutter App (모바일)
↓
Second Layer: API Gateway (REST API)
↓
Third Layer: Lambda Functions (서버리스)
↓
Fourth Layer: SQS Queues (메시징)
↓
Fifth Layer: Processing Lambdas (AI/ML)
↓
Bottom Layer: Storage (S3 + DynamoDB)
Side: CloudWatch (모니터링)
```

이 흐름도를 바탕으로 AWS 아키텍처 다이어그램을 그리시면 됩니다! 🚀