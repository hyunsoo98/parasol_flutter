# AWS Lambda Container Image 배포 가이드

## 📋 개요

MediaPipe + OpenCV 라이브러리 크기 문제로 인한 AWS Lambda 250MB 제한을 해결하기 위해 Container Image 방식으로 배포하는 가이드입니다.

### 현재 문제점
- MediaPipe (0.10.7) + OpenCV (4.8.1.78) 라이브러리가 250MB 제한 초과
- Lambda Layer로도 해결 불가
- Eye-tracking 분석 성능 저하

### Container Image 방식의 장점
- **크기 제한**: 250MB → **10GB**로 확장
- **의존성 관리**: Dockerfile로 모든 라이브러리 포함
- **환경 일관성**: 로컬 개발환경과 동일
- **복잡한 설치**: 시스템 레벨 패키지도 설치 가능

## 🏗️ 프로젝트 구조

```
aws-deployment/lambda-functions/
├── lambda-eye-container/
│   ├── Dockerfile
│   ├── lambda_eye_process.py (기존 파일)
│   ├── lambda_function.py (진입점)
│   ├── requirements.txt
│   ├── build_and_deploy.sh
│   └── .dockerignore
└── ...
```

## 📝 구현 단계

### 1. 디렉토리 생성 및 파일 구성

```bash
mkdir aws-deployment/lambda-functions/lambda-eye-container
cd aws-deployment/lambda-functions/lambda-eye-container
```

### 2. Dockerfile 생성

```dockerfile
FROM public.ecr.aws/lambda/python:3.11

# 시스템 패키지 설치 (OpenCV 의존성)
RUN yum update -y && \
    yum install -y \
    mesa-libGL \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgtk-3-0 \
    && yum clean all

# Python 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Lambda 함수 코드 복사
COPY lambda_eye_process.py ${LAMBDA_TASK_ROOT}/
COPY lambda_function.py ${LAMBDA_TASK_ROOT}/

# Lambda 핸들러 설정
CMD ["lambda_function.lambda_handler"]
```

### 3. requirements.txt 생성

```txt
boto3==1.34.0
numpy==1.24.3
pandas==2.0.3
opencv-python==4.8.1.78
mediapipe==0.10.7
```

### 4. lambda_function.py (진입점) 생성

```python
from lambda_eye_process import lambda_handler

def lambda_handler(event, context):
    """
    Container Image Lambda 진입점
    기존 lambda_eye_process.py의 lambda_handler 함수 호출
    """
    return lambda_handler(event, context)
```

### 5. .dockerignore 생성

```dockerignore
*.md
.git/
__pycache__/
*.pyc
tests/
docs/
.DS_Store
*.log
```

### 6. 배포 스크립트 생성 (build_and_deploy.sh)

```bash
#!/bin/bash

# 설정값 (본인의 AWS 계정 정보로 변경)
ACCOUNT_ID="your-account-id"
REGION="ap-northeast-2"
REPO_NAME="lambda-eye-tracking"
FUNCTION_NAME="lambda-eye-process"

echo "🚀 Lambda Container Image 배포 시작..."

# 1. ECR 로그인
echo "📝 ECR 로그인 중..."
aws ecr get-login-password --region $REGION | \
docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# 2. ECR 레포지토리 생성 (존재하지 않을 경우)
echo "📦 ECR 레포지토리 생성 중..."
aws ecr create-repository --repository-name $REPO_NAME --region $REGION || echo "레포지토리가 이미 존재합니다."

# 3. Docker 이미지 빌드
echo "🔨 Docker 이미지 빌드 중..."
docker build -t $REPO_NAME .

# 4. 태그 설정
echo "🏷️ 이미지 태그 설정 중..."
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# 5. ECR에 푸시
echo "📤 ECR에 이미지 푸시 중..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# 6. Lambda 함수 업데이트
echo "🔄 Lambda 함수 업데이트 중..."
aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --image-uri $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# 7. Lambda 함수 설정 업데이트 (메모리, 타임아웃)
echo "⚙️ Lambda 함수 설정 업데이트 중..."
aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --timeout 900 \
    --memory-size 3008

echo "✅ 배포 완료!"
echo "📊 Lambda 함수 정보:"
aws lambda get-function --function-name $FUNCTION_NAME --query 'Configuration.[FunctionName,Runtime,CodeSize,Timeout,MemorySize]' --output table
```

