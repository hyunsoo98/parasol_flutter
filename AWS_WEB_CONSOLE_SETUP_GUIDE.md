# 🌐 AWS 웹콘솔을 통한 EC2 컨테이너 워커 설정 가이드

> **주의:** 모든 설정은 **us-west-1 (캘리포니아 북부)** 리전에서 진행해주세요.

## 📋 설정 순서 요약
1. IAM 역할 생성
2. ECR 저장소 생성
3. EC2 Launch Template 생성
4. Auto Scaling Group 생성
5. CloudWatch 모니터링 설정

---

## 1️⃣ IAM 역할 생성

### 1.1 IAM 콘솔 접속
1. AWS 콘솔에서 **IAM** 서비스 검색 후 클릭
2. 좌측 메뉴에서 **역할(Roles)** 클릭
3. **역할 생성** 버튼 클릭

### 1.2 신뢰할 수 있는 엔터티 선택
- **AWS 서비스** 선택
- **사용 사례**에서 **EC2** 선택
- **다음** 클릭

### 1.3 권한 정책 연결
다음 정책들을 검색하여 체크:
- ✅ `AmazonS3FullAccess`
- ✅ `AmazonDynamoDBFullAccess`
- ✅ `AmazonSQSFullAccess`
- ✅ `CloudWatchAgentServerPolicy`
- ✅ `AmazonEC2ContainerRegistryReadOnly`

### 1.4 역할 세부 정보
- **역할 이름**: `parasolEC2WorkerRole`
- **설명**: `parasol EC2 Container Worker Role`
- **역할 생성** 클릭

---

## 2️⃣ ECR 저장소 생성

### 2.1 ECR 콘솔 접속
1. AWS 콘솔에서 **ECR** 서비스 검색 후 클릭
2. **프라이빗 레지스트리** → **리포지토리** 메뉴 선택

### 2.2 각 워커별 저장소 생성 (3개 생성)

#### Eye Tracking Worker 저장소
1. **리포지토리 생성** 클릭
2. **가시성 설정**: 프라이빗
3. **리포지토리 이름**: `parasol-eye-worker`
4. **태그 변경 불가능성**: 비활성화
5. **이미지 스캔 설정**: 푸시 시 스캔 활성화
6. **리포지토리 생성** 클릭

#### Voice Analysis Worker 저장소
1. **리포지토리 생성** 클릭
2. **리포지토리 이름**: `parasol-voice-worker`
3. 나머지 설정은 동일
4. **리포지토리 생성** 클릭

#### Finger Tapping Worker 저장소
1. **리포지토리 생성** 클릭
2. **리포지토리 이름**: `parasol-finger-worker`
3. 나머지 설정은 동일
4. **리포지토리 생성** 클릭

---

## 3️⃣ EC2 Launch Template 생성

### 3.1 EC2 콘솔 접속
1. AWS 콘솔에서 **EC2** 서비스 검색 후 클릭
2. 좌측 메뉴에서 **시작 템플릿** 클릭
3. **시작 템플릿 생성** 클릭

### 3.2 시작 템플릿 설정

#### 기본 정보
- **시작 템플릿 이름**: `parasolWorkerTemplate`
- **템플릿 버전 설명**: `parasol Container Worker Template v1`

#### 시작 템플릿 콘텐츠

**애플리케이션 및 OS 이미지 (Amazon Machine Image)**
- **빠른 시작** 탭 선택
- **Amazon Linux** 선택
- **Amazon Linux 2023 AMI** 선택 (최신 버전)

**인스턴스 유형**
- **c5.xlarge** 선택 (4 vCPU, 8GB RAM)

**키 페어(로그인)**
- **키 페어 이름**: 기존 키 페어 선택 또는 "키 페어 없이 진행" 선택

**네트워크 설정**
- **서브넷**: 지정하지 않음 (Auto Scaling에서 설정)
- **방화벽(보안 그룹)**:
  - **보안 그룹 생성** 선택
  - **보안 그룹 이름**: `parasol-worker-sg`
  - **설명**: `Parasol Worker Security Group`
  - **인바운드 보안 그룹 규칙**: 기본값 (SSH만 허용)

**고급 세부 정보**

**IAM 인스턴스 프로파일**
- 드롭다운에서 `ParkinsonEC2WorkerRole` 선택

**사용자 데이터** (텍스트 박스에 입력):
```bash
#!/bin/bash
yum update -y
yum install -y docker
service docker start
usermod -a -G docker ec2-user

# ECR 로그인 설정
aws ecr get-login-password --region us-west-1 | docker login --username AWS --password-stdin 327784329358.dkr.ecr.us-west-1.amazonaws.com

# CloudWatch 에이전트 설치
yum install -y amazon-cloudwatch-agent

# 작업 디렉토리 생성
mkdir -p /home/ec2-user/parkinson-worker
chown ec2-user:ec2-user /home/ec2-user/parkinson-worker
```

### 3.3 시작 템플릿 생성
- **시작 템플릿 생성** 클릭

---

## 4️⃣ Auto Scaling Group 생성

### 4.1 Auto Scaling 콘솔 접속
1. EC2 콘솔에서 좌측 메뉴 **Auto Scaling** → **Auto Scaling 그룹** 클릭
2. **Auto Scaling 그룹 생성** 클릭

### 4.2 1단계: 시작 템플릿 선택
- **Auto Scaling 그룹 이름**: `ParkinsonWorkerASG`
- **시작 템플릿**: `ParkinsonWorkerTemplate` 선택
- **버전**: `최신 ($Latest)` 선택
- **다음** 클릭

