# AWS 환경 설정 통합 가이드 (수정된 버전)

## 🎯 목표
API 아키텍처 문서 기준으로 모든 AWS 리소스를 정확하게 설정합니다.

## 📂 정정된 S3 버킷 구조

```
seoul-ht-09/
├── eye-tracking/
│   ├── raw/
│   │   └── {analysis_id}/
│   │       └── video.mp4
│   ├── processed/
│   │   └── {analysis_id}/
│   │       └── features.json
│   └── results/
│       └── {analysis_id}/
│           └── analysis.json
├── finger-tapping/
│   ├── raw/
│   │   └── {analysis_id}/
│   │       └── video.mp4
│   ├── processed/
│   │   └── {analysis_id}/
│   │       └── landmarks.json
│   └── results/
│       └── {analysis_id}/
│           └── analysis.json
└── voice-analysis/
    ├── raw/
    │   └── {analysis_id}/
    │       └── audio.wav
    ├── processed/
    │   └── {analysis_id}/
    │       └── features.json
    └── results/
        └── {analysis_id}/
            └── analysis.json
```

## 🔧 정정된 통합 환경 변수 정의

### Core Infrastructure
```bash
# AWS 기본 설정
AWS_REGION=us-west-1
AWS_ACCOUNT_ID=327784329358

# S3 설정
S3_BUCKET=seoul-ht-09
S3_EYE_TRACKING_PREFIX=eye-tracking
S3_FINGER_TAPPING_PREFIX=finger-tapping
S3_VOICE_ANALYSIS_PREFIX=voice-analysis

# API Gateway
API_GATEWAY_BASE_URL=https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod
```

### SQS Queue URLs
```bash
# SQS 큐 설정
EYE_TRACKING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue.fifo
FINGER_TAPPING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue.fifo
VOICE_ANALYSIS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue.fifo

# 큐 이름 (리소스 생성용)
EYE_TRACKING_QUEUE_NAME=eye-tracking-queue.fifo
FINGER_TAPPING_QUEUE_NAME=finger-tapping-queue.fifo
VOICE_ANALYSIS_QUEUE_NAME=voice-analysis-queue.fifo
```

### DynamoDB Tables
```bash
# 메인 분석 테이블
ANALYSES_TABLE=analyses

# 종합 진단 세션 테이블
DIAGNOSIS_SESSIONS_TABLE=diagnosis_sessions

# 인덱스 이름
USER_ID_INDEX=user-id-index
CREATED_AT_INDEX=created-at-index
```

### Lambda Function Names
```bash
# 함수 이름 (API 문서 기준)
LAMBDA_UNIFIED_UPLOAD=unified-upload
LAMBDA_UNIFIED_STATUS=unified-status
LAMBDA_COMPREHENSIVE_DIAGNOSIS=comprehensive-diagnosis
LAMBDA_EYE_TRACKING_PROCESS=eye-tracking-process
LAMBDA_FINGER_TAPPING_PROCESS=finger-tapping-process
LAMBDA_VOICE_ANALYSIS_PROCESS=voice-analysis-process
```

## 📋 Lambda 함수별 환경 변수 설정

### 1. Lambda Unified Upload (`unified-upload`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09
S3_EYE_TRACKING_PREFIX=eye-tracking
S3_FINGER_TAPPING_PREFIX=finger-tapping
S3_VOICE_ANALYSIS_PREFIX=voice-analysis

# SQS 큐
EYE_TRACKING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue.fifo
FINGER_TAPPING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue.fifo
VOICE_ANALYSIS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue.fifo

# DynamoDB 테이블
ANALYSES_TABLE=analyses

# 기타 설정
MAX_FILE_SIZE_MB=100
UPLOAD_TIMEOUT_SECONDS=300
```

### 2. Lambda Unified Status (`unified-status`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09
S3_EYE_TRACKING_PREFIX=eye-tracking
S3_FINGER_TAPPING_PREFIX=finger-tapping
S3_VOICE_ANALYSIS_PREFIX=voice-analysis

# DynamoDB 테이블
ANALYSES_TABLE=analyses
DIAGNOSIS_SESSIONS_TABLE=diagnosis_sessions

# Presigned URL 설정
PRESIGNED_URL_EXPIRATION_SECONDS=3600
MAX_HISTORY_RECORDS=100
```

### 3. Lambda Comprehensive Diagnosis (`comprehensive-diagnosis`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09

# DynamoDB 테이블
ANALYSES_TABLE=analyses
DIAGNOSIS_SESSIONS_TABLE=diagnosis_sessions

# API Gateway (내부 호출용)
API_GATEWAY_BASE_URL=https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod

# 진단 설정
REQUIRED_ANALYSES=eye-tracking,finger-tapping,voice-analysis
SESSION_TIMEOUT_HOURS=24
```

### 4. Lambda Eye Tracking Process (`eye-tracking-process`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09
S3_EYE_TRACKING_PREFIX=eye-tracking

# DynamoDB 테이블
ANALYSES_TABLE=analyses

# SQS 큐
EYE_TRACKING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue.fifo

# 분석 설정
MODEL_PATH=/opt/models/eye_tracking_model.joblib
MAX_PROCESSING_TIME_SECONDS=600
DEFAULT_THRESHOLD=0.06
```

