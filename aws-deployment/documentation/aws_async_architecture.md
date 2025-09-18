# 🚀 AWS 순수 비동기 Eye Tracking 아키텍처

## 📋 아키텍처 구성

### 🔄 데이터 플로우
```
1. Flutter → API Gateway → Upload Lambda → S3 + SQS
2. SQS → Process Lambda → DynamoDB (결과 저장)
3. Flutter → API Gateway → Status Lambda → DynamoDB (상태 조회)
```

### 🛠️ AWS 서비스 구성
- **API Gateway**: REST API 엔드포인트
- **Lambda**: 3개 함수 (Upload, Process, Status)
- **S3**: 비디오 파일 저장
- **SQS**: 비동기 메시지 큐
- **DynamoDB**: 분석 결과 및 상태 저장

## 📁 Lambda 함수 구조

### 1) lambda_upload.py - 파일 업로드 및 큐 전송
### 2) lambda_process.py - 실제 eye tracking 분석
### 3) lambda_status.py - 상태 및 결과 조회

## 🔧 환경 변수 설정
```
S3_BUCKET=eye-tracking-videos
SQS_QUEUE_URL=https://sqs.region.amazonaws.com/account/eye-tracking-queue
DYNAMODB_TABLE=eye-tracking-results
AWS_REGION=ap-northeast-2
```

## 📊 DynamoDB 테이블 스키마
```
Table: eye-tracking-results
Primary Key: analysis_id (String)
Attributes:
- status (String): processing | completed | failed
- user_id (String)
- timestamp (Number)
- s3_key (String)
- result (Map): 분석 결과 JSON
- error (String): 오류 메시지 (실패시)
```

## 🎯 주요 특징
- ✅ 15분까지 긴 처리 시간 가능
- ✅ 대용량 파일 S3 업로드
- ✅ 완전한 AWS 생태계
- ✅ 자동 스케일링
- ✅ 비용 효율적 (처리시간만 과금)