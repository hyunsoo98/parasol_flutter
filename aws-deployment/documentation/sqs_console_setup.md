# 📨 SQS 큐 생성 가이드 (AWS Console)

## 🤔 **FIFO vs Standard 큐 선택**

### **🔄 FIFO 큐 (권장 - 의료 데이터 특성)**
- **장점**:
  - 메시지 순서 보장 ✅
  - 정확히 한 번 전송 보장 ✅
  - 중복 제거 기능 ✅
  - 의료 데이터 무결성 보장
- **단점**:
  - 제한된 처리량 (300 TPS) - 개인 앱으로는 충분
  - 약간 높은 비용
  - MessageGroupId 설정 필요
- **🎯 Parkinson 분석에 적합한 이유**:
  - 환자별 시간순 분석 결과 중요
  - 동일 비디오 중복 분석 방지
  - 치료 전후 비교를 위한 순서 보장

### **⚡ Standard 큐 (대량 처리용)**
- **장점**:
  - 무제한 처리량 (TPS)
  - 낮은 비용
  - 단순한 설정
- **단점**:
  - 메시지 순서 보장 없음 ❌
  - 중복 전송 가능성 있음 ❌
- **적합한 경우**:
  - 대규모 병원 시스템
  - 순서가 중요하지 않은 bulk 분석
  - 최고 성능이 필요한 경우

---

## 🔄 **FIFO 큐 생성 (권장)**

### **Step 1: SQS 콘솔 접속**
1. AWS Console → **SQS (Simple Queue Service)** 이동
2. 리전이 **us-west-1 (N. California)**인지 확인

### **Step 2: eye-tracking-queue.fifo 생성**
1. **Create queue** 버튼 클릭
2. **Type**: 🔄 **FIFO** 선택
3. **Name**: `eye-tracking-queue.fifo` (`.fifo` 접미사 필수)
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds` (16분 - Lambda timeout보다 길게)
   - **Message retention period**: `14 days` (1209600 seconds)
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **FIFO 설정**:
   - **Content-based deduplication**: ✅ **Enable** (자동 중복 제거)
   - **High throughput FIFO**: ❌ **Disable** (단순성 우선)
6. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `eye-tracking-dlq.fifo`
   - **Maximum receives**: `3`
7. **Create queue** 클릭

### **Step 3: finger-tapping-queue.fifo 생성**
1. **Create queue** 버튼 클릭
2. **Type**: 🔄 **FIFO** 선택
3. **Name**: `finger-tapping-queue.fifo`
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds`
   - **Message retention period**: `14 days`
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **FIFO 설정**:
   - **Content-based deduplication**: ✅ **Enable**
   - **High throughput FIFO**: ❌ **Disable**
6. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `finger-tapping-dlq.fifo`
   - **Maximum receives**: `3`
7. **Create queue** 클릭