### 5. Lambda Finger Tapping Process (`finger-tapping-process`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09
S3_FINGER_TAPPING_PREFIX=finger-tapping

# DynamoDB 테이블
ANALYSES_TABLE=analyses

# SQS 큐
FINGER_TAPPING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue.fifo

# 분석 설정
MODEL_PATH=/opt/models/best_pipeline_recall_AdaBoost.joblib
FEATURE_EXTRACTION_MODULE=/opt/feature_extraction
MAX_PROCESSING_TIME_SECONDS=600
DEFAULT_THRESHOLD=0.5
```

### 6. Lambda Voice Analysis Process (`voice-analysis-process`)
```bash
# 필수 환경 변수
S3_BUCKET=seoul-ht-09
S3_VOICE_ANALYSIS_PREFIX=voice-analysis

# DynamoDB 테이블
ANALYSES_TABLE=analyses

# SQS 큐
VOICE_ANALYSIS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue.fifo

# 분석 설정
MODEL_PATH=/opt/models/voice_analysis_model.pth
PYTORCH_MODEL_PATH=/opt/models/pytorch_voice_model.pth
AUDIO_SAMPLE_RATE=16000
MAX_AUDIO_DURATION_SECONDS=300
MAX_PROCESSING_TIME_SECONDS=900
```

## 🌐 Flutter 클라이언트 설정

### lib/config/aws_config.dart
```dart
class AwsConfig {
  // Core Infrastructure
  static const String awsRegion = 'us-west-1';
  static const String awsAccountId = '327784329358';

  // S3 설정
  static const String s3Bucket = 'seoul-ht-09';
  static const String s3EyeTrackingPrefix = 'eye-tracking';
  static const String s3FingerTappingPrefix = 'finger-tapping';
  static const String s3VoiceAnalysisPrefix = 'voice-analysis';

  // API Gateway
  static const String apiGatewayBaseUrl = 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';

  // DynamoDB 테이블
  static const String analysesTable = 'analyses';
  static const String diagnosisSessionsTable = 'diagnosis_sessions';

  // 분석 타입
  static const String eyeTrackingType = 'eye-tracking';
  static const String fingerTappingType = 'finger-tapping';
  static const String voiceAnalysisType = 'voice-analysis';

  // API 엔드포인트
  static const String uploadEndpoint = '/api/v1/upload';
  static const String statusEndpoint = '/api/v1/status';
  static const String resultsEndpoint = '/api/v1/results';
  static const String diagnosisStartEndpoint = '/api/v1/diagnosis/start';
  static const String diagnosisEndpoint = '/api/v1/diagnosis';
  static const String healthEndpoint = '/api/v1/health';
}
```

## 🔗 DynamoDB 테이블 스키마

### analyses 테이블
```json
{
  "TableName": "analyses",
  "KeySchema": [
    {
      "AttributeName": "analysis_id",
      "KeyType": "HASH"
    }
  ],
  "AttributeDefinitions": [
    {
      "AttributeName": "analysis_id",
      "AttributeType": "S"
    },
    {
      "AttributeName": "user_id",
      "AttributeType": "S"
    },
    {
      "AttributeName": "created_at",
      "AttributeType": "S"
    }
  ],
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "user-id-index",
      "KeySchema": [
        {
          "AttributeName": "user_id",
          "KeyType": "HASH"
        },
        {
          "AttributeName": "created_at",
          "KeyType": "RANGE"
        }
      ],
      "Projection": {
        "ProjectionType": "ALL"
      }
    }
  ]
}
```

### diagnosis_sessions 테이블
```json
{
  "TableName": "diagnosis_sessions",
  "KeySchema": [
    {
      "AttributeName": "session_id",
      "KeyType": "HASH"
    }
  ],
  "AttributeDefinitions": [
    {
      "AttributeName": "session_id",
      "AttributeType": "S"
    },
    {
      "AttributeName": "user_id",
      "AttributeType": "S"
    },
    {
      "AttributeName": "created_at",
      "AttributeType": "S"
    }
  ],
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "user-id-index",
      "KeySchema": [
        {
          "AttributeName": "user_id",
          "KeyType": "HASH"
        },
        {
          "AttributeName": "created_at",
          "KeyType": "RANGE"
        }
      ],
      "Projection": {
        "ProjectionType": "ALL"
      }
    }
  ]
}
```

## 🚀 배포 순서

1. **DynamoDB 테이블 생성**: `analyses`, `diagnosis_sessions`
2. **SQS 큐 생성**: 3개의 FIFO 큐
3. **S3 버킷 구조 생성**: 분석 타입별 디렉토리
4. **Lambda 함수 환경변수 업데이트**: 6개 함수
5. **Flutter 앱 설정 업데이트**: 새로운 AwsConfig 적용
6. **API Gateway 연결 확인**: 엔드포인트 매핑 검증

이제 API 아키텍처 문서와 완전히 일치하는 구조로 정정되었습니다! 🎯