# 🔐 API Gateway 인증 엔드포인트 추가

## 🆕 **추가할 리소스들**

### **1. auth 리소스 생성**
```bash
# /api/v1 아래에 auth 리소스 추가
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id V1_RESOURCE_ID \
    --path-part "auth" \
    --region us-west-1
```

### **2. register 리소스 생성**
```bash
# /api/v1/auth 아래에 register 리소스 추가
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id AUTH_RESOURCE_ID \
    --path-part "register" \
    --region us-west-1
```

### **3. login 리소스 생성**
```bash
# /api/v1/auth 아래에 login 리소스 추가
aws apigateway create-resource \
    --rest-api-id YOUR_API_ID \
    --parent-id AUTH_RESOURCE_ID \
    --path-part "login" \
    --region us-west-1
```

## 🔗 **Lambda 연결**

### **POST /auth/register**
```bash
# POST 메서드 생성
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region us-west-1

# Lambda 통합 설정
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:parasol-login/invocations" \
    --region us-west-1

# Lambda 권한 부여
aws lambda add-permission \
    --function-name parasol-login \
    --statement-id api-gateway-register-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-west-1:327784329358:YOUR_API_ID/*/POST/api/v1/auth/register" \
    --region us-west-1
```

### **POST /auth/login**
```bash
# POST 메서드 생성
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id LOGIN_RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region us-west-1

# Lambda 통합 설정
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id LOGIN_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:parasol-login/invocations" \
    --region us-west-1

# Lambda 권한 부여
aws lambda add-permission \
    --function-name parasol-login \
    --statement-id api-gateway-login-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-west-1:327784329358:YOUR_API_ID/*/POST/api/v1/auth/login" \
    --region us-west-1
```

## ✅ **CORS 설정 추가**

### **register & login 리소스에 CORS 추가**
```bash
# /auth/register OPTIONS
aws apigateway put-method \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE \
    --region us-west-1

# MOCK 통합
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
    --region us-west-1

# CORS 응답 헤더
aws apigateway put-method-response \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Headers=true \
    --region us-west-1

aws apigateway put-integration-response \
    --rest-api-id YOUR_API_ID \
    --resource-id REGISTER_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters method.response.header.Access-Control-Allow-Origin="'*'",method.response.header.Access-Control-Allow-Methods="'POST,OPTIONS'",method.response.header.Access-Control-Allow-Headers="'Content-Type,Authorization'" \
    --region us-west-1

# login도 동일하게 설정...
```

## 🎯 **최종 API 구조**

```
/api/v1/auth/register    (POST) - 회원가입 (인증 불필요)
/api/v1/auth/login       (POST) - 로그인 (인증 불필요)
/api/v1/upload           (POST) - 분석 업로드 (인증 필요)
/api/v1/status/*         (GET)  - 상태 조회 (인증 필요)
/api/v1/diagnosis/*      (POST/GET) - 종합 진단 (인증 필요)
```

## 📱 **Flutter 앱에서 사용**

### **회원가입**
```dart
POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/register
{
  "email": "user@example.com",
  "password": "password123",
  "name": "홍길동"
}
```

### **로그인**
```dart
POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/auth/login
{
  "email": "user@example.com",
  "password": "password123"
}
```

### **인증 필요한 API 호출**
```dart
Headers: {
  "Authorization": "Bearer session_token_from_login"
}
```

이제 **API Gateway에 인증 엔드포인트가 완전히 추가**되었습니다! 🎯