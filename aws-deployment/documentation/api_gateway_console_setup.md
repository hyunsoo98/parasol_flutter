# 🖥️ AWS Console에서 API Gateway 직접 설정

## 🔧 **1. 인증 리소스 생성**

### **Step 1: API Gateway 콘솔 접속**
1. AWS Console → **API Gateway** 서비스 이동
2. **parasol-api** REST API 선택
3. 왼쪽 **Resources** 탭 클릭

### **Step 2: auth 리소스 생성**
1. `/api/v1` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `auth`
4. **Resource Path**: `auth` (자동 입력됨)
5. **Enable API Gateway CORS** 체크 ✅
6. **Create Resource** 클릭

### **Step 3: register 리소스 생성**
1. 방금 생성한 `/api/v1/auth` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `register`
4. **Resource Path**: `register`
5. **Enable API Gateway CORS** 체크 ✅
6. **Create Resource** 클릭

### **Step 4: login 리소스 생성**
1. `/api/v1/auth` 리소스 선택
2. **Actions** → **Create Resource** 클릭
3. **Resource Name**: `login`
4. **Resource Path**: `login`
5. **Enable API Gateway CORS** 체크 ✅
6. **Create Resource** 클릭

## 🔗 **2. Lambda 함수 연결**

### **register에 POST 메서드 추가**
1. `/api/v1/auth/register` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. 드롭다운에서 **POST** 선택 → ✅ 체크
4. **Integration type**: **Lambda Function**
5. **Use Lambda Proxy integration** 체크 ✅
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `parasol-login`
8. **Save** 클릭
9. **Add Permission to Lambda Function** 팝업 → **OK** 클릭

### **login에 POST 메서드 추가**
1. `/api/v1/auth/login` 리소스 선택
2. **Actions** → **Create Method** 클릭
3. 드롭다운에서 **POST** 선택 → ✅ 체크
4. **Integration type**: **Lambda Function**
5. **Use Lambda Proxy integration** 체크 ✅
6. **Lambda Region**: `us-west-1`
7. **Lambda Function**: `parasol-login`
8. **Save** 클릭
9. **Add Permission to Lambda Function** 팝업 → **OK** 클릭

## ✅ **3. CORS 설정 (자동 완료)**

**리소스 생성 시 "Enable API Gateway CORS"를 체크했으므로 자동으로 완료됩니다!**

### **확인 방법**
1. `/api/v1/auth/register` 리소스 선택
2. **OPTIONS** 메서드가 자동 생성되었는지 확인
3. **POST** 메서드 클릭 → **Method Response** 확인
4. **200** 응답에 다음 헤더들이 있는지 확인:
   - `Access-Control-Allow-Origin`
   - `Access-Control-Allow-Methods`
   - `Access-Control-Allow-Headers`

## 🚀 **4. API 배포**

### **배포하기**
1. API Gateway 콘솔에서 **Actions** → **Deploy API** 클릭
2. **Deployment stage**: `prod` (기존 선택)
3. **Deployment description**: `Added auth endpoints`
4. **Deploy** 클릭

### **배포 URL 확인**
배포 완료 후 **Stage Editor**에서 **Invoke URL** 확인:
```
https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod
```

## 🧪 **5. 테스트**

### **Console에서 테스트**
1. `/api/v1/auth/register` → **POST** 메서드 선택
2. **TEST** 버튼 클릭
3. **Request Body**에 입력:
   ```json
   {
     "email": "test@example.com",
     "password": "password123",
     "name": "테스트"
   }
   ```
4. **Test** 클릭
5. **Response Body**에서 결과 확인

### **실제 URL 테스트**
```bash
curl -X POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "name": "테스트"
  }'
```

## 📊 **최종 구조 확인**

Resources 탭에서 다음과 같은 구조가 보여야 합니다:

```
/
└── api
    └── v1
        ├── auth
        │   ├── register
        │   │   ├── POST (→ parasol-login)
        │   │   └── OPTIONS (CORS)
        │   └── login
        │       ├── POST (→ parasol-login)
        │       └── OPTIONS (CORS)
        ├── upload
        ├── status
        └── diagnosis
```

## 🔍 **문제 해결**

### **Lambda 함수 연결 안됨**
- **Lambda Region**이 `us-west-1`인지 확인
- **parasol-login** 함수명이 정확한지 확인
- Lambda 함수에 API Gateway 실행 권한이 있는지 확인

### **CORS 에러**
- **Enable API Gateway CORS** 체크했는지 확인
- 배포를 다시 했는지 확인
- OPTIONS 메서드가 생성되었는지 확인

### **404 에러**
- API를 배포했는지 확인
- URL 경로가 정확한지 확인 (`/api/v1/auth/register`)

이 방법으로 AWS Console에서 직접 설정할 수 있습니다! 🎯