# 🔗 SQS-Lambda 트리거 설정 (AWS Console)

## 🎯 **3개 큐와 Lambda 함수 연결**

### **연결 매핑**
1. `eye-tracking-queue` → `eye-tracking-process`
2. `finger-tapping-queue` → `finger-tapping-process`
3. `voice-analysis-queue` → `voice-analysis-process`

---

## 🔧 **Lambda 함수에서 트리거 설정**

### **1. eye-tracking-process 트리거 설정**

1. **Lambda 콘솔** → `eye-tracking-process` 함수 선택
2. **Configuration** 탭 → **Triggers** 선택
3. **Add trigger** 버튼 클릭
4. **Trigger configuration**:
   - **Select a source**: `SQS`
   - **SQS queue**: `eye-tracking-queue` 선택
   - **Batch size**: `1` (한 번에 하나의 메시지만 처리)
   - **Batch window**: `0` (즉시 처리)
   - **Enable trigger**: ✅ 체크
5. **Add** 클릭

### **2. finger-tapping-process 트리거 설정**

1. **Lambda 콘솔** → `finger-tapping-process` 함수 선택
2. **Configuration** 탭 → **Triggers** 선택
3. **Add trigger** 버튼 클릭
4. **Trigger configuration**:
   - **Select a source**: `SQS`
   - **SQS queue**: `finger-tapping-queue` 선택
   - **Batch size**: `1`
   - **Batch window**: `0`
   - **Enable trigger**: ✅ 체크
5. **Add** 클릭

### **3. voice-analysis-process 트리거 설정**

1. **Lambda 콘솔** → `voice-analysis-process` 함수 선택
2. **Configuration** 탭 → **Triggers** 선택
3. **Add trigger** 버튼 클릭
4. **Trigger configuration**:
   - **Select a source**: `SQS`
   - **SQS queue**: `voice-analysis-queue` 선택
   - **Batch size**: `1`
   - **Batch window**: `0`
   - **Enable trigger**: ✅ 체크
5. **Add** 클릭

---

## ⚙️ **트리거 설정 세부사항**

### **Batch Size: 1**
- 한 번에 하나의 분석 작업만 처리
- 메모리 사용량 최적화
- 개별 오류 처리 가능

### **Batch Window: 0**
- 메시지 도착 즉시 Lambda 실행
- 분석 지연 최소화

### **Enable Trigger: ✅**
- 트리거 활성화
- SQS 메시지 자동 처리 시작

### **권한 자동 설정**
AWS가 자동으로 다음 권한을 설정합니다:
- Lambda 함수가 SQS 큐에서 메시지 읽기
- 처리 완료 후 메시지 삭제
- DLQ로 실패 메시지 전송

---

## 📊 **SQS에서 트리거 확인**

### **각 SQS 큐에서 확인**

1. **SQS 콘솔** → 큐 선택 (예: `eye-tracking-queue`)
2. **Lambda triggers** 탭 확인
3. 연결된 Lambda 함수가 표시되는지 확인:
   - `eye-tracking-queue` → `eye-tracking-process`
   - `finger-tapping-queue` → `finger-tapping-process`
   - `voice-analysis-queue` → `voice-analysis-process`

---

## ✅ **트리거 작동 확인**

### **1. 테스트 메시지 전송**

**SQS 콘솔에서 테스트:**

1. `eye-tracking-queue` 선택
2. **Send message** 버튼 클릭
3. **Message body**에 테스트 JSON 입력:
```json
{
  "analysis_id": "test_eye_001",
  "s3_key": "eye-tracking/test_eye_001/video.mp4",
  "user_id": "test_user"
}
```
4. **Send message** 클릭

### **2. Lambda 실행 확인**

1. **Lambda 콘솔** → `eye-tracking-process` 선택
2. **Monitor** 탭 → **CloudWatch Logs** 확인
3. 함수가 실행되었는지 로그 확인

### **3. 메시지 처리 확인**

1. **SQS 콘솔** → `eye-tracking-queue` 선택
2. **Messages available**: `0` (메시지가 처리되어 사라짐)
3. 오류시 **Messages in flight** 또는 DLQ에 메시지 확인

---

## 🔍 **트러블슈팅**

### **트리거가 작동하지 않는 경우**

**1. 권한 확인**
- Lambda 실행 역할에 SQS 읽기 권한 있는지 확인
- `lambda-execution-role`에 `AmazonSQSFullAccess` 정책 연결

**2. 큐 설정 확인**
- Visibility timeout (960초)이 Lambda timeout보다 긴지 확인
- 큐 이름이 정확한지 확인

**3. Lambda 설정 확인**
- 함수가 `us-west-1` 리전에 있는지 확인
- 메모리와 타임아웃이 충분한지 확인

### **메시지가 DLQ로 이동하는 경우**

**1. Lambda 로그 확인**
- CloudWatch Logs에서 오류 메시지 확인
- Import 오류, 환경변수 오류 등 해결

**2. DLQ 메시지 확인**
- Dead Letter Queue에서 실패한 메시지 내용 확인
- 메시지 형식이 올바른지 검증

---

## 📈 **모니터링 설정**

### **CloudWatch 메트릭 확인**

1. **CloudWatch 콘솔** → **Metrics** 이동
2. **AWS/SQS** 네임스페이스에서 확인:
   - `NumberOfMessagesSent`
   - `NumberOfMessagesReceived`
   - `NumberOfMessagesDeleted`

3. **AWS/Lambda** 네임스페이스에서 확인:
   - `Invocations`: 함수 실행 횟수
   - `Duration`: 실행 시간
   - `Errors`: 오류 발생 횟수

### **알람 설정 (선택사항)**

1. **CloudWatch 콘솔** → **Alarms** → **Create alarm**
2. **Metric**: `AWS/Lambda/Errors`
3. **Threshold**: 오류 1회 이상시 알림
4. **SNS Topic**: 이메일 알림 설정

**SQS-Lambda 트리거 설정 완료!** 🔗