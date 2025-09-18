# 🔐 auth Lambda 배포 가이드

## 📦 **패키지 생성**

```bash
# 패키지 생성
mkdir auth-lambda-package
cp lambda_simple_auth.py auth-lambda-package/

# 최소 requirements 생성
cat > auth-lambda-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
EOF

cd auth-lambda-package
pip install -r requirements.txt -t .
zip -r ../auth-lambda.zip .
cd ..
```

## 🚀 **Lambda 함수 생성**

```bash
aws lambda create-function \
    --function-name simple-auth \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_simple_auth.lambda_handler \
    --zip-file fileb://auth-lambda.zip \
    --timeout 30 \
    --memory-size 256 \
    --region us-west-1
```

## ⚙️ **환경변수 설정**

```bash
aws lambda update-function-configuration \
    --function-name simple-auth \
    --environment Variables='{
        "DYNAMODB_TABLE":"parasol-users"
    }' \
    --region us-west-1
```

## 🔧 **lambda_simple_auth.py 수정**

환경변수 사용하도록 코드 수정:

```python
import os

# 환경변수에서 테이블명 가져오기
USERS_TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'parasol-users')

dynamodb = boto3.resource('dynamodb')
users_table = dynamodb.Table(USERS_TABLE_NAME)
```

## 📋 **최종 환경변수**

| 변수명 | 값 | 설명 |
|-------|-----|------|
| `DYNAMODB_TABLE` | `parasol-users` | 사용자 정보 테이블 |

## ✅ **배포 확인**

```bash
# 함수 확인
aws lambda get-function --function-name simple-auth --region us-west-1

# 환경변수 확인
aws lambda get-function-configuration --function-name simple-auth --region us-west-1
```

## 🎯 **API Gateway 연결**

```bash
# /auth/register 경로에 연결
aws apigateway put-integration \
    --rest-api-id YOUR_API_ID \
    --resource-id AUTH_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:simple-auth/invocations"

# /auth/login 경로에도 동일하게 연결
```