# 🌐 API Gateway 라우터 구성 가이드

## 📋 **현재 API Gateway 구조**

### **리소스 트리**
```
RestAPI: parasol-api
└── /
    └── api/
        └── v1/
            ├── auth/
            │   ├── register           (POST, OPTIONS)
            │   └── login              (POST, OPTIONS)
            ├── upload                 (POST, OPTIONS)
            ├── status/
            │   └── {analysis_id}      (GET, OPTIONS)
            ├── results/
            │   └── {analysis_id}      (GET, OPTIONS)
            └── diagnosis/
                ├── start              (POST, OPTIONS)
                ├── {session_id}       (GET, OPTIONS)
                ├── {session_id}/complete (POST, OPTIONS)
                └── user/
                    └── {user_id}      (GET, OPTIONS)
```

### **엔드포인트 매핑**
```
인증:
POST   /api/v1/auth/register       → simple-auth Lambda
POST   /api/v1/auth/login          → simple-auth Lambda

개별 분석:
POST   /api/v1/upload              → unified-upload Lambda (인증 필요)
GET    /api/v1/status/{id}         → unified-status Lambda (인증 필요)
GET    /api/v1/status?user_id=xxx  → unified-status Lambda (인증 필요)
GET    /api/v1/results/{id}        → unified-status Lambda (인증 필요)

종합 진단:
POST   /api/v1/diagnosis/start     → comprehensive-diagnosis Lambda (인증 필요)
GET    /api/v1/diagnosis/{session_id} → comprehensive-diagnosis Lambda (인증 필요)
POST   /api/v1/diagnosis/{session_id}/complete → comprehensive-diagnosis Lambda (인증 필요)
GET    /api/v1/diagnosis/user/{user_id} → comprehensive-diagnosis Lambda (인증 필요)
```

## 🔧 **API Gateway 설정 단계**

### **1. REST API 생성**
```bash
aws apigateway create-rest-api \
    --name "parasol-api" \
    --description "Parasol Parkinson Disease Analysis API" \
    --region us-west-1
```

### **2. 리소스 생성**

#### **루트 리소스 ID 확인**
```bash
aws apigateway get-resources \
    --rest-api-id YOUR_API_ID \
    --region us-west-1
```

#### **api 리소스 생성**
```bash
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id ROOT_RESOURCE_ID \
    --path-part "api" \
    --region us-west-1
```

#### **v1 리소스 생성**
```bash
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id API_RESOURCE_ID \
    --path-part "v1" \
    --region us-west-1
```

#### **upload 리소스 생성**
```bash
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id V1_RESOURCE_ID \
    --path-part "upload" \
    --region us-west-1
```

#### **status 리소스 생성**
```bash
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id V1_RESOURCE_ID \
    --path-part "status" \
    --region us-west-1

# {analysis_id} 경로 파라미터
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id STATUS_RESOURCE_ID \
    --path-part "{analysis_id}" \
    --region us-west-1
```

#### **results 리소스 생성**
```bash
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id V1_RESOURCE_ID \
    --path-part "results" \
    --region us-west-1

# {analysis_id} 경로 파라미터
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id RESULTS_RESOURCE_ID \
    --path-part "{analysis_id}" \
    --region us-west-1
```

### **3. 메서드 생성 및 Lambda 연결**

#### **POST /upload → unified-upload Lambda**
```bash
# POST 메서드 생성
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id UPLOAD_RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region us-west-1

# Lambda 통합 설정
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id UPLOAD_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:unified-upload/invocations" \
    --region us-west-1

# Lambda 권한 부여
aws lambda add-permission \
    --function-name unified-upload \
    --statement-id api-gateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-west-1:327784329358:YOUR_API_ID/*/POST/api/v1/upload" \
    --region us-west-1
```

#### **GET /status/{analysis_id} → unified-status Lambda**
```bash
# GET 메서드 생성
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id STATUS_ANALYSIS_ID_RESOURCE_ID \
    --http-method GET \
    --authorization-type NONE \
    --request-parameters method.request.path.analysis_id=true \
    --region us-west-1

# Lambda 통합 설정
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id STATUS_ANALYSIS_ID_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:unified-status/invocations" \
    --region us-west-1

# Lambda 권한 부여
aws lambda add-permission \
    --function-name unified-status \
    --statement-id api-gateway-status-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-west-1:327784329358:YOUR_API_ID/*/GET/api/v1/status/*" \
    --region us-west-1
```

#### **GET /results/{analysis_id} → unified-status Lambda**
```bash
# GET 메서드 생성 (results)
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id RESULTS_ANALYSIS_ID_RESOURCE_ID \
    --http-method GET \
    --authorization-type NONE \
    --request-parameters method.request.path.analysis_id=true \
    --region us-west-1

# 같은 unified-status Lambda 연결
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id RESULTS_ANALYSIS_ID_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:unified-status/invocations" \
    --region us-west-1
```

