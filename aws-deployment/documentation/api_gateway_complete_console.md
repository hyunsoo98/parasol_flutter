# 🌐 API Gateway 완전 설정 (AWS Console)

## 🎯 **통합 API Gateway 구성**

### **최종 API 구조**
```
/api/v1/auth/register        (POST) - 회원가입
/api/v1/auth/login           (POST) - 로그인
/api/v1/upload               (POST) - 통합 업로드
/api/v1/status/{analysis_id} (GET)  - 상태 조회
/api/v1/results/{analysis_id}(GET)  - 결과 조회
/api/v1/diagnosis/start      (POST) - 종합진단 시작
/api/v1/diagnosis/{session_id} (GET) - 진단 조회
/api/v1/diagnosis/{session_id}/complete (POST) - 진단 완료
```

---

## **🔧 Step 1: REST API 생성**

1. **API Gateway 콘솔** 접속
2. **Create API** 버튼 클릭
3. **REST API** → **Build** 선택
4. **API 설정**:
   - **API name**: `parasol-api`
   - **Description**: `Parasol Parkinson Disease Analysis API`
   - **Endpoint Type**: `Regional`
5. **Create API** 클릭

---

## **📁 Step 2: 리소스 구조 생성**

### **2-1. api 리소스 생성**
1. 루트 리소스(`/`) 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `api`
4. **Resource Path**: `api` (자동 입력)
5. **Enable API Gateway CORS**: ❌ (나중에 설정)
6. **Create Resource** 클릭

### **2-2. v1 리소스 생성**
1. `/api` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `v1`
4. **Resource Path**: `v1`
5. **Create Resource** 클릭

### **2-3. auth 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `auth`
4. **Resource Path**: `auth`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-4. register 리소스 생성**
1. `/api/v1/auth` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `register`
4. **Resource Path**: `register`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-5. login 리소스 생성**
1. `/api/v1/auth` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `login`
4. **Resource Path**: `login`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-6. upload 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `upload`
4. **Resource Path**: `upload`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-7. status 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `status`
4. **Resource Path**: `status`
5. **Create Resource** 클릭

### **2-8. {analysis_id} 리소스 생성 (status 하위)**
1. `/api/v1/status` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `{analysis_id}`
4. **Resource Path**: `{analysis_id}` (중괄호 포함)
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-9. results 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `results`
4. **Resource Path**: `results`
5. **Create Resource** 클릭

### **2-10. {analysis_id} 리소스 생성 (results 하위)**
1. `/api/v1/results` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `{analysis_id}`
4. **Resource Path**: `{analysis_id}`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **2-11. diagnosis 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `diagnosis`
4. **Resource Path**: `diagnosis`
5. **Create Resource** 클릭

### **2-12. start 리소스 생성 (diagnosis 하위)**
1. `/api/v1/diagnosis` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `start`
4. **Resource Path**: `start`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

---

## **🔗 Step 3: 메서드 생성 및 Lambda 연결**

### **3-1. POST /auth/register → parasol-login**
1. `/api/v1/auth/register` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. 드롭다운에서 **POST** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `parasol-login`
8. **Save** 클릭
9. **Add Permission to Lambda Function** 팝업 → **OK** 클릭

### **3-2. POST /auth/login → parasol-login**
1. `/api/v1/auth/login` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **POST** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `parasol-login`
8. **Save** 클릭 → **OK** 클릭

### **3-3. POST /upload → unified-upload**
1. `/api/v1/upload` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **POST** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `unified-upload`
8. **Save** 클릭 → **OK** 클릭

### **3-4. GET /status/{analysis_id} → unified-status**
1. `/api/v1/status/{analysis_id}` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **GET** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `unified-status`
8. **Save** 클릭 → **OK** 클릭

### **3-5. GET /results/{analysis_id} → unified-status**
1. `/api/v1/results/{analysis_id}` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **GET** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `unified-status`
8. **Save** 클릭 → **OK** 클릭

### **3-6. POST /diagnosis/start → comprehensive-diagnosis**
1. `/api/v1/diagnosis/start` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **POST** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `comprehensive-diagnosis`
8. **Save** 클릭 → **OK** 클릭

---

## **✅ Step 4: CORS 설정 확인**

### **자동 생성된 OPTIONS 메서드 확인**
CORS를 활성화한 리소스들에서 **OPTIONS** 메서드가 자동으로 생성되었는지 확인:

1. `/api/v1/auth/register` → **OPTIONS** 있는지 확인
2. `/api/v1/auth/login` → **OPTIONS** 있는지 확인
3. `/api/v1/upload` → **OPTIONS** 있는지 확인
4. `/api/v1/status/{analysis_id}` → **OPTIONS** 있는지 확인
5. `/api/v1/results/{analysis_id}` → **OPTIONS** 있는지 확인
6. `/api/v1/diagnosis/start` → **OPTIONS** 있는지 확인

### **Gateway Responses 설정**
1. API Gateway 콘솔에서 **Gateway Responses** 클릭
2. **Default 4XX** 선택 → **Edit**
   - **Response Headers** 추가:
   - `Access-Control-Allow-Origin`: `'*'`
   - **Save** 클릭
3. **Default 5XX** 선택 → **Edit**
   - **Response Headers** 추가:
   - `Access-Control-Allow-Origin`: `'*'`
   - **Save** 클릭

---

## **🚀 Step 5: API 배포**

1. **Actions** → **Deploy API** 클릭
2. **Deployment stage**:
   - **[New Stage]** 선택
   - **Stage name**: `prod`
   - **Stage description**: `Production stage`
   - **Deployment description**: `Initial deployment with all endpoints`
3. **Deploy** 클릭

### **API URL 확인**
배포 완료 후 **Stage Editor**에서 **Invoke URL** 확인:
```
https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod
```

---

## **🧪 Step 6: 테스트**

### **Console에서 테스트**
1. `/api/v1/auth/register` → **POST** 메서드 선택
2. **TEST** 버튼 클릭
3. **Request Body**에 입력:
```json
{
  "email": "test@example.com",
  "password": "password123",
  "name": "테스트 사용자"
}
```
4. **Test** 클릭
5. **Response Body**에서 결과 확인

### **실제 URL 테스트**
```bash
# 회원가입 테스트
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "name": "테스트 사용자"
  }'

# 로그인 테스트
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

---

## **📊 최종 확인사항**

### **✅ 체크리스트**

**리소스 구조:**
- ✅ `/api/v1/auth/register` (POST, OPTIONS)
- ✅ `/api/v1/auth/login` (POST, OPTIONS)
- ✅ `/api/v1/upload` (POST, OPTIONS)
- ✅ `/api/v1/status/{analysis_id}` (GET, OPTIONS)
- ✅ `/api/v1/results/{analysis_id}` (GET, OPTIONS)
- ✅ `/api/v1/diagnosis/start` (POST, OPTIONS)

**Lambda 연결:**
- ✅ `parasol-login` → auth endpoints
- ✅ `unified-upload` → upload endpoint
- ✅ `unified-status` → status/results endpoints
- ✅ `comprehensive-diagnosis` → diagnosis endpoints

**CORS 설정:**
- ✅ 모든 리소스에 OPTIONS 메서드 생성
- ✅ Gateway Responses에 CORS 헤더 추가

**배포:**
- ✅ prod 스테이지에 배포 완료
- ✅ API URL 동작 확인

**API Gateway 완전 설정 완료!** 🌐