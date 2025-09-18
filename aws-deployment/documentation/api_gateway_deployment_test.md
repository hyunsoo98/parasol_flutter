# 🚀 API Gateway 배포 및 테스트

## 📋 **배포 전 최종 체크리스트**

### **✅ 리소스 구조 확인**
```
/api/v1/auth/register        ✅ POST, OPTIONS
/api/v1/auth/login           ✅ POST, OPTIONS
/api/v1/upload               ✅ POST, OPTIONS
/api/v1/status               ✅ OPTIONS
/api/v1/status/{analysis_id} ✅ GET, OPTIONS
/api/v1/results              ✅ OPTIONS
/api/v1/results/{analysis_id}✅ GET, OPTIONS
/api/v1/diagnosis            ✅ OPTIONS
/api/v1/diagnosis/start      ✅ POST, OPTIONS
/api/v1/diagnosis/{session_id} ✅ GET, OPTIONS
/api/v1/diagnosis/{session_id}/complete ✅ POST, OPTIONS
```

### **✅ Lambda 연결 확인**
- `parasol-login` → auth endpoints
- `unified-upload` → upload endpoint
- `unified-status` → status/results endpoints
- `comprehensive-diagnosis` → diagnosis endpoints

---

## **🚀 Step 1: 최종 배포**

1. **API Gateway 콘솔** → `parasol-api` 선택
2. **Actions** → **Deploy API** 클릭
3. **Deployment stage**: `prod` 선택
4. **Deployment description**: `Complete API with all endpoints and CORS`
5. **Deploy** 클릭

### **배포 URL 확인**
```
https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod
```

---

## **🧪 Step 2: 엔드포인트별 테스트**

### **2-1. 회원가입 테스트 (IAM 권한 문제로 실패 예상)**
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "name": "테스트 사용자"
  }'
```

**예상 결과**: DynamoDB 권한 오류 (나중에 해결)

### **2-2. 로그인 테스트**
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### **2-3. 업로드 테스트**
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload \
  -H "Content-Type: application/json" \
  -d '{
    "analysis_type": "voice-analysis",
    "audio_data": "base64_encoded_data",
    "user_id": "test_user"
  }'
```

### **2-4. 상태 조회 테스트**
```bash
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status/test_analysis_id
```

### **2-5. 결과 조회 테스트**
```bash
curl https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/results/test_analysis_id
```

### **2-6. 종합 진단 시작 테스트**
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/diagnosis/start \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test_user",
    "analysis_ids": ["eye_001", "finger_002", "voice_003"]
  }'
```

---

## **🔍 Step 3: CORS 테스트**

### **3-1. 브라우저에서 CORS 테스트**
브라우저 개발자 도구에서 실행:

```javascript
// OPTIONS 프리플라이트 요청 테스트
fetch('https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register', {
  method: 'OPTIONS'
})
.then(response => {
  console.log('CORS Headers:', response.headers);
  console.log('Access-Control-Allow-Origin:', response.headers.get('Access-Control-Allow-Origin'));
  console.log('Access-Control-Allow-Methods:', response.headers.get('Access-Control-Allow-Methods'));
})
.catch(error => console.error('CORS Error:', error));
```

### **3-2. 실제 POST 요청 테스트**
```javascript
fetch('https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    email: 'test@example.com',
    password: 'password123',
    name: '테스트'
  })
})
.then(response => response.json())
.then(data => console.log('Response:', data))
.catch(error => console.error('Error:', error));
```

---

## **📊 Step 4: CloudWatch 로그 확인**

### **4-1. Lambda 함수 로그 확인**
1. **CloudWatch 콘솔** → **Logs** → **Log groups**
2. 다음 로그 그룹들 확인:
   - `/aws/lambda/parasol-login`
   - `/aws/lambda/unified-upload`
   - `/aws/lambda/unified-status`
   - `/aws/lambda/comprehensive-diagnosis`

### **4-2. API Gateway 로그 확인**
1. **CloudWatch 콘솔** → **Logs** → **Log groups**
2. `API-Gateway-Execution-Logs_YOUR_API_ID/prod` 확인

---

## **⚠️ Step 5: 예상되는 문제들**

### **5-1. DynamoDB 권한 오류**
```json
{
  "errorType": "AccessDeniedException",
  "errorMessage": "User is not authorized to perform: dynamodb:Scan"
}
```
**해결**: IAM 역할에 DynamoDB 권한 추가 (나중에 처리)

### **5-2. Lambda 함수 미배포**
```json
{
  "message": "Internal server error"
}
```
**해결**: Lambda 함수가 올바르게 배포되었는지 확인

### **5-3. 환경변수 누락**
CloudWatch 로그에서 확인:
```
KeyError: 'DYNAMODB_TABLE'
```
**해결**: Lambda 환경변수 재확인

### **5-4. CORS 오류**
브라우저 콘솔에서:
```
Access to fetch at '...' has been blocked by CORS policy
```
**해결**: CORS 설정 재확인 및 재배포

---

## **✅ Step 6: 성공 기준**

### **6-1. 기본 연결 테스트**
- ✅ 모든 엔드포인트에서 200 또는 500 응답 (404 아님)
- ✅ CORS 헤더가 올바르게 설정됨
- ✅ Lambda 함수가 실행됨 (CloudWatch 로그 확인)

### **6-2. 기능 테스트 (IAM 권한 해결 후)**
- ✅ 회원가입/로그인 성공
- ✅ 파일 업로드 성공
- ✅ 상태 조회 성공
- ✅ 결과 조회 성공

---

## **📱 Step 7: Flutter 연동 준비**

API Gateway 테스트가 완료되면 Flutter 앱에서 사용할 설정:

```dart
class ApiConfig {
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // Auth endpoints
  static const String registerUrl = '$baseUrl/api/v1/auth/register';
  static const String loginUrl = '$baseUrl/api/v1/auth/login';

  // Analysis endpoints
  static const String uploadUrl = '$baseUrl/api/v1/upload';
  static const String statusUrl = '$baseUrl/api/v1/status';
  static const String resultsUrl = '$baseUrl/api/v1/results';

  // Diagnosis endpoints
  static const String diagnosisStartUrl = '$baseUrl/api/v1/diagnosis/start';
  static const String diagnosisUrl = '$baseUrl/api/v1/diagnosis';
}
```

**API Gateway 배포 및 테스트 완료!** 🚀