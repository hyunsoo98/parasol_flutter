# 🚀 Lambda 함수 완전 배포 가이드

## 📋 **Lambda 함수 목록**

### **1. 통합 업로드 (unified-upload)**
```bash
# 패키지 생성
mkdir unified-upload-package
cp lambda_unified_upload.py unified-upload-package/

# upload용 경량 requirements 생성
cat > unified-upload-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
requests==2.32.3
EOF

cd unified-upload-package
pip install -r requirements.txt -t .
zip -r ../unified-upload.zip .
cd ..

# Lambda 함수 생성
aws lambda create-function \
    --function-name unified-upload \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_unified_upload.lambda_handler \
    --zip-file fileb://unified-upload.zip \
    --timeout 900 \
    --memory-size 1024 \
    --region us-west-1
```

### **2. 통합 상태 확인 (unified-status)**
```bash
# 패키지 생성
mkdir unified-status-package
cp lambda_unified_status.py unified-status-package/

# status용 경량 requirements 생성
cat > unified-status-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
requests==2.32.3
EOF

cd unified-status-package
pip install -r requirements.txt -t .
zip -r ../unified-status.zip .
cd ..

# Lambda 함수 생성
aws lambda create-function \
    --function-name unified-status \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_unified_status.lambda_handler \
    --zip-file fileb://unified-status.zip \
    --timeout 300 \
    --memory-size 512 \
    --region us-west-1
```

### **3. 아이 트래킹 처리 (eye-tracking-process)**
```bash
# 패키지 생성
mkdir eye-tracking-package
cp lambda_eye_process.py eye-tracking-package/

# eye-tracking용 requirements 생성
cat > eye-tracking-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
opencv-python-headless==4.10.0.84
mediapipe==0.10.21
numpy==1.26.4
pandas==2.2.2
requests==2.32.3
EOF

cd eye-tracking-package
pip install -r requirements.txt -t .
zip -r ../eye-tracking-process.zip .
cd ..

# Lambda 함수 생성
aws lambda create-function \
    --function-name eye-tracking-process \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_eye_process.lambda_handler \
    --zip-file fileb://eye-tracking-process.zip \
    --timeout 900 \
    --memory-size 3008 \
    --region us-west-1
```

### **4. 손가락 태핑 처리 (finger-tapping-process)**
```bash
# 패키지 생성
mkdir finger-tapping-package
cp lambda_finger_process.py finger-tapping-package/
cp feature_extraction.py finger-tapping-package/

# finger-tapping용 requirements 생성
cat > finger-tapping-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
opencv-python-headless==4.10.0.84
mediapipe==0.10.21
numpy==1.26.4
pandas==2.2.2
scikit-learn==1.5.0
joblib==1.4.0
requests==2.32.3
EOF

# AdaBoost 모델 파일 복사
cp best_pipeline_recall_AdaBoost.joblib finger-tapping-package/

cd finger-tapping-package
pip install -r requirements.txt -t .
zip -r ../finger-tapping-process.zip .
cd ..

# Lambda 함수 생성
aws lambda create-function \
    --function-name finger-tapping-process \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_finger_process.lambda_handler \
    --zip-file fileb://finger-tapping-process.zip \
    --timeout 900 \
    --memory-size 3008 \
    --region us-west-1
```

### **5. 음성 분석 처리 (voice-analysis-process)**
```bash
# 패키지 생성
mkdir voice-analysis-package
cp lambda_voice_process_real.py voice-analysis-package/

# CPU 전용 requirements 생성
cat > voice-analysis-package/requirements.txt << EOF
# AWS 공통
boto3==1.34.0
botocore==1.34.0

# 음성 분석 (CPU 전용)
torch==2.1.0+cpu --index-url https://download.pytorch.org/whl/cpu
torchaudio==2.1.0+cpu --index-url https://download.pytorch.org/whl/cpu
librosa==0.10.1
soundfile==1.0.0
scikit-learn==1.3.0

# 공통
numpy==1.24.4
pandas==2.0.3
requests==2.31.0
EOF

# 음성 모델 파일 복사 (핵심 파일만)
cp model_ensemble_avg.pt voice-analysis-package/

cd voice-analysis-package
pip install -r requirements.txt -t .
zip -r ../voice-analysis-process.zip .
cd ..

# Lambda 함수 생성 (메모리 최적화)
aws lambda create-function \
    --function-name voice-analysis-process \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_voice_process_real.lambda_handler \
    --zip-file fileb://voice-analysis-process.zip \
    --timeout 600 \
    --memory-size 2048 \
    --region us-west-1
```