### **4. CORS 설정 (AWS Console에서)**

#### **각 리소스별 CORS 설정 단계**

**1. API Gateway 콘솔 접속**
- AWS Console → API Gateway → parasol-api 선택

**2. 각 리소스에서 CORS 활성화**
- `/api/v1/auth/register` 선택 → Actions → Enable CORS
- `/api/v1/auth/login` 선택 → Actions → Enable CORS
- `/api/v1/upload` 선택 → Actions → Enable CORS
- `/api/v1/status/{analysis_id}` 선택 → Actions → Enable CORS
- `/api/v1/results/{analysis_id}` 선택 → Actions → Enable CORS
- `/api/v1/diagnosis/start` 선택 → Actions → Enable CORS
- `/api/v1/diagnosis/{session_id}` 선택 → Actions → Enable CORS
- `/api/v1/diagnosis/{session_id}/complete` 선택 → Actions → Enable CORS
- `/api/v1/diagnosis/user/{user_id}` 선택 → Actions → Enable CORS

**3. CORS 설정 값**
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token
Access-Control-Allow-Methods: GET,POST,OPTIONS

✅ 체크할 항목들:
□ Gateway Responses에서 Default 4XX 활성화
□ Gateway Responses에서 Default 5XX 활성화
□ 모든 응답에 CORS 헤더 추가
```

**4. Gateway Responses 설정 (중요!)**
- API Gateway → parasol-api → Gateway Responses
- **Default 4XX** 클릭 → Edit
  - Access-Control-Allow-Origin: '*' 추가
- **Default 5XX** 클릭 → Edit
  - Access-Control-Allow-Origin: '*' 추가

**5. 배포 필수!**
- Actions → Deploy API → Stage: prod → Deploy

## 🎯 **라우팅 로직**

### **unified-upload Lambda에서 처리**
```python
def lambda_handler(event, context):
    # analysis_type에 따라 분기
    analysis_type = body.get('analysis_type')

    if analysis_type == 'eye-tracking':
        # eye-tracking-queue로 전송
    elif analysis_type == 'finger-tapping':
        # finger-tapping-queue로 전송
    elif analysis_type == 'voice-analysis':
        # voice-analysis-queue로 전송
```

### **unified-status Lambda에서 처리**
```python
def lambda_handler(event, context):
    path = event.get('path', '')

    if '/results' in path:
        # 결과만 반환
        return get_results_only(analysis_id)
    else:
        # 상태 + 결과 반환
        return get_status_and_results(analysis_id)
```

## 📊 **API 엔드포인트 상세**

### **POST /api/v1/upload**
```json
Request:
{
  "analysis_type": "eye-tracking" | "finger-tapping" | "voice-analysis",
  "video_data": "base64_encoded_data",
  "user_id": "string",
  "parameters": {}
}

Response:
{
  "analysis_id": "uuid",
  "status": "uploaded",
  "estimated_processing_time": "2-5 minutes"
}
```

### **GET /api/v1/status/{analysis_id}**
```json
Response:
{
  "analysis_id": "uuid",
  "analysis_type": "voice-analysis",
  "status": "completed",
  "progress": 100,
  "results": {...},
  "summary": {...}
}
```

### **GET /api/v1/status?user_id=xxx**
```json
Response:
{
  "user_id": "xxx",
  "total_count": 5,
  "analyses": [
    {
      "analysis_id": "uuid1",
      "analysis_type": "eye-tracking",
      "status": "completed",
      "timestamp": 1234567890
    },
    ...
  ]
}
```

### **GET /api/v1/results/{analysis_id}**
```json
Response:
{
  "analysis_id": "uuid",
  "analysis_type": "voice-analysis",
  "results": {...},
  "summary": {...},
  "download_urls": {...}
}
```

## 🚀 **배포 및 테스트**

### **API 배포**
```bash
aws apigateway create-deployment \
    --rest-api-id YOUR_API_ID \
    --stage-name prod \
    --stage-description "Production deployment" \
    --description "Unified Parkinson Analysis API v1.0" \
    --region us-west-1
```

### **테스트 명령어**
```bash
# Health Check
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/health

# Upload Test
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{"analysis_type":"voice-analysis","video_data":"...","user_id":"test"}'

# Status Check
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status/ANALYSIS_ID
```

## 🔧 **관리 팁**

### **로그 확인**
```bash
# API Gateway 로그
aws logs describe-log-groups --log-group-name-prefix "API-Gateway-Execution-Logs"

# Lambda 로그
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

### **모니터링 설정**
- CloudWatch에서 API Gateway 메트릭 모니터링
- Lambda 실행 시간 및 오류율 추적
- DynamoDB 읽기/쓰기 용량 모니터링

이렇게 구성하면 단일 API Gateway로 3가지 분석 타입을 모두 효율적으로 처리할 수 있습니다! 🎯