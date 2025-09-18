# 🚀 Lambda 함수 배포 (AWS Console)

## 📋 **배포할 Lambda 함수 목록**

1. **unified-upload** - 통합 업로드 처리
2. **unified-status** - 통합 상태 확인
3. **eye-tracking-process** - 아이 트래킹 분석
4. **finger-tapping-process** - 손가락 태핑 분석
5. **voice-analysis-process** - 음성 분석
6. **comprehensive-diagnosis** - 종합 진단

## 🔧 **사전 준비사항**

### **ZIP 파일 준비**
각 Lambda 함수별로 ZIP 파일을 미리 생성해야 합니다:

```bash
# 1. unified-upload
mkdir unified-upload-package
cp lambda_unified_upload.py unified-upload-package/
pip install boto3==1.34.0 botocore==1.34.0 requests==2.32.3 -t unified-upload-package/
cd unified-upload-package && zip -r ../unified-upload.zip . && cd ..

# 2. unified-status
mkdir unified-status-package
cp lambda_unified_status.py unified-status-package/
pip install boto3==1.34.0 botocore==1.34.0 requests==2.32.3 -t unified-status-package/
cd unified-status-package && zip -r ../unified-status.zip . && cd ..

# 3. eye-tracking-process
mkdir eye-tracking-package
cp lambda_eye_process.py eye-tracking-package/
pip install boto3==1.34.0 opencv-python-headless==4.10.0.84 mediapipe==0.10.21 numpy==1.26.4 pandas==2.2.2 requests==2.32.3 -t eye-tracking-package/
cd eye-tracking-package && zip -r ../eye-tracking-process.zip . && cd ..

# 4. finger-tapping-process
mkdir finger-tapping-package
cp lambda_finger_process.py finger-tapping-package/
cp feature_extraction.py finger-tapping-package/
cp best_pipeline_recall_AdaBoost.joblib finger-tapping-package/
pip install boto3==1.34.0 opencv-python-headless==4.10.0.84 mediapipe==0.10.21 numpy==1.26.4 pandas==2.2.2 scikit-learn==1.5.0 joblib==1.4.0 requests==2.32.3 -t finger-tapping-package/
cd finger-tapping-package && zip -r ../finger-tapping-process.zip . && cd ..

# 5. voice-analysis-process
mkdir voice-analysis-package
cp lambda_voice_process_real.py voice-analysis-package/
cp model_ensemble_avg.pt voice-analysis-package/
pip install boto3==1.34.0 torch==2.1.0+cpu torchaudio==2.1.0+cpu librosa==0.10.1 soundfile==1.0.0 scikit-learn==1.3.0 numpy==1.24.4 pandas==2.0.3 requests==2.31.0 -t voice-analysis-package/ --index-url https://download.pytorch.org/whl/cpu
cd voice-analysis-package && zip -r ../voice-analysis-process.zip . && cd ..

# 6. comprehensive-diagnosis
mkdir comprehensive-diagnosis-package
cp lambda_comprehensive_diagnosis.py comprehensive-diagnosis-package/
pip install boto3==1.34.0 numpy==1.26.4 pandas==2.2.2 requests==2.32.3 -t comprehensive-diagnosis-package/
cd comprehensive-diagnosis-package && zip -r ../comprehensive-diagnosis.zip . && cd ..
```

## 🏗️ **Lambda 함수 생성 (AWS Console)**

### **공통 단계 (모든 함수)**

1. **Lambda 콘솔 접속**
   - AWS Console → **Lambda** 서비스 이동
   - 리전이 **us-west-1 (N. California)**인지 확인

2. **Create function** 클릭

3. **Author from scratch** 선택

### **1. unified-upload 함수**

**Basic information:**
- **Function name**: `unified-upload`
- **Runtime**: `Python 3.9`
- **Architecture**: `x86_64`

**Permissions:**
- **Execution role**: Use an existing role → `lambda-execution-role`

**Advanced settings:**
- ✅ **Enable function URL** 체크하지 않음

**Create function** 클릭 → 함수 생성 후:

**Upload code:**
1. **Code** 탭에서 **Upload from** → **.zip file** 클릭
2. `unified-upload.zip` 파일 선택
3. **Save** 클릭

