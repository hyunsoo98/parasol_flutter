# Parkinson App - AWS 제한된 권한 설정 가이드

## 📋 준비 사항
- 제한된 AWS 계정 (액세스 키 발급 권한 없음)
- Node.js 및 npm 설치
- AWS CLI 설치
- AWS 관리자로부터 받은 제한된 IAM 사용자 정보

## ⚠️ 제약 사항
- **Cognito 사용 불가**: 인증 서비스 없이 구성
- **액세스 키 발급 불가**: 관리자가 제공한 제한된 권한만 사용
- **AWS Amplify CLI 사용 제한**: 수동 AWS 콘솔 설정 필요

## 🏗️ 아키텍처 구성

```
Flutter App → API Gateway → Lambda → DynamoDB
              ↓
              S3 (파일 저장)
              ↓  
         AWS Amplify (호스팅)
```

## 🔧 1단계: AWS 콘솔 수동 설정

### 1.1 관리자에게 요청할 권한
관리자에게 다음 서비스에 대한 권한을 요청하세요:
- **API Gateway**: API 생성, 배포
- **Lambda**: 함수 생성, 실행
- **DynamoDB**: 테이블 생성, 읽기/쓰기
- **S3**: 버킷 생성, 객체 업로드/다운로드
- **AWS Amplify**: 앱 호스팅

### 1.2 AWS CLI 설정 (관리자 제공 자격증명)
```bash
aws configure
# Access Key ID: [관리자 제공]
# Secret Access Key: [관리자 제공]
# Default region: ap-northeast-2
# Default output format: json
```

## 📊 2단계: DynamoDB 테이블 생성