### **Step 4: voice-analysis-queue.fifo 생성**
1. **Create queue** 버튼 클릭
2. **Type**: 🔄 **FIFO** 선택
3. **Name**: `voice-analysis-queue.fifo`
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds`
   - **Message retention period**: `14 days`
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **FIFO 설정**:
   - **Content-based deduplication**: ✅ **Enable**
   - **High throughput FIFO**: ❌ **Disable**
6. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `voice-analysis-dlq.fifo`
   - **Maximum receives**: `3`
7. **Create queue** 클릭

---

## ⚡ **Standard 큐 생성 (대량 처리용)**

> 💡 **참고**: 대규모 병원 시스템이나 최고 성능 필요시에만 사용

### **Standard 큐 생성 단계**
1. **Create queue** 버튼 클릭
2. **Type**: ⚡ **Standard** 선택
3. **Name**: `eye-tracking-queue` (`.fifo` 없음)
4. **Configuration** 섹션에서:
   - **Visibility timeout**: `960 seconds`
   - **Message retention period**: `14 days`
   - **Delivery delay**: `0 seconds`
   - **Receive message wait time**: `0 seconds`
   - **Maximum message size**: `256 KB`
5. **Dead letter queue**:
   - ✅ **Enable** 체크
   - **Choose queue**: Create new queue → `eye-tracking-dlq`
   - **Maximum receives**: `3`
6. **Create queue** 클릭

## 📋 **생성된 큐 목록**

### **🎯 Standard 큐 (권장)**
총 **6개** 큐가 생성됩니다:

#### **메인 큐 (3개)**
1. `eye-tracking-queue`
2. `finger-tapping-queue`
3. `voice-analysis-queue`

#### **Dead Letter 큐 (3개)**
1. `eye-tracking-dlq`
2. `finger-tapping-dlq`
3. `voice-analysis-dlq`

### **🔄 FIFO 큐 (고급 사용자)**
총 **6개** FIFO 큐가 생성됩니다:

#### **메인 큐 (3개)**
1. `eye-tracking-queue.fifo`
2. `finger-tapping-queue.fifo`
3. `voice-analysis-queue.fifo`

#### **Dead Letter 큐 (3개)**
1. `eye-tracking-dlq.fifo`
2. `finger-tapping-dlq.fifo`
3. `voice-analysis-dlq.fifo`

---

## 📊 **큐 URL 확인**

각 큐 생성 후 **Details** 탭에서 URL 확인:

### **Standard 큐 URL**
```
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/eye-tracking-queue
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/finger-tapping-queue
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/voice-analysis-queue
```

### **FIFO 큐 URL**
```
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/eye-tracking-queue.fifo
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/finger-tapping-queue.fifo
https://sqs.us-west-1.amazonaws.com/YOUR-ACCOUNT-ID/voice-analysis-queue.fifo
```

> 💡 **YOUR-ACCOUNT-ID**를 실제 AWS 계정 ID로 바꿔주세요.
> 이 URL들은 **unified-upload Lambda 환경변수**에서 사용됩니다!

---

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

### **FIFO 전용 설정**
- **Content-based deduplication**: 메시지 내용 기반 자동 중복 제거
- **MessageGroupId**: Lambda 함수에서 `analysis_type` 사용
- **MessageDeduplicationId**: Lambda 함수에서 `analysis_id` 사용

---

## 🔧 **Lambda 함수 코드 수정 (FIFO 큐 사용시)**

FIFO 큐 선택시 `lambda_function.py`에서 다음 코드 확인:

### **현재 코드 (FIFO 대응됨)**
```python
sqs_client.send_message(
    QueueUrl=config['sqs_queue_url'],
    MessageBody=json.dumps(sqs_message),
    MessageGroupId=analysis_type,  # FIFO 큐용 - ✅ 이미 적용됨
    MessageDeduplicationId=analysis_id  # FIFO 큐용 - ✅ 이미 적용됨
)
```

### **Standard 큐 전용 (MessageGroupId 제거 필요)**
```python
sqs_client.send_message(
    QueueUrl=config['sqs_queue_url'],
    MessageBody=json.dumps(sqs_message)
    # MessageGroupId, MessageDeduplicationId 제거
)
```

> ⚠️ **주의**: Standard 큐에는 `MessageGroupId`를 전송하면 오류 발생!

---

## 🔍 **권한 설정 (자동)**

SQS 큐 생성시 AWS가 자동으로 처리하는 항목들:
- Lambda 함수에서 큐 읽기 권한
- 큐에 메시지 전송 권한
- DLQ 접근 권한

추가 IAM 권한 설정은 **Lambda 실행 역할**에서 처리됩니다.

---

## 📱 **환경변수 설정**

### **Standard 큐 ARN**
```
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:eye-tracking-queue
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:finger-tapping-queue
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:voice-analysis-queue
```

### **FIFO 큐 ARN**
```
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:eye-tracking-queue.fifo
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:finger-tapping-queue.fifo
arn:aws:sqs:us-west-1:YOUR-ACCOUNT-ID:voice-analysis-queue.fifo
```

---

## 🎯 **추천사항**

### **🥇 1순위: FIFO 큐 (의료 앱 권장)**
- 환자 데이터 순서 보장 ✅
- 중복 분석 방지 ✅
- 치료 진행도 추적 가능 ✅
- 300 TPS도 개인 앱에 충분
- **Parkinson 분석에 최적화**

### **🥈 2순위: Standard 큐 (대량 처리)**
- 대규모 병원 시스템용
- 무제한 처리량 필요시
- 비용 최적화 우선시

**SQS 큐 설정 완료!** 📨✨