**Configuration:**
1. **Configuration** → **General configuration** → **Edit**
   - **Timeout**: `15 minutes` (900 seconds)
   - **Memory**: `1024 MB`
2. **Runtime settings** → **Edit**
   - **Handler**: `lambda_unified_upload.lambda_handler`

### **2. unified-status 함수**

**Basic information:**
- **Function name**: `unified-status`
- **Runtime**: `Python 3.9`
- **Execution role**: `lambda-execution-role`

**Upload code:**
- `unified-status.zip` 업로드

**Configuration:**
- **Timeout**: `5 minutes` (300 seconds)
- **Memory**: `512 MB`
- **Handler**: `lambda_unified_status.lambda_handler`

### **3. eye-tracking-process 함수**

**Basic information:**
- **Function name**: `eye-tracking-process`
- **Runtime**: `Python 3.9`
- **Execution role**: `lambda-execution-role`

**Upload code:**
- `eye-tracking-process.zip` 업로드

**Configuration:**
- **Timeout**: `15 minutes` (900 seconds)
- **Memory**: `3008 MB` (최대)
- **Handler**: `lambda_eye_process.lambda_handler`

### **4. finger-tapping-process 함수**

**Basic information:**
- **Function name**: `finger-tapping-process`
- **Runtime**: `Python 3.9`
- **Execution role**: `lambda-execution-role`

**Upload code:**
- `finger-tapping-process.zip` 업로드

**Configuration:**
- **Timeout**: `15 minutes` (900 seconds)
- **Memory**: `3008 MB`
- **Handler**: `lambda_finger_process.lambda_handler`

### **5. voice-analysis-process 함수**

**Basic information:**
- **Function name**: `voice-analysis-process`
- **Runtime**: `Python 3.9`
- **Execution role**: `lambda-execution-role`

**Upload code:**
- `voice-analysis-process.zip` 업로드

**Configuration:**
- **Timeout**: `10 minutes` (600 seconds)
- **Memory**: `2048 MB`
- **Handler**: `lambda_voice_process_real.lambda_handler`

### **6. comprehensive-diagnosis 함수**

**Basic information:**
- **Function name**: `comprehensive-diagnosis`
- **Runtime**: `Python 3.9`
- **Execution role**: `lambda-execution-role`

**Upload code:**
- `comprehensive-diagnosis.zip` 업로드

**Configuration:**
- **Timeout**: `15 minutes` (900 seconds)
- **Memory**: `1024 MB`
- **Handler**: `lambda_comprehensive_diagnosis.lambda_handler`

## ✅ **배포 완료 확인**

### **Function 목록 확인**
Lambda 콘솔에서 다음 6개 함수가 생성되었는지 확인:

1. ✅ `unified-upload` (15분, 1024MB)
2. ✅ `unified-status` (5분, 512MB)
3. ✅ `eye-tracking-process` (15분, 3008MB)
4. ✅ `finger-tapping-process` (15분, 3008MB)
5. ✅ `voice-analysis-process` (10분, 2048MB)
6. ✅ `comprehensive-diagnosis` (15분, 1024MB)

### **테스트**
각 함수에서 **Test** 탭으로 기본 테스트 실행 (Import 오류가 없는지 확인)

## 🚨 **주의사항**

### **ZIP 파일 크기**
- **voice-analysis-process**: PyTorch 모델로 인해 50MB+ 예상
- **finger-tapping-process**: scikit-learn 포함으로 25MB+ 예상
- 50MB 초과시 S3 업로드 후 Lambda에서 S3 URL로 배포 필요

### **메모리 및 타임아웃**
- 분석 함수들은 최대 메모리(3008MB) 권장
- 타임아웃은 실제 처리 시간 고려하여 충분히 설정
- voice-analysis는 CPU 전용으로 최적화됨

### **권한 확인**
모든 함수가 `lambda-execution-role`을 사용하여:
- S3 읽기/쓰기
- DynamoDB 읽기/쓰기
- SQS 읽기/쓰기
- CloudWatch Logs 쓰기

권한을 가지고 있는지 확인하세요.

**Lambda 함수 배포 완료!** 🚀