### 2.1 AWS 콘솔에서 DynamoDB 테이블 생성
1. [DynamoDB 콘솔](https://console.aws.amazon.com/dynamodb/) 접속
2. "테이블 생성" 클릭

**테이블 1: 사용자 데이터**
- 테이블 이름: `parkinson-users`
- 파티션 키: `userId` (String)
- 정렬 키: `timestamp` (Number)

**테이블 2: 분석 결과**
- 테이블 이름: `parkinson-analysis`
- 파티션 키: `analysisId` (String)
- 정렬 키: `testType` (String)

**테이블 3: 파일 메타데이터**
- 테이블 이름: `parkinson-files`
- 파티션 키: `fileId` (String)

## 📦 3단계: S3 버킷 생성

### 3.1 AWS 콘솔에서 S3 버킷 생성
1. [S3 콘솔](https://s3.console.aws.amazon.com/s3/) 접속
2. "버킷 만들기" 클릭

**버킷 설정:**
- 버킷 이름: `parkinson-app-storage-[고유번호]`
- 리전: `ap-northeast-2` (서울)
- 버킷 버전 관리: 비활성화
- 퍼블릭 액세스 차단: 모든 퍼블릭 액세스 차단

**폴더 구조:**
```
parkinson-app-storage/
├── videos/          # 업로드된 비디오 파일
├── results/         # 분석 결과 CSV 파일
└── temp/           # 임시 처리 파일
```

### 3.2 CORS 설정
S3 버킷 → 권한 → CORS 설정에서 다음을 추가:
```json
[
    {
        "AllowedHeaders": ["*"],
        "AllowedMethods": ["GET", "POST", "PUT"],
        "AllowedOrigins": ["*"],
        "ExposeHeaders": ["ETag"]
    }
]
```

## ⚡ 4단계: Lambda 함수 생성

### 4.1 시선 추적 분석 함수
1. [Lambda 콘솔](https://console.aws.amazon.com/lambda/) 접속
2. "함수 생성" 클릭

**함수 1: 시선 추적 분석**
- 함수 이름: `parkinson-eye-tracking`
- 런타임: `Python 3.9`
- 아키텍처: `x86_64`

**환경 변수:**
```
S3_BUCKET=parkinson-app-storage-[고유번호]
DYNAMODB_TABLE=parkinson-analysis
```

**IAM 역할 권한:**
- AWSLambdaBasicExecutionRole
- S3 읽기/쓰기 권한
- DynamoDB 읽기/쓰기 권한

### 4.2 음성 분석 함수
**함수 2: 음성 분석**
- 함수 이름: `parkinson-voice-analysis`
- 런타임: `Python 3.9`
- 제한 시간: 5분

### 4.3 손가락 태핑 분석 함수
**함수 3: 손가락 태핑 분석**
- 함수 이름: `parkinson-finger-tapping`
- 런타임: `Python 3.9`
- 메모리: 512 MB

### 4.4 파일 업로드 함수
**함수 4: 파일 업로드 처리**
- 함수 이름: `parkinson-file-upload`
- 런타임: `Python 3.9`
- 메모리: 256 MB
- 제한 시간: 30초

**역할:**
- S3 Pre-signed URL 생성
- 파일 메타데이터 DynamoDB 저장
- 업로드 완료 후 검증

## 🌐 5단계: API Gateway 설정

### 5.1 REST API 생성
1. [API Gateway 콘솔](https://console.aws.amazon.com/apigateway/) 접속
2. "API 생성" → "REST API" 선택
3. API 이름: `parkinson-api`

### 5.2 리소스 및 메서드 생성

**API 구조:**
```
/api/v1/
├── /upload          # POST: 파일 업로드
├── /analyze         # POST: 분석 시작
│   ├── /eye-tracking
│   ├── /voice
│   └── /finger-tapping
├── /results         # GET: 결과 조회
└── /health         # GET: 헬스체크
```

**각 메서드와 Lambda 함수 매핑:**
- `/upload` POST → `parkinson-file-upload`
- `/analyze/eye-tracking` POST → `parkinson-eye-tracking`  
- `/analyze/voice` POST → `parkinson-voice-analysis`
- `/analyze/finger-tapping` POST → `parkinson-finger-tapping`
- `/results` GET → `parkinson-eye-tracking` (결과 조회용)
- `/health` GET → `parkinson-file-upload` (간단한 헬스체크)

**메서드 설정 방법:**
1. 리소스 생성 → 메서드 생성
2. 통합 유형: Lambda 함수
3. Lambda 프록시 통합 사용: 체크
4. 해당 Lambda 함수 선택

### 5.3 CORS 활성화
**CORS 설정이 필요한 모든 리소스:**
- `/upload` (POST)
- `/analyze` (부모 리소스)
- `/analyze/eye-tracking` (POST)
- `/analyze/voice` (POST)
- `/analyze/finger-tapping` (POST)
- `/results` (GET)
- `/health` (GET)

**설정 방법:** 각 리소스에서 "작업" → "CORS 활성화" 클릭

**CORS 설정값:**
- **Access-Control-Allow-Origin**: `*` (또는 특정 도메인)
- **Access-Control-Allow-Headers**: `Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token`
- **Access-Control-Allow-Methods**: `GET,POST,OPTIONS`

**게이트웨이 응답 설정 (중요!):**
1. 각 메서드 → "메서드 응답" 탭
2. **4XX 응답 추가**: 
   - 응답 코드: `400`, `401`, `403`, `404`
   - 응답 헤더: `Access-Control-Allow-Origin` 추가
3. **5XX 응답 추가**:
   - 응답 코드: `500`, `502`, `503`
   - 응답 헤더: `Access-Control-Allow-Origin` 추가
4. "통합 응답" 탭에서 각 응답에 헤더 값 `'*'` 설정

### 5.4 API 배포
1. "작업" → "API 배포"
2. 배포 스테이지: `dev`
3. 호출 URL 기록: `https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev`

## 🚀 6단계: AWS Amplify 호스팅 설정

### 6.1 Amplify 앱 생성
1. [Amplify 콘솔](https://console.aws.amazon.com/amplify/) 접속
2. "새 앱" → "웹 앱 호스팅"
3. 소스: "빌드 아티팩트 업로드" 선택

### 6.2 Flutter 웹 빌드
```bash
# Flutter 웹 빌드
flutter build web

# build/web 폴더를 ZIP으로 압축
# Amplify에 업로드
```

### 6.3 환경 변수 설정
Amplify 앱 → 환경 변수에서 설정:
```
API_ENDPOINT=https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev
S3_BUCKET=parkinson-app-storage-[고유번호]
AWS_REGION=ap-northeast-2
```

## ⚙️ 7단계: Flutter 앱 설정

### 7.1 API 엔드포인트 설정
`lib/config/aws_config.dart` 생성:
```dart
class AWSConfig {
  static const String apiEndpoint = 'https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev';
  static const String s3Bucket = 'parkinson-app-storage-[고유번호]';
  static const String region = 'ap-northeast-2';
}
```

### 7.2 HTTP 클라이언트 설정
`lib/services/api_service.dart`에서 API Gateway 연동

### 7.3 파일 업로드 설정
S3 직접 업로드 또는 API Gateway를 통한 업로드 구성

## 🧪 8단계: 테스트

### 8.1 API 테스트
```bash
# API 엔드포인트 테스트
curl -X GET https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev/health

# 파일 업로드 테스트
curl -X POST https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev/upload \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.mp4", "fileType": "video"}'
```

### 8.2 Flutter 앱 테스트
```bash
flutter pub get
flutter build web
flutter run -d chrome
```

## 📊 9단계: 모니터링 및 관리

### 9.1 CloudWatch 로그 확인
- Lambda 함수 로그 모니터링
- API Gateway 액세스 로그 확인
- 에러 추적 및 디버깅

### 9.2 비용 모니터링
**예상 비용 (월간):**
- **S3**: $5-15 (스토리지 + 요청)
- **Lambda**: $10-30 (실행 시간 기준)
- **API Gateway**: $5-20 (API 호출)
- **DynamoDB**: $5-15 (읽기/쓰기)
- **Amplify**: $1-5 (호스팅)
- **총합**: $26-85/월

### 9.3 보안 설정
1. **API Key 설정**: API Gateway에서 API 키 생성 및 사용량 계획 설정
2. **Rate Limiting**: API 호출 제한 설정
3. **Input Validation**: Lambda 함수에서 입력 데이터 검증

## 🔧 10단계: 코드 예제

### 10.1 Lambda 함수 예제 (Python)
```python
import json
import boto3
import os

def lambda_handler(event, context):
    # S3 및 DynamoDB 클라이언트 초기화
    s3 = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')
    
    # 환경 변수에서 설정 읽기
    bucket_name = os.environ['S3_BUCKET']
    table_name = os.environ['DYNAMODB_TABLE']
    
    # 비즈니스 로직 처리
    try:
        # 파일 처리 및 분석 로직
        result = process_analysis(event)
        
        # 결과를 DynamoDB에 저장
        table = dynamodb.Table(table_name)
        table.put_item(Item=result)
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps(result)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

### 10.2 Flutter API 클라이언트 예제
```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class APIService {
  static const String baseUrl = 'https://[api-id].execute-api.ap-northeast-2.amazonaws.com/dev';
  
  static Future<Map<String, dynamic>> startAnalysis(String fileUrl, String testType) async {
    final response = await http.post(
      Uri.parse('$baseUrl/analyze/$testType'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fileUrl': fileUrl}),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('분석 시작 실패');
    }
  }
}
```

이제 제한된 권한 환경에서 Cognito 없이 AWS 서비스들을 활용한 파킨슨병 앱을 구축할 수 있습니다!