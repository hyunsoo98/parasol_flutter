# 🖥️ AWS 콘솔에서 직접 리소스 생성 가이드

Amplify CLI나 AWS CLI 없이 AWS 콘솔에서 직접 모든 리소스를 생성하는 방법입니다.

## 1️⃣ DynamoDB 테이블 생성

### 단계별 생성 방법

1. **AWS 콘솔 접속**
   - https://console.aws.amazon.com 접속
   - 로그인 후 서비스 검색에서 "DynamoDB" 입력

2. **DynamoDB 대시보드에서 테이블 생성**
   - 좌측 메뉴에서 "테이블" 클릭
   - "테이블 생성" 버튼 클릭

3. **테이블 설정**
   ```
   테이블 이름: eye-tracking-results
   파티션 키: analysis_id (String)
   정렬 키: (비워둠)
   ```

4. **테이블 설정 (고급)**
   - "테이블 설정" → "기본 설정 사용자 정의" 선택
   - "용량 모드" → "온디맨드" 선택
   - 나머지는 기본값 유지

5. **생성 완료**
   - "테이블 생성" 버튼 클릭
   - 생성 완료까지 1-2분 대기

## 2️⃣ S3 버킷 생성

### 단계별 생성 방법

1. **S3 서비스 접속**
   - 서비스 검색에서 "S3" 입력
   - Amazon S3 클릭

2. **버킷 생성**
   - "버킷 만들기" 버튼 클릭
   
3. **버킷 설정**
   ```
   버킷 이름: eye-tracking-videos-고유번호
   (예: eye-tracking-videos-20241211)
   AWS 리전: 미국 서부(캘리포니아 북부) us-west-1
   ```

4. **객체 소유권**
   - "ACL 비활성화됨(권장)" 선택

5. **퍼블릭 액세스 차단**
   - 기본 설정 유지 (모든 퍼블릭 액세스 차단)

6. **버킷 버전 관리**
   - "비활성화" 선택

7. **생성 완료**
   - "버킷 만들기" 클릭

### CORS 설정 추가

1. **생성된 버킷 선택**
   - 방금 만든 버킷 클릭

2. **권한 탭**
   - "권한" 탭 클릭
   - 하단의 "Cross-origin 리소스 공유(CORS)" 섹션에서 "편집" 클릭

3. **CORS 규칙 입력**
   ```json
   [
       {
           "AllowedHeaders": ["*"],
           "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
           "AllowedOrigins": ["*"],
           "ExposeHeaders": ["ETag"],
           "MaxAgeSeconds": 3000
       }
   ]
   ```

4. **변경 사항 저장**

## 3️⃣ SQS 큐 생성

### 단계별 생성 방법

1. **SQS 서비스 접속**
   - 서비스 검색에서 "SQS" 입력
   - Amazon SQS 클릭

2. **큐 생성**
   - "큐 생성" 버튼 클릭

3. **큐 설정**
   ```
   유형: 표준
   이름: eye-tracking-queue
   ```

4. **구성 설정**
   ```
   가시성 제한 시간: 16분 (960초)
   메시지 보존 기간: 14일
   수신 대기 시간: 0초
   최대 수신 횟수: 3
   ```

5. **생성 완료**
   - "큐 생성" 클릭

## 4️⃣ IAM 역할 생성

### Lambda 실행 역할 생성

1. **IAM 서비스 접속**
   - 서비스 검색에서 "IAM" 입력

2. **역할 생성**
   - 좌측 메뉴 "역할" 클릭
   - "역할 생성" 버튼 클릭

3. **신뢰할 수 있는 엔티티**
   - "AWS 서비스" 선택
   - 사용 사례: "Lambda" 선택
   - "다음" 클릭

