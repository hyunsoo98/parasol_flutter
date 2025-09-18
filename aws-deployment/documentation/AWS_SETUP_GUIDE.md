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
# Default region: us-west-1
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
- 버킷 이름: `seoul-ht-09` (이미 생성됨)
- 리전: `us-west-1` (캘리포니아)
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
3. 호출 URL 기록: `https://[api-id].execute-api.us-west-1.amazonaws.com/dev`

## 🚀 6단계: AWS Amplify 호스팅 설정

### 6.1 Amplify 앱 생성
1. [Amplify 콘솔](https://console.aws.amazon.com/amplify/) 접속
2. "새 앱" → "웹 앱 호스팅" 클릭
3. **소스 선택**: "빌드 아티팩트를 업로드하지 않고 배포" 선택
4. **앱 이름**: `parkinson-app` 입력
5. **환경 이름**: `main` (기본값)
6. "앱 만들기" 클릭

### 6.2 Flutter 웹 빌드 및 배포
```bash
# 1. Flutter 웹 빌드
flutter build web

# 2. build/web 폴더 확인
ls build/web

# 3. build/web 폴더 전체를 ZIP으로 압축
# Windows: build/web 폴더 내의 모든 파일을 선택하여 압축 (폴더 자체가 아님)
# 압축 파일명: parkinson-web.zip
```

### 6.3 수동 배포
1. Amplify 앱 → **호스팅** → **배포** 탭
2. "아티팩트 끌어서 놓기" 영역에 `parkinson-web.zip` 업로드
3. 배포 완료까지 2-3분 대기
4. **앱 URL** 확인 및 기록: `https://main.d27qlm0640fgud.amplifyapp.com`

### 6.4 환경 변수 설정
1. Amplify 앱 → **호스팅** → **환경 변수** 탭
2. "변수 관리" 클릭
3. 다음 환경 변수 추가:

**현재 Amplify 앱 ID: `d27qlm0640fgud`**

| 변수 | 값 | 브랜치 | 설명 |
|------|----|----|------|
| `API_ENDPOINT` | `https://[your-api-gateway-id].execute-api.us-west-1.amazonaws.com/dev` | `main` | API Gateway 배포 후 실제 ID로 교체 |
| `S3_BUCKET` | `seoul-ht-09` | `main` | 실제 S3 버킷명 |
| `REGION` | `us-west-1` | `main` | 캘리포니아 리전 (AWS_ 접두사 제거) |

**예시 실제 값:**
- API_ENDPOINT: `https://abc123xyz9.execute-api.us-west-1.amazonaws.com/dev`
- S3_BUCKET: `seoul-ht-09`

4. "저장" 클릭
5. **재배포 필수**: "작업" → "앱 재배포" 클릭 (환경 변수 적용을 위해)

### 6.5 빌드 설정 (향후 자동 배포용)
향후 Git 연동 시를 위한 빌드 설정:
1. **앱 설정** → **빌드 설정** 탭
2. **amplify.yml** 설정:
```yaml
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - flutter pub get
    build:
      commands:
        - flutter build web --release
  artifacts:
    baseDirectory: build/web
    files:
      - '**/*'
  cache:
    paths:
      - .pub-cache/**/*
```

## ⚙️ 7단계: Flutter 앱 설정

### 7.1 Flutter 웹 빌드 오류 해결

**Amplify 의존성 제거 (이미 완료):**
- `main.dart`에서 Amplify 관련 import 제거
- `CustomAuthProvider`로 이름 충돌 해결
- HTTP 기반 API 서비스로 변경

**웹 빌드 전 필수 확인사항:**
```bash
# 1. pubspec.yaml에서 web 지원 패키지 확인
flutter pub get

# 2. 웹 빌드 테스트
flutter build web --web-renderer html

# 3. 빌드 오류 없는지 확인
flutter analyze
```

### 7.2 API 엔드포인트 설정 (자동 완료)
`lib/config/aws_config.dart` 이미 생성됨:
- 웹/모바일 환경 변수 자동 감지
- Amplify 환경 변수와 호환
- API 엔드포인트 자동 구성

### 7.3 실제 값으로 설정 변경
배포 후 `lib/config/aws_config.dart`에서 실제 값으로 교체:
```dart
// 실제 API Gateway ID로 교체
static const String apiEndpoint = 'https://abc123def4.execute-api.us-west-1.amazonaws.com/dev';

// 실제 S3 버킷명으로 교체  
static const String s3Bucket = 'parkinson-app-storage-20241210';
```

### 7.4 웹 빌드 최종 확인
```bash
# 모든 오류 해결 후 최종 빌드
flutter clean
flutter pub get  
flutter build web --release

# 빌드 성공 확인
ls build/web/
```

**문제 발생 시 해결책:**
- `Type 'PromiseJsImpl' not found` → Firebase 의존성 제거로 해결됨
- `Method not found: 'dartify'` → Firebase 의존성 제거로 해결됨
- `AuthProvider import conflict` → `CustomAuthProvider`로 해결됨
- `Amplify 빌드 오류` → pubspec.yaml에서 모든 Amplify 패키지 제거함
- `Firebase 빌드 오류` → Firebase 패키지도 제거, 임시 인증으로 대체

**제거된 의존성들:**
- `amplify_flutter`, `amplify_auth_cognito`, `amplify_storage_s3`, `amplify_api`, `amplify_datastore`
- `firebase_core`, `firebase_auth`, `google_sign_in`

**대체 구현:**
- AWS HTTP API 직접 호출로 Amplify 대체
- 임시 인증 시스템으로 Firebase Auth 대체
- 환경 변수 기반 설정으로 동적 구성

## 🧪 8단계: 테스트

### 8.1 API 테스트
```bash
# API 엔드포인트 테스트
curl -X GET https://[api-id].execute-api.us-west-1.amazonaws.com/dev/health

# 파일 업로드 테스트
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/upload \
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
  static const String baseUrl = 'https://[api-id].execute-api.us-west-1.amazonaws.com/dev';
  
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