### 4.3 2단계: 인스턴스 시작 옵션
- **VPC**: 기본 VPC 선택
- **가용 영역 및 서브넷**:
  - 최소 2개 AZ 선택 (예: us-west-1a, us-west-1c)
  - 각 AZ의 퍼블릭 서브넷 선택
- **다음** 클릭

### 4.4 3단계: 고급 옵션 구성
- **로드 밸런싱**: 로드 밸런서에 연결 안 함 선택
- **상태 확인**:
  - **EC2 상태 확인** 체크
  - **상태 확인 유예 기간**: 300초
- **다음** 클릭

### 4.5 4단계: 그룹 크기 및 크기 조정 정책
**그룹 크기**
- **원하는 용량**: 2
- **최소 용량**: 1
- **최대 용량**: 10

**크기 조정 정책**
- **대상 추적 크기 조정 정책** 선택
- **크기 조정 정책 이름**: `SQSTargetTracking`
- **지표 유형**: **사용자 지정 지표** 선택
- 지표 사양:
  - **네임스페이스**: `AWS/SQS`
  - **지표 이름**: `ApproximateNumberOfVisibleMessages`
  - **차원**:
    - **이름**: `QueueName`
    - **값**: `eye-tracking-queue` (대표 큐 하나 선택)
- **대상 값**: 30
- **다음** 클릭

### 4.6 5단계: 알림 추가 (선택사항)
- 알림 건너뛰기 - **다음** 클릭

### 4.7 6단계: 태그 추가
태그 추가:
- **키**: `Name`, **값**: `ParkinsonWorker`
- **키**: `Project`, **값**: `Parkinson`
- **키**: `Environment`, **값**: `Production`
- **다음** 클릭

### 4.8 7단계: 검토
- 설정 내용 확인
- **Auto Scaling 그룹 생성** 클릭

---

## 5️⃣ CloudWatch 대시보드 생성

### 5.1 CloudWatch 콘솔 접속
1. AWS 콘솔에서 **CloudWatch** 서비스 검색 후 클릭
2. 좌측 메뉴에서 **대시보드** 클릭
3. **대시보드 생성** 클릭

### 5.2 대시보드 설정
- **대시보드 이름**: `ParkinsonWorkerDashboard`
- **생성** 클릭

### 5.3 위젯 추가

#### SQS 큐 메시지 수 모니터링
1. **위젯 추가** 클릭
2. **선 그래프** 선택
3. **지표** 탭에서:
   - **AWS/SQS** 선택
   - **QueueName** 체크
   - 각 큐 선택: `eye-tracking-queue`, `finger-tapping-queue`, `voice-analysis-queue`
   - **지표**: `ApproximateNumberOfVisibleMessages` 선택
4. **위젯 생성** 클릭

#### EC2 인스턴스 CPU 사용률
1. **위젯 추가** 클릭
2. **선 그래프** 선택
3. **AWS/EC2** → **InstanceId** 선택
4. **지표**: `CPUUtilization` 선택
5. Auto Scaling Group의 모든 인스턴스 선택
6. **위젯 생성** 클릭

### 5.4 대시보드 저장
- **저장** 클릭

---

## 6️⃣ 추가 보안 설정

### 6.1 보안 그룹 수정
1. EC2 콘솔 → **보안 그룹** 메뉴
2. `parkinson-worker-sg` 선택
3. **인바운드 규칙** 탭에서 **인바운드 규칙 편집**
4. 현재 설정 유지 (SSH만 허용)
5. **규칙 저장**

### 6.2 VPC 설정 검토 (선택사항)
- 보안 강화를 위해 프라이빗 서브넷 사용 고려
- NAT Gateway 설정으로 아웃바운드 트래픽만 허용

---

## 📊 검증 및 테스트

### 7.1 인스턴스 상태 확인
1. EC2 콘솔 → **인스턴스** 메뉴
2. `ParkinsonWorker` 태그를 가진 인스턴스들이 `running` 상태인지 확인
3. Auto Scaling Group에서 원하는 용량(2개)만큼 인스턴스가 생성되었는지 확인

### 7.2 로그 확인
1. CloudWatch 콘솔 → **로그** → **로그 그룹**
2. `/aws/ec2/user-data` 로그 그룹에서 사용자 데이터 스크립트 실행 로그 확인

### 7.3 ECR 로그인 테스트
1. EC2 인스턴스에 SSH 접속
2. 다음 명령어로 ECR 로그인 확인:
```bash
aws ecr describe-repositories --region us-west-1
```

---

## ⚠️ 주요 체크포인트

### ✅ 필수 확인 사항
- [ ] IAM 역할에 모든 필요한 정책이 연결되었는지 확인
- [ ] ECR 저장소 3개가 모두 생성되었는지 확인
- [ ] Launch Template에 올바른 IAM 역할이 설정되었는지 확인
- [ ] Auto Scaling Group에서 인스턴스가 정상 실행되는지 확인
- [ ] 모든 리소스가 us-west-1 리전에 생성되었는지 확인

### 💰 비용 관리
- 테스트 완료 후 Auto Scaling Group의 원하는 용량을 0으로 설정
- 불필요한 인스턴스는 즉시 종료
- CloudWatch 대시보드를 통해 리소스 사용량 정기 모니터링

### 🔧 다음 단계
1. Docker 이미지 빌드 및 ECR에 푸시
2. 워커 애플리케이션 배포 스크립트 작성
3. SQS 메시지 처리 로직 구현 및 테스트

이 가이드를 따라 설정하면 AWS 웹콘솔을 통해 EC2 컨테이너 워커 인프라가 완성됩니다!