4. **권한 정책 연결**
   
   **기본 정책:**
   - `AWSLambdaBasicExecutionRole` 체크

   **사용자 지정 정책 생성:**
   - "정책 생성" 클릭 (새 탭)
   
   **JSON 탭에서 다음 정책 입력:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::eye-tracking-videos-*/*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "dynamodb:GetItem",
           "dynamodb:PutItem",
           "dynamodb:UpdateItem",
           "dynamodb:Scan"
         ],
         "Resource": "arn:aws:dynamodb:us-west-1:*:table/eye-tracking-results"
       },
       {
         "Effect": "Allow",
         "Action": [
           "sqs:SendMessage",
           "sqs:ReceiveMessage",
           "sqs:DeleteMessage",
           "sqs:GetQueueAttributes"
         ],
         "Resource": "arn:aws:sqs:us-west-1:*:eye-tracking-queue"
       }
     ]
   }
   ```

5. **정책 이름**
   - 정책 이름: `EyeTrackingLambdaPolicy`
   - "정책 생성" 클릭

6. **역할에 정책 연결**
   - 기존 역할 생성 탭으로 돌아가기
   - 새로고침 후 `EyeTrackingLambdaPolicy` 체크
   - "다음" 클릭

7. **역할 이름**
   - 역할 이름: `EyeTrackingLambdaRole`
   - "역할 생성" 클릭

## 5️⃣ API Gateway 생성

### REST API 생성

1. **API Gateway 서비스 접속**
   - 서비스 검색에서 "API Gateway" 입력

2. **API 생성**
   - "API 생성" 버튼 클릭
   - "REST API" 카드에서 "구축" 클릭

3. **API 설정**
   ```
   API 이름: EyeTrackingAPI
   설명: Eye Tracking Analysis API
   엔드포인트 유형: 리전
   ```
   - "API 생성" 클릭

### 리소스 및 메서드 생성

#### 1) /upload 리소스

1. **리소스 생성**
   - "작업" → "리소스 생성" 클릭
   - 리소스 이름: `upload`
   - "리소스 생성" 클릭

2. **POST 메서드 생성**
   - `/upload` 리소스 선택
   - "작업" → "메서드 생성" 클릭
   - 드롭다운에서 "POST" 선택 → 체크 아이콘 클릭

3. **통합 설정**
   ```
   통합 유형: Lambda 함수
   Lambda 프록시 통합 사용: 체크
   Lambda 리전: us-west-1
   Lambda 함수: eye-tracking-upload (나중에 생성할 함수명)
   ```
   - "저장" 클릭

#### 2) /status 리소스

1. **리소스 생성**
   - 루트(/) 선택
   - "작업" → "리소스 생성"
   - 리소스 이름: `status`
   - "리소스 생성" 클릭

2. **GET 메서드 생성**
   - `/status` 리소스 선택
   - "작업" → "메서드 생성"
   - "GET" 선택 → 체크

3. **통합 설정**
   ```
   통합 유형: Lambda 함수
   Lambda 프록시 통합 사용: 체크
   Lambda 함수: eye-tracking-status
   ```

#### 3) /status/{analysis_id} 리소스

1. **리소스 생성**
   - `/status` 리소스 선택
   - "작업" → "리소스 생성"
   - 리소스 이름: `{analysis_id}`
   - "리소스 생성" 클릭

2. **GET 메서드 생성**
   - 위와 동일하게 설정

### CORS 활성화

각 메서드에서:
1. 메서드 선택 → "작업" → "CORS 활성화"
2. 기본 설정 유지 → "CORS 활성화 및 기존 CORS 헤더 바꾸기"

### API 배포

1. **배포 생성**
   - "작업" → "API 배포"
   - 배포 스테이지: `[새 스테이지]`
   - 스테이지 이름: `prod`
   - "배포" 클릭

2. **API URL 확인**
   - 배포 후 나타나는 "호출 URL" 복사
   - 예: `https://abcd1234.execute-api.us-west-1.amazonaws.com/prod`

## 6️⃣ 생성된 리소스 정보 정리

배포 후 다음 정보들을 메모해두세요:

### DynamoDB
- 테이블명: `eye-tracking-results`
- ARN: `arn:aws:dynamodb:us-west-1:YOUR_ACCOUNT:table/eye-tracking-results`

### S3
- 버킷명: `eye-tracking-videos-YYYYMMDD`
- ARN: `arn:aws:s3:::eye-tracking-videos-YYYYMMDD`

### SQS
- 큐명: `eye-tracking-queue`
- URL: `https://sqs.us-west-1.amazonaws.com/YOUR_ACCOUNT/eye-tracking-queue`

### IAM
- 역할명: `EyeTrackingLambdaRole`
- ARN: `arn:aws:iam::YOUR_ACCOUNT:role/EyeTrackingLambdaRole`

### API Gateway
- API ID: `abcd1234`
- 호출 URL: `https://abcd1234.execute-api.us-west-1.amazonaws.com/prod`

이제 Lambda 함수들을 생성하고 이 리소스들을 연결하면 됩니다! 🎉

## ❗ 주의사항

1. **리전 일치**: 모든 리소스를 같은 리전(us-west-1)에 생성
2. **권한 확인**: IAM 정책에서 리소스 ARN이 정확한지 확인
3. **비용 모니터링**: 온디맨드 요금제이므로 사용량 확인
4. **보안**: 실제 운영에서는 CORS 설정을 더 제한적으로 구성