## 🚀 배포 과정

### 1. 사전 준비

```bash
# AWS CLI 설치 및 설정
aws configure

# Docker 설치 확인
docker --version

# 본인의 AWS 계정 ID 확인
aws sts get-caller-identity --query Account --output text
```

### 2. 파일 복사 및 설정

```bash
# 기존 lambda_eye_process.py 파일 복사
cp ../lambda_eye_process.py ./

# build_and_deploy.sh의 ACCOUNT_ID 수정
# your-account-id를 실제 AWS 계정 ID로 변경
```

### 3. 배포 실행

```bash
# 실행 권한 부여
chmod +x build_and_deploy.sh

# 배포 실행
./build_and_deploy.sh
```

## 🔧 최적화 옵션

### Multi-stage Build로 이미지 크기 최적화

```dockerfile
# 빌드 스테이지
FROM public.ecr.aws/lambda/python:3.11 as builder

RUN yum update -y && yum install -y gcc gcc-c++ cmake
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -t /tmp/lib

# 런타임 스테이지
FROM public.ecr.aws/lambda/python:3.11

RUN yum update -y && \
    yum install -y mesa-libGL libgomp1 && \
    yum clean all

COPY --from=builder /tmp/lib ${LAMBDA_RUNTIME_DIR}
COPY lambda_eye_process.py ${LAMBDA_TASK_ROOT}/
COPY lambda_function.py ${LAMBDA_TASK_ROOT}/

CMD ["lambda_function.lambda_handler"]
```

## 📊 성능 및 비용 고려사항

### 성능
- **Cold Start**: 컨테이너 이미지는 ZIP보다 1-2초 느림
- **권장 메모리**: 2048MB 이상 (MediaPipe 최적화)
- **타임아웃**: 최대 15분 설정 가능

### 비용
- **ECR 저장**: $0.10/GB/월
- **Lambda 실행**: 기존과 동일
- **예상 이미지 크기**: 1-2GB

### 모니터링
```bash
# Lambda 로그 확인
aws logs tail /aws/lambda/lambda-eye-process --follow

# 메트릭 확인
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=lambda-eye-process \
    --statistics Average \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600
```

## 🛠️ 트러블슈팅

### 자주 발생하는 문제

1. **Docker 빌드 실패**
   ```bash
   # Docker 데몬 실행 확인
   docker ps

   # 캐시 없이 빌드
   docker build --no-cache -t lambda-eye-tracking .
   ```

2. **ECR 권한 문제**
   ```bash
   # IAM 정책 확인 필요
   # AmazonEC2ContainerRegistryFullAccess 권한 필요
   ```

3. **Lambda 메모리 부족**
   ```bash
   # 메모리 3008MB로 증가
   aws lambda update-function-configuration \
       --function-name lambda-eye-process \
       --memory-size 3008
   ```

4. **Cold Start 지연**
   ```bash
   # 프로비저닝된 동시성 설정 (비용 추가)
   aws lambda put-provisioned-concurrency-config \
       --function-name lambda-eye-process \
       --provisioned-concurrency-value 1
   ```

## 📋 체크리스트

배포 전 확인사항:
- [ ] AWS CLI 설정 완료
- [ ] Docker 설치 및 실행 중
- [ ] AWS 계정 ID 확인
- [ ] ECR 권한 설정
- [ ] 기존 Lambda 함수 백업

배포 후 확인사항:
- [ ] Lambda 함수 정상 작동
- [ ] 메모리/타임아웃 설정 확인
- [ ] CloudWatch 로그 확인
- [ ] 성능 테스트 수행

## 🔄 롤백 방법

기존 ZIP 배포로 되돌리기:
```bash
# 기존 배포 패키지로 롤백
aws lambda update-function-code \
    --function-name lambda-eye-process \
    --zip-file fileb://previous-deployment.zip

# 패키지 타입을 ZIP으로 변경
aws lambda update-function-configuration \
    --function-name lambda-eye-process \
    --package-type Zip
```

---

**💡 참고**: 이 가이드는 MediaPipe 라이브러리 크기 문제를 해결하기 위한 임시 해결책입니다. 장기적으로는 더 가벼운 라이브러리나 외부 API 방식을 고려하는 것이 좋습니다.