### **6. 종합 진단 (comprehensive-diagnosis)**
```bash
# 패키지 생성
mkdir comprehensive-diagnosis-package
cp lambda_comprehensive_diagnosis.py comprehensive-diagnosis-package/

# comprehensive-diagnosis용 경량 requirements 생성
cat > comprehensive-diagnosis-package/requirements.txt << EOF
boto3==1.34.0
botocore==1.34.0
numpy==1.26.4
pandas==2.2.2
requests==2.32.3
EOF

cd comprehensive-diagnosis-package
pip install -r requirements.txt -t .
zip -r ../comprehensive-diagnosis.zip .
cd ..

# Lambda 함수 생성
aws lambda create-function \
    --function-name comprehensive-diagnosis \
    --runtime python3.9 \
    --role arn:aws:iam::327784329358:role/lambda-execution-role \
    --handler lambda_comprehensive_diagnosis.lambda_handler \
    --zip-file fileb://comprehensive-diagnosis.zip \
    --timeout 900 \
    --memory-size 1024 \
    --region us-west-1
```

## 🔄 **SQS 큐와 Lambda 연결**

### **큐 생성**
```bash
# 각 분석 타입별 큐 생성 (visibility timeout을 Lambda timeout보다 길게 설정)
aws sqs create-queue \
    --queue-name eye-tracking-queue \
    --attributes VisibilityTimeoutSeconds=960,MessageRetentionPeriod=1209600 \
    --region us-west-1

aws sqs create-queue \
    --queue-name finger-tapping-queue \
    --attributes VisibilityTimeoutSeconds=960,MessageRetentionPeriod=1209600 \
    --region us-west-1

aws sqs create-queue \
    --queue-name voice-analysis-queue \
    --attributes VisibilityTimeoutSeconds=960,MessageRetentionPeriod=1209600 \
    --region us-west-1
```

### **Lambda 트리거 설정**
```bash
# Eye Tracking 큐 트리거
aws lambda create-event-source-mapping \
    --event-source-arn arn:aws:sqs:us-west-1:327784329358:eye-tracking-queue \
    --function-name eye-tracking-process \
    --batch-size 1 \
    --region us-west-1

# Finger Tapping 큐 트리거
aws lambda create-event-source-mapping \
    --event-source-arn arn:aws:sqs:us-west-1:327784329358:finger-tapping-queue \
    --function-name finger-tapping-process \
    --batch-size 1 \
    --region us-west-1

# Voice Analysis 큐 트리거
aws lambda create-event-source-mapping \
    --event-source-arn arn:aws:sqs:us-west-1:327784329358:voice-analysis-queue \
    --function-name voice-analysis-process \
    --batch-size 1 \
    --region us-west-1
```

## ⚙️ **환경 변수 설정**

### **1. unified-upload 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name unified-upload \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "EYE_TRACKING_QUEUE":"https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue",
        "FINGER_TAPPING_QUEUE":"https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue",
        "VOICE_ANALYSIS_QUEUE":"https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue",
        "DYNAMODB_TABLE":"parasol-analysis"
    }' \
    --region us-west-1
```

### **2. unified-status 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name unified-status \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"parasol-analysis"
    }' \
    --region us-west-1
```

### **3. eye-tracking-process 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name eye-tracking-process \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"parasol-analysis"
    }' \
    --region us-west-1
```

### **4. finger-tapping-process 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name finger-tapping-process \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"parasol-analysis",
        "MODEL_PATH":"best_pipeline_recall_AdaBoost.joblib"
    }' \
    --region us-west-1
```

### **5. voice-analysis-process 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name voice-analysis-process \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"voice-analysis-results",
        "MODEL_PATH":"model_ensemble_avg.pt",
        "DEVICE":"cpu"
    }' \
    --region us-west-1
```

### **6. parasol-login 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name parasol-login \
    --environment Variables='{
        "DYNAMODB_TABLE":"parasol-users"
    }' \
    --region us-west-1
```

### **7. comprehensive-diagnosis 환경 변수**
```bash
aws lambda update-function-configuration \
    --function-name comprehensive-diagnosis \
    --environment Variables='{
        "S3_BUCKET":"seoul-ht-09",
        "DYNAMODB_TABLE":"parasol-analysis",
        "DIAGNOSIS_TABLE":"diagnosis_sessions"
    }' \
    --region us-west-1
```
```

## 🎯 **배포 순서**

1. **DynamoDB 테이블 생성** (이미 완료)
2. **S3 버킷 및 CORS 설정** (이미 완료)
3. **SQS 큐 생성**
4. **Lambda 함수 배포** (위 순서대로)
5. **Lambda 트리거 설정**
6. **API Gateway 설정**
7. **테스트 및 검증**

## ✅ **배포 완료 확인**

```bash
# Lambda 함수 목록 확인
aws lambda list-functions --region us-west-1

# SQS 큐 확인
aws sqs list-queues --region us-west-1

# API Gateway 확인
aws apigateway get-rest-apis --region us-west-1
```