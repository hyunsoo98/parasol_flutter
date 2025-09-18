# 📨 SQS 큐 생성 (AWS Console)

## 🎯 **3개 분석 타입별 큐 생성**

### **Step 1: SQS 콘솔 접속**
1. AWS Console → **SQS (Simple Queue Service)** 이동
2. 리전이 **us-west-1 (N. California)**인지 확인

### **Step 2: eye-tracking-queue 생성**
1. **Create queue** 버튼 클릭
2. **Type**: Standard 선택
3. **Name**: `eye-tracking-queue`
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds` (16분 - Lambda timeout보다 길게)
   - **Message retention period**: `14 days` (1209600 seconds)
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **Dead letter queue** (선택사항):
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `eye-tracking-dlq`
   - **Maximum receives**: `3`
6. **Create queue** 클릭

### **Step 3: finger-tapping-queue 생성**
1. **Create queue** 버튼 클릭
2. **Type**: Standard 선택
3. **Name**: `finger-tapping-queue`
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds`
   - **Message retention period**: `14 days`
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `finger-tapping-dlq`
   - **Maximum receives**: `3`
6. **Create queue** 클릭

### **Step 4: voice-analysis-queue 생성**
1. **Create queue** 버튼 클릭
2. **Type**: Standard 선택
3. **Name**: `voice-analysis-queue`
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds`
   - **Message retention period**: `14 days`
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `voice-analysis-dlq`
   - **Maximum receives**: `3`
6. **Create queue** 클릭

## 📋 **생성된 큐 목록**

총 **6개** 큐가 생성됩니다:

### **메인 큐 (3개)**
1. `eye-tracking-queue`
2. `finger-tapping-queue`
3. `voice-analysis-queue`

### **Dead Letter 큐 (3개)**
1. `eye-tracking-dlq`
2. `finger-tapping-dlq`
3. `voice-analysis-dlq`

## 📊 **큐 URL 확인**

각 큐 생성 후 **Details** 탭에서 URL 확인:

```
https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue
https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue
https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue
```

이 URL들은 **unified-upload Lambda 환경변수**에서 사용됩니다!

## ⚙️ **설정 세부사항**

### **Visibility Timeout (960초)**
- Lambda 함수 최대 실행 시간(900초)보다 길게 설정
- 메시지 처리 중 다른 컨슈머가 같은 메시지를 받지 않도록 함

### **Message Retention (14일)**
- 처리되지 않은 메시지 보관 기간
- 충분한 시간으로 설정하여 시스템 장애시에도 메시지 유실 방지

### **Dead Letter Queue**
- 처리 실패한 메시지를 별도 보관
- **Maximum receives: 3** → 3번 실패하면 DLQ로 이동
- 디버깅과 에러 분석에 활용

## 🔍 **권한 설정 (자동)**

SQS 큐 생성시 AWS가 자동으로 처리하는 항목들:
- Lambda 함수에서 큐 읽기 권한
- 큐에 메시지 전송 권한
- DLQ 접근 권한

## 📱 **Lambda에서 사용할 ARN**

생성된 큐들의 ARN:
```
arn:aws:sqs:us-west-1:327784329358:eye-tracking-queue
arn:aws:sqs:us-west-1:327784329358:finger-tapping-queue
arn:aws:sqs:us-west-1:327784329358:voice-analysis-queue
```

**SQS 큐 생성 완료!** 📨