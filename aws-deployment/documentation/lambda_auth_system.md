# 🔐 간단한 자체 회원가입 시스템

## 🎯 **인증 시스템 설계**

### **Firebase 제거 → 간단한 자체 회원가입**
- ❌ Firebase Auth 제거
- ✅ 이메일/폰번호 + 비밀번호
- ✅ DynamoDB에 사용자 정보 저장
- ✅ 간단한 세션 토큰

## 🗃️ **DynamoDB 테이블 구조**

### **parasol-users 테이블 (기존 활용)**
```json
{
  "userId": "user_20240917_abc123",      // Primary Key
  "email": "user@example.com",           // 이메일 (로그인 ID)
  "phone": "+821012345678",              // 전화번호 (선택)
  "name": "홍길동",                      // 이름
  "passwordHash": "hashed_password",     // SHA256 해시된 비밀번호
  "status": "active",                    // active | blocked
  "timestamp": 1694956800,               // Sort Key
  "createdAt": "2024-09-17T10:30:00Z",
  "lastLoginAt": "2024-09-17T11:00:00Z"
}
```

### **sessions 테이블 (새로 생성)**
```json
{
  "sessionId": "session_20240917_xyz789", // Primary Key
  "userId": "user_20240917_abc123",
  "accessToken": "jwt_token_here",
  "refreshToken": "refresh_token_here",
  "expiresAt": "2024-09-17T12:00:00Z",
  "createdAt": "2024-09-17T10:30:00Z",
  "lastUsedAt": "2024-09-17T11:00:00Z",
  "deviceInfo": "Flutter App v1.0"
}
```

## 🔧 **Lambda 함수 추가**

### **1. auth-send-sms**
```python
import boto3
import json
import random
from datetime import datetime, timedelta

def lambda_handler(event, context):
    phone_number = event['body']['phoneNumber']

    # 6자리 인증번호 생성
    verification_code = str(random.randint(100000, 999999))
    expires_at = (datetime.utcnow() + timedelta(minutes=5)).isoformat()

    # DynamoDB에 사용자 정보 저장/업데이트
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('parasol-users')

    user_id = f"user_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    table.put_item(Item={
        'userId': user_id,
        'phoneNumber': phone_number,
        'timestamp': int(datetime.utcnow().timestamp()),
        'status': 'pending',
        'verificationCode': verification_code,
        'codeExpiresAt': expires_at,
        'createdAt': datetime.utcnow().isoformat()
    })

    # SMS 발송 (AWS SNS)
    sns = boto3.client('sns')
    message = f"[Parasol] 인증번호: {verification_code}"

    sns.publish(
        PhoneNumber=phone_number,
        Message=message
    )

    return {
        'statusCode': 200,
        'body': json.dumps({
            'userId': user_id,
            'message': '인증번호가 발송되었습니다.'
        })
    }
```

### **2. auth-verify-sms**
```python
import boto3
import json
import jwt
import uuid
from datetime import datetime, timedelta

def lambda_handler(event, context):
    body = json.loads(event['body'])
    user_id = body['userId']
    verification_code = body['verificationCode']

    dynamodb = boto3.resource('dynamodb')
    users_table = dynamodb.Table('parasol-users')
    sessions_table = dynamodb.Table('sessions')

    # 사용자 정보 조회
    response = users_table.get_item(Key={'userId': user_id})

    if 'Item' not in response:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': '사용자를 찾을 수 없습니다.'})
        }

    user = response['Item']

    # 인증번호 확인
    if user['verificationCode'] != verification_code:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': '인증번호가 일치하지 않습니다.'})
        }

    # 만료 시간 확인
    if datetime.utcnow() > datetime.fromisoformat(user['codeExpiresAt']):
        return {
            'statusCode': 400,
            'body': json.dumps({'error': '인증번호가 만료되었습니다.'})
        }

    # JWT 토큰 생성
    access_token = jwt.encode({
        'userId': user_id,
        'phoneNumber': user['phoneNumber'],
        'exp': datetime.utcnow() + timedelta(hours=24)
    }, 'your-secret-key', algorithm='HS256')

    refresh_token = str(uuid.uuid4())
    session_id = f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    # 사용자 상태 업데이트
    users_table.update_item(
        Key={'userId': user_id},
        UpdateExpression='SET #status = :status, lastLoginAt = :login_time',
        ExpressionAttributeNames={'#status': 'status'},
        ExpressionAttributeValues={
            ':status': 'verified',
            ':login_time': datetime.utcnow().isoformat()
        }
    )

    # 세션 생성
    sessions_table.put_item(Item={
        'sessionId': session_id,
        'userId': user_id,
        'accessToken': access_token,
        'refreshToken': refresh_token,
        'expiresAt': (datetime.utcnow() + timedelta(hours=24)).isoformat(),
        'createdAt': datetime.utcnow().isoformat(),
        'lastUsedAt': datetime.utcnow().isoformat()
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'accessToken': access_token,
            'refreshToken': refresh_token,
            'userId': user_id,
            'sessionId': session_id
        })
    }
```

