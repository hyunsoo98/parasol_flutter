# ⚙️ Lambda 환경변수 설정 (AWS Console)

## 🎯 **7개 Lambda 함수 환경변수 설정**

### **공통 설정 방법**
1. **Lambda 콘솔** → 함수 선택
2. **Configuration** 탭 → **Environment variables** 섹션
3. **Edit** 버튼 클릭
4. **Add environment variable** 로 변수 추가
5. **Save** 클릭

---

## **1. parasol-login**

| Key | Value |
|-----|-------|
| `DYNAMODB_TABLE` | `parasol-users` |

---

## **2. unified-upload**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `EYE_TRACKING_QUEUE` | `https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue` |
| `FINGER_TAPPING_QUEUE` | `https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue` |
| `VOICE_ANALYSIS_QUEUE` | `https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue` |
| `DYNAMODB_TABLE` | `parasol-analysis` |

---

## **3. unified-status**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `DYNAMODB_TABLE` | `parasol-analysis` |

---

## **4. eye-tracking-process**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `DYNAMODB_TABLE` | `parasol-analysis` |

---

## **5. finger-tapping-process**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `DYNAMODB_TABLE` | `parasol-analysis` |
| `MODEL_PATH` | `best_pipeline_recall_AdaBoost.joblib` |

---

## **6. voice-analysis-process**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `DYNAMODB_TABLE` | `parasol-analysis` |
| `MODEL_PATH` | `model_ensemble_avg.pt` |
| `DEVICE` | `cpu` |

---

## **7. comprehensive-diagnosis**

| Key | Value |
|-----|-------|
| `S3_BUCKET` | `seoul-ht-09` |
| `DYNAMODB_TABLE` | `parasol-analysis` |
| `DIAGNOSIS_TABLE` | `diagnosis_sessions` |

---

## 📝 **설정 세부사항**

### **SQS Queue URLs**
- `eye-tracking-queue`: `https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue`
- `finger-tapping-queue`: `https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue`
- `voice-analysis-queue`: `https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue`

### **DynamoDB Tables**
- `parasol-users`: 사용자 정보 저장 (기존 테이블 활용)
- `parasol-analysis`: 메인 분석 결과 저장 (analysisId + testType 구조)
- `eye-tracking-results`: 아이 트래킹 결과 (기존 테이블)
- `finger-tapping-results`: 손가락 태핑 결과 (기존 테이블)

### **S3 Bucket**
- `seoul-ht-09`: 모든 파일 저장 (비디오, 오디오, 결과)

### **Model Files**
- `best_pipeline_recall_AdaBoost.joblib`: 손가락 태핑 분석 모델
- `model_ensemble_avg.pt`: 음성 분석 PyTorch 모델

## ✅ **설정 확인 방법**

각 Lambda 함수에서:
1. **Configuration** → **Environment variables** 확인
2. **Test** 탭에서 간단한 테스트 실행
3. **CloudWatch Logs**에서 환경변수 로드 오류 없는지 확인

## 🔍 **환경변수 테스트 코드**

각 Lambda 함수에 다음 코드로 테스트:

```python
import os

def test_env_vars():
    print("Environment Variables:")
    for key, value in os.environ.items():
        if key.startswith(('S3_', 'DYNAMODB_', 'EYE_', 'FINGER_', 'VOICE_', 'MODEL_', 'DEVICE', 'DIAGNOSIS_')):
            print(f"{key}: {value}")

# Lambda handler에서 호출
test_env_vars()
```

## 🚨 **주의사항**

### **SQS URL 정확성**
- Region: `us-west-1`
- Account ID: `327784329358`
- Queue 이름이 정확한지 확인

### **DynamoDB Table 존재 여부**
모든 테이블이 `us-west-1` 리전에 생성되어 있는지 확인:
- ✅ `parasol-users`
- ✅ `parasol-analysis`
- ✅ `voice-analysis-results`
- ⚠️ `diagnosis_sessions` (아직 생성 필요)

### **S3 Bucket 권한**
`seoul-ht-09` 버킷에 Lambda 실행 역할이 읽기/쓰기 권한을 가지는지 확인

**환경변수 설정 완료!** ⚙️