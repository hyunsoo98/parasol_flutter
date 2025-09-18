# ✅ API Gateway CORS 최종 설정

## 🎯 **추가 CORS 설정이 필요한 리소스들**

기존 가이드에서 CORS가 누락된 리소스들을 추가로 설정합니다.

### **누락된 리소스들**
- `/api/v1/status` (부모 리소스)
- `/api/v1/results` (부모 리소스)
- `/api/v1/diagnosis` (부모 리소스)
- `/api/v1/diagnosis/{session_id}` (새로 추가 필요)
- `/api/v1/diagnosis/{session_id}/complete` (새로 추가 필요)

---

## **🔧 Step 1: 누락된 리소스 추가 생성**

### **1-1. {session_id} 리소스 생성 (diagnosis 하위)**
1. `/api/v1/diagnosis` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `{session_id}`
4. **Resource Path**: `{session_id}`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

### **1-2. complete 리소스 생성 ({session_id} 하위)**
1. `/api/v1/diagnosis/{session_id}` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `complete`
4. **Resource Path**: `complete`
5. **Enable API Gateway CORS**: ✅ 체크
6. **Create Resource** 클릭

---

## **🔗 Step 2: 누락된 메서드 추가**

### **2-1. GET /diagnosis/{session_id} → comprehensive-diagnosis**
1. `/api/v1/diagnosis/{session_id}` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **GET** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `comprehensive-diagnosis`
8. **Save** 클릭 → **OK** 클릭

### **2-2. POST /diagnosis/{session_id}/complete → comprehensive-diagnosis**
1. `/api/v1/diagnosis/{session_id}/complete` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. **POST** 선택 → ✅ 체크
4. **Integration type**: `Lambda Function`
5. **Use Lambda Proxy integration**: ✅ 체크
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `comprehensive-diagnosis`
8. **Save** 클릭 → **OK** 클릭

---

## **🌐 Step 3: 부모 리소스들 CORS 설정**

부모 리소스들에도 CORS를 수동으로 추가해야 합니다:

### **3-1. /api/v1/status CORS 추가**
1. `/api/v1/status` 리소스 선택
2. **Actions** → **Enable CORS** 클릭
3. **Access-Control-Allow-Origin**: `*`
4. **Access-Control-Allow-Headers**: `Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token`
5. **Access-Control-Allow-Methods**: `GET,OPTIONS`
6. **Enable CORS and replace existing CORS headers** 클릭

### **3-2. /api/v1/results CORS 추가**
1. `/api/v1/results` 리소스 선택
2. **Actions** → **Enable CORS** 클릭
3. 동일한 설정으로 **Enable CORS** 클릭

### **3-3. /api/v1/diagnosis CORS 추가**
1. `/api/v1/diagnosis` 리소스 선택
2. **Actions** → **Enable CORS** 클릭
3. **Access-Control-Allow-Methods**: `GET,POST,OPTIONS`
4. **Enable CORS** 클릭

---

## **🔄 Step 4: Gateway Responses 최종 확인**

1. **API Gateway 콘솔** → **Gateway Responses** 클릭
2. **Default 4XX** 확인:
   - `Access-Control-Allow-Origin`: `'*'` 설정되어 있는지 확인
3. **Default 5XX** 확인:
   - `Access-Control-Allow-Origin`: `'*'` 설정되어 있는지 확인

만약 설정되어 있지 않다면:
1. **Default 4XX** → **Edit**
2. **Response Headers** → **Add Header**
3. **Name**: `Access-Control-Allow-Origin`, **Value**: `'*'`
4. **Save** 클릭

---

## **📊 Step 5: 최종 엔드포인트 구조 확인**

```
✅ POST   /api/v1/auth/register        → parasol-login
✅ POST   /api/v1/auth/login           → parasol-login
✅ POST   /api/v1/upload               → unified-upload
✅ GET    /api/v1/status/{analysis_id} → unified-status
✅ GET    /api/v1/results/{analysis_id}→ unified-status
✅ POST   /api/v1/diagnosis/start      → comprehensive-diagnosis
✅ GET    /api/v1/diagnosis/{session_id} → comprehensive-diagnosis
✅ POST   /api/v1/diagnosis/{session_id}/complete → comprehensive-diagnosis
```

**모든 엔드포인트에 OPTIONS 메서드와 CORS 헤더가 설정되어야 합니다.**

---

## **🚀 Step 6: 다시 배포**

CORS 설정 변경 후 반드시 API를 다시 배포해야 합니다:

1. **Actions** → **Deploy API** 클릭
2. **Deployment stage**: `prod` 선택
3. **Deployment description**: `Added missing CORS settings`
4. **Deploy** 클릭

---

## **🧪 Step 7: CORS 테스트**

브라우저 개발자 도구에서 테스트:

```javascript
// CORS 프리플라이트 테스트
fetch('https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    email: 'test@example.com',
    password: 'password123',
    name: '테스트'
  })
})
.then(response => response.json())
.then(data => console.log('Success:', data))
.catch(error => console.error('CORS Error:', error));
```

**CORS 설정 완료!** ✅