### **3. auth-validate-token**
```python
import boto3
import json
import jwt
from datetime import datetime

def lambda_handler(event, context):
    # API Gateway Authorizer로 사용
    token = event['authorizationToken'].replace('Bearer ', '')

    try:
        payload = jwt.decode(token, 'your-secret-key', algorithms=['HS256'])
        user_id = payload['userId']

        # 세션 확인
        dynamodb = boto3.resource('dynamodb')
        sessions_table = dynamodb.Table('sessions')

        response = sessions_table.scan(
            FilterExpression='userId = :uid AND accessToken = :token',
            ExpressionAttributeValues={
                ':uid': user_id,
                ':token': token
            }
        )

        if not response['Items']:
            raise Exception('Invalid session')

        # 정책 반환 (API Gateway Authorizer 응답)
        return {
            'principalId': user_id,
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [
                    {
                        'Action': 'execute-api:Invoke',
                        'Effect': 'Allow',
                        'Resource': event['methodArn']
                    }
                ]
            },
            'context': {
                'userId': user_id
            }
        }

    except Exception as e:
        raise Exception('Unauthorized')
```

## 🎨 **Flutter 앱 변경사항**

### **인증 서비스 클래스**
```dart
class AuthService {
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // SMS 인증번호 요청
  Future<String> sendSMSCode(String phoneNumber) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/send-sms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber}),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return result['userId'];
    } else {
      throw Exception('SMS 발송 실패');
    }
  }

  // 인증번호 확인
  Future<AuthResult> verifySMSCode(String userId, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify-sms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'verificationCode': code,
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);

      // 토큰 저장
      await _saveTokens(
        result['accessToken'],
        result['refreshToken'],
        result['userId'],
      );

      return AuthResult(
        accessToken: result['accessToken'],
        userId: result['userId'],
      );
    } else {
      throw Exception('인증 실패');
    }
  }

  // 토큰 저장
  Future<void> _saveTokens(String accessToken, String refreshToken, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', accessToken);
    await prefs.setString('refreshToken', refreshToken);
    await prefs.setString('userId', userId);
  }

  // 저장된 토큰 가져오기
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('accessToken');
  }

  // 현재 사용자 ID
  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }
}

class AuthResult {
  final String accessToken;
  final String userId;

  AuthResult({required this.accessToken, required this.userId});
}
```

## 🚀 **API Gateway 인증 설정**

### **Authorizer 추가**
```bash
# Lambda Authorizer 생성
aws apigateway create-authorizer \
    --rest-api-id YOUR_API_ID \
    --name "ParasolAuthorizer" \
    --type TOKEN \
    --authorizer-uri "arn:aws:apigateway:us-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-1:327784329358:function:auth-validate-token/invocations" \
    --identity-source "method.request.header.Authorization" \
    --region us-west-1
```

## 📊 **업데이트된 API 엔드포인트**

```
/auth/send-sms        (POST) - SMS 인증번호 발송
/auth/verify-sms      (POST) - 인증번호 확인 & 로그인
/api/v1/upload        (POST) - 분석 업로드 (인증 필요)
/api/v1/status/*      (GET)  - 상태 조회 (인증 필요)
/api/v1/diagnosis/*   (POST/GET) - 종합 진단 (인증 필요)
```

## 🔧 **sessions 테이블 생성**

```json
{
  "TableName": "sessions",
  "AttributeDefinitions": [
    {
      "AttributeName": "sessionId",
      "AttributeType": "S"
    },
    {
      "AttributeName": "userId",
      "AttributeType": "S"
    }
  ],
  "KeySchema": [
    {
      "AttributeName": "sessionId",
      "KeyType": "HASH"
    }
  ],
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "user-sessions-index",
      "KeySchema": [
        {
          "AttributeName": "userId",
          "KeyType": "HASH"
        }
      ],
      "Projection": {
        "ProjectionType": "ALL"
      }
    }
  ],
  "BillingMode": "PAY_PER_REQUEST"
}
```

이제 **완전한 자체 인증 시스템**으로 Firebase 없이 운영할 수 있습니다! 🎯