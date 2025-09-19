# EC2 기반 영상 분석 시스템 구축 가이드

## 📋 개요

Lambda의 제약사항(15분 타임아웃, 메모리 제한, 라이브러리 크기 제한)을 해결하기 위한 EC2 기반 영상 분석 시스템 구축 가이드입니다.

### Lambda 방식의 문제점
- ⏱️ **시간 제한**: 15분 타임아웃으로 긴 영상 처리 불가
- 💾 **메모리 제한**: 최대 10GB로 대용량 영상 처리 한계
- 📦 **라이브러리 제한**: MediaPipe + OpenCV = 250MB+ 초과
- 💰 **비용 문제**: 장시간 처리 시 Lambda 비용 급증

### EC2 방식의 장점
- ⏱️ **무제한 처리 시간**: 몇 시간짜리 영상도 처리 가능
- 💾 **충분한 메모리**: 최대 768GB+까지 확장 가능
- 📦 **자유로운 라이브러리**: 모든 Python 패키지 설치 가능
- 💰 **비용 효율성**: 장기 사용 시 Lambda 대비 90% 절약
- 🔧 **완전한 제어**: OS 레벨 커스터마이징 가능
- 🚀 **병렬 처리**: 여러 영상 동시 분석 가능

## 🏗️ 시스템 아키텍처

### 전체 구조도
```
┌─────────────────┐    ┌─────────────┐    ┌─────────────┐
│   Flutter App   │───▶│     S3      │───▶│  SQS Queue  │
└─────────────────┘    │ (Videos)    │    │ (Jobs)      │
                       └─────────────┘    └─────────────┘
                                                 │
                                                 ▼
┌─────────────────┐    ┌─────────────┐    ┌─────────────┐
│  Results View   │◀───│     S3      │◀───│ EC2 Workers │
│   (Flutter)     │    │ (Results)   │    │Auto Scaling │
└─────────────────┘    └─────────────┘    │   Group     │
                                          └─────────────┘
                                                 │
                                                 ▼
                                        ┌─────────────┐
                                        │  DynamoDB   │
                                        │  (Status)   │
                                        └─────────────┘
```

### 구성 요소
1. **S3 Bucket**: 영상 파일 및 결과 저장
2. **SQS Queue**: 분석 작업 대기열
3. **EC2 Auto Scaling Group**: 워커 인스턴스들
4. **Application Load Balancer**: 트래픽 분산 (선택)
5. **DynamoDB**: 분석 상태 및 메타데이터
6. **CloudWatch**: 모니터링 및 알람

## 📁 프로젝트 구조

```
aws-deployment/
├── ec2-video-analysis/
│   ├── infrastructure/
│   │   ├── cloudformation-stack.yaml      # 인프라 구성
│   │   ├── user-data.sh                   # EC2 초기 설정 스크립트
│   │   └── iam-policies.json              # IAM 권한 설정
│   ├── application/
│   │   ├── worker.py                      # 메인 워커 애플리케이션
│   │   ├── video_processor.py             # 영상 분석 로직
│   │   ├── aws_services.py                # AWS 서비스 인터페이스
│   │   ├── config.py                      # 설정 관리
│   │   └── requirements.txt               # Python 의존성
│   ├── deployment/
│   │   ├── deploy.sh                      # 배포 스크립트
│   │   ├── update-code.sh                 # 코드 업데이트 스크립트
│   │   └── monitoring-setup.sh            # 모니터링 설정
│   └── docker/                            # Docker 관련 (선택)
│       ├── Dockerfile
│       └── docker-compose.yml
├── flutter-integration/
│   ├── ec2_analysis_service.dart          # Flutter 서비스 클래스
│   └── analysis_status_widget.dart        # 상태 표시 위젯
└── monitoring/
    ├── cloudwatch-dashboard.json          # 대시보드 설정
    └── alarms.yaml                        # 알람 설정
```

## 🚀 Phase 1: 기본 EC2 시스템 구축

### 1. CloudFormation 템플릿

```yaml
# infrastructure/cloudformation-stack.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'EC2 기반 영상 분석 시스템'

Parameters:
  InstanceType:
    Type: String
    Default: 't3.large'
    AllowedValues: ['t3.medium', 't3.large', 't3.xlarge', 'c5.large', 'c5.xlarge', 'c5.2xlarge', 'g4dn.xlarge']
    Description: EC2 인스턴스 타입

  KeyPairName:
    Type: AWS::EC2::KeyPair::KeyName
    Description: SSH 접근용 키페어

  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC ID

  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>
    Description: 서브넷 IDs (최소 2개)

Resources:
  # S3 버킷 - 영상 및 결과 저장
  VideoBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${AWS::StackName}-videos-${AWS::AccountId}"
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      NotificationConfiguration:
        QueueConfigurations:
          - Event: s3:ObjectCreated:*
            Queue: !GetAtt VideoAnalysisQueue.Arn
            Filter:
              S3Key:
                Rules:
                  - Name: prefix
                    Value: input/
                  - Name: suffix
                    Value: .mp4

  # SQS 큐 - 분석 작업 대기열
  VideoAnalysisQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "${AWS::StackName}-video-analysis-queue"
      VisibilityTimeoutSeconds: 3600  # 1시간 (긴 처리 시간 고려)
      MessageRetentionPeriod: 1209600  # 14일
      ReceiveMessageWaitTimeSeconds: 20  # Long polling
      ReddrivePolicy:
        deadLetterTargetArn: !GetAtt DeadLetterQueue.Arn
        maxReceiveCount: 3

  # 데드 레터 큐
  DeadLetterQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "${AWS::StackName}-video-analysis-dlq"
      MessageRetentionPeriod: 1209600

  # SQS 정책 - S3가 메시지 발송할 수 있도록 허용
  QueuePolicy:
    Type: AWS::SQS::QueuePolicy
    Properties:
      Queues:
        - !Ref VideoAnalysisQueue
      PolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: s3.amazonaws.com
            Action: sqs:SendMessage
            Resource: !GetAtt VideoAnalysisQueue.Arn
            Condition:
              ArnEquals:
                aws:SourceArn: !GetAtt VideoBucket.Arn

  # DynamoDB 테이블 - 분석 상태 저장
  AnalysisStatusTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub "${AWS::StackName}-analysis-status"
      AttributeDefinitions:
        - AttributeName: analysisId
          AttributeType: S
        - AttributeName: userId
          AttributeType: S
        - AttributeName: status
          AttributeType: S
      KeySchema:
        - AttributeName: analysisId
          KeyType: HASH
      GlobalSecondaryIndexes:
        - IndexName: UserIndex
          KeySchema:
            - AttributeName: userId
              KeyType: HASH
            - AttributeName: status
              KeyType: RANGE
          Projection:
            ProjectionType: ALL
          BillingMode: PAY_PER_REQUEST
      BillingMode: PAY_PER_REQUEST

  # IAM 역할 - EC2 인스턴스용
  EC2Role:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
      Policies:
        - PolicyName: VideoAnalysisPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                  - s3:DeleteObject
                Resource:
                  - !Sub "${VideoBucket}/*"
              - Effect: Allow
                Action:
                  - s3:ListBucket
                Resource:
                  - !GetAtt VideoBucket.Arn
              - Effect: Allow
                Action:
                  - sqs:ReceiveMessage
                  - sqs:DeleteMessage
                  - sqs:GetQueueAttributes
                  - sqs:GetQueueUrl
                Resource:
                  - !GetAtt VideoAnalysisQueue.Arn
              - Effect: Allow
                Action:
                  - dynamodb:PutItem
                  - dynamodb:GetItem
                  - dynamodb:UpdateItem
                  - dynamodb:Query
                  - dynamodb:Scan
                Resource:
                  - !GetAtt AnalysisStatusTable.Arn
                  - !Sub "${AnalysisStatusTable.Arn}/index/*"
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                  - logs:DescribeLogStreams
                Resource: "*"

  # 인스턴스 프로필
  EC2InstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref EC2Role

  # 보안 그룹
  EC2SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for video analysis EC2 instances
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0  # 실제 운영에서는 특정 IP로 제한
        - IpProtocol: tcp
          FromPort: 8000
          ToPort: 8000
          CidrIp: 10.0.0.0/16  # 내부 통신용
      SecurityGroupEgress:
        - IpProtocol: -1
          CidrIp: 0.0.0.0/0

  # 런치 템플릿
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateName: !Sub "${AWS::StackName}-launch-template"
      LaunchTemplateData:
        ImageId: ami-0c02fb55956c7d316  # Amazon Linux 2 (리전별로 조정 필요)
        InstanceType: !Ref InstanceType
        KeyName: !Ref KeyPairName
        IamInstanceProfile:
          Arn: !GetAtt EC2InstanceProfile.Arn
        SecurityGroupIds:
          - !Ref EC2SecurityGroup
        UserData:
          Fn::Base64: !Sub |
            #!/bin/bash
            yum update -y
            yum install -y python3 python3-pip git htop

            # CloudWatch Agent 설치
            yum install -y amazon-cloudwatch-agent

            # 애플리케이션 디렉토리 생성
            mkdir -p /opt/video-analysis
            cd /opt/video-analysis

            # 환경 변수 설정
            echo "export AWS_DEFAULT_REGION=${AWS::Region}" >> /etc/environment
            echo "export S3_BUCKET=${VideoBucket}" >> /etc/environment
            echo "export SQS_QUEUE_URL=${VideoAnalysisQueue}" >> /etc/environment
            echo "export DYNAMODB_TABLE=${AnalysisStatusTable}" >> /etc/environment

            # 시스템 패키지 설치 (OpenCV 의존성)
            yum install -y mesa-libGL libgomp

            # 코드 다운로드 및 설치는 별도 스크립트에서 수행

            # 서비스 시작 (systemd)
            systemctl enable video-analysis-worker
            systemctl start video-analysis-worker

  # Auto Scaling Group
  AutoScalingGroup:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      AutoScalingGroupName: !Sub "${AWS::StackName}-asg"
      VPCZoneIdentifier: !Ref SubnetIds
      LaunchTemplate:
        LaunchTemplateId: !Ref LaunchTemplate
        Version: !GetAtt LaunchTemplate.LatestVersionNumber
      MinSize: 1
      MaxSize: 10
      DesiredCapacity: 2
      HealthCheckType: EC2
      HealthCheckGracePeriod: 300
      Tags:
        - Key: Name
          Value: !Sub "${AWS::StackName}-worker"
          PropagateAtLaunch: true
        - Key: Purpose
          Value: VideoAnalysis
          PropagateAtLaunch: true

  # Auto Scaling 정책 - Scale Up
  ScaleUpPolicy:
    Type: AWS::AutoScaling::ScalingPolicy
    Properties:
      AutoScalingGroupName: !Ref AutoScalingGroup
      PolicyType: StepScaling
      AdjustmentType: ChangeInCapacity
      StepAdjustments:
        - MetricIntervalLowerBound: 0
          MetricIntervalUpperBound: 10
          ScalingAdjustment: 1
        - MetricIntervalLowerBound: 10
          ScalingAdjustment: 2

  # Auto Scaling 정책 - Scale Down
  ScaleDownPolicy:
    Type: AWS::AutoScaling::ScalingPolicy
    Properties:
      AutoScalingGroupName: !Ref AutoScalingGroup
      PolicyType: StepScaling
      AdjustmentType: ChangeInCapacity
      StepAdjustments:
        - MetricIntervalUpperBound: 0
          ScalingAdjustment: -1

  # CloudWatch 알람 - Scale Up
  HighQueueDepthAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub "${AWS::StackName}-high-queue-depth"
      AlarmDescription: "Scale up when queue depth is high"
      MetricName: ApproximateNumberOfMessages
      Namespace: AWS/SQS
      Statistic: Average
      Period: 300
      EvaluationPeriods: 2
      Threshold: 5
      ComparisonOperator: GreaterThanThreshold
      Dimensions:
        - Name: QueueName
          Value: !GetAtt VideoAnalysisQueue.QueueName
      AlarmActions:
        - !Ref ScaleUpPolicy

  # CloudWatch 알람 - Scale Down
  LowQueueDepthAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: !Sub "${AWS::StackName}-low-queue-depth"
      AlarmDescription: "Scale down when queue depth is low"
      MetricName: ApproximateNumberOfMessages
      Namespace: AWS/SQS
      Statistic: Average
      Period: 300
      EvaluationPeriods: 3
      Threshold: 1
      ComparisonOperator: LessThanThreshold
      Dimensions:
        - Name: QueueName
          Value: !GetAtt VideoAnalysisQueue.QueueName
      AlarmActions:
        - !Ref ScaleDownPolicy

Outputs:
  BucketName:
    Description: S3 Bucket Name
    Value: !Ref VideoBucket
    Export:
      Name: !Sub "${AWS::StackName}-BucketName"

  QueueUrl:
    Description: SQS Queue URL
    Value: !Ref VideoAnalysisQueue
    Export:
      Name: !Sub "${AWS::StackName}-QueueUrl"

  TableName:
    Description: DynamoDB Table Name
    Value: !Ref AnalysisStatusTable
    Export:
      Name: !Sub "${AWS::StackName}-TableName"
```

### 2. EC2 워커 애플리케이션

#### A. 메인 워커 스크립트 (application/worker.py)

```python
#!/usr/bin/env python3
"""
EC2 기반 영상 분석 워커
SQS에서 메시지를 받아 영상을 분석하고 결과를 저장합니다.
"""

import os
import sys
import json
import time
import logging
import signal
import threading
from concurrent.futures import ThreadPoolExecutor
from video_processor import VideoProcessor
from aws_services import AWSServices
from config import Config

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/video-analysis-worker.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class VideoAnalysisWorker:
    def __init__(self):
        self.config = Config()
        self.aws_services = AWSServices(self.config)
        self.video_processor = VideoProcessor(self.config)
        self.running = False
        self.executor = ThreadPoolExecutor(max_workers=self.config.MAX_CONCURRENT_JOBS)

    def start(self):
        """워커 시작"""
        logger.info("Starting Video Analysis Worker...")
        logger.info(f"SQS Queue: {self.config.SQS_QUEUE_URL}")
        logger.info(f"S3 Bucket: {self.config.S3_BUCKET}")
        logger.info(f"DynamoDB Table: {self.config.DYNAMODB_TABLE}")
        logger.info(f"Max Concurrent Jobs: {self.config.MAX_CONCURRENT_JOBS}")

        self.running = True

        # 시그널 핸들러 등록
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        # 메인 루프
        self._main_loop()

    def _main_loop(self):
        """메인 처리 루프"""
        while self.running:
            try:
                # SQS에서 메시지 받기
                messages = self.aws_services.receive_messages(
                    max_messages=self.config.SQS_MAX_MESSAGES,
                    wait_time=self.config.SQS_WAIT_TIME
                )

                if not messages:
                    logger.debug("No messages received, continuing...")
                    time.sleep(5)
                    continue

                # 메시지 처리
                for message in messages:
                    if not self.running:
                        break

                    # 스레드풀에 작업 제출
                    future = self.executor.submit(self._process_message, message)
                    # 에러 처리를 위한 콜백 등록
                    future.add_done_callback(self._handle_job_completion)

            except Exception as e:
                logger.error(f"Error in main loop: {str(e)}", exc_info=True)
                time.sleep(10)  # 에러 시 잠시 대기

        logger.info("Worker stopped.")

    def _process_message(self, message):
        """개별 메시지 처리"""
        try:
            # 메시지 파싱
            message_body = json.loads(message['Body'])

            # S3 이벤트에서 정보 추출
            if 'Records' in message_body:
                s3_record = message_body['Records'][0]['s3']
                bucket = s3_record['bucket']['name']
                key = s3_record['object']['key']
            else:
                # 직접 메시지인 경우
                bucket = message_body.get('bucket')
                key = message_body.get('key')

            if not bucket or not key:
                logger.error(f"Invalid message format: {message_body}")
                return

            logger.info(f"Processing video: s3://{bucket}/{key}")

            # 분석 ID 추출 (예: input/user123/analysis456/video.mp4)
            path_parts = key.split('/')
            if len(path_parts) >= 4:
                user_id = path_parts[1]
                analysis_id = path_parts[2]
            else:
                logger.error(f"Invalid S3 key format: {key}")
                return

            # 상태를 processing으로 업데이트
            self.aws_services.update_analysis_status(
                analysis_id, user_id, 'processing', 0, 'Started processing'
            )

            # 영상 다운로드
            logger.info(f"Downloading video from S3: {key}")
            video_data = self.aws_services.download_from_s3(bucket, key)
            self.aws_services.update_analysis_status(
                analysis_id, user_id, 'processing', 25, 'Video downloaded'
            )

            # 영상 분석 수행
            logger.info(f"Starting video analysis: {analysis_id}")
            analysis_result = self.video_processor.analyze_video(
                video_data,
                progress_callback=lambda progress, message: self.aws_services.update_analysis_status(
                    analysis_id, user_id, 'processing', 25 + int(progress * 0.7), message
                )
            )

            # 결과 저장
            result_key = f"results/{user_id}/{analysis_id}/analysis_result.json"
            self.aws_services.upload_to_s3(
                json.dumps(analysis_result, indent=2).encode('utf-8'),
                result_key,
                'application/json'
            )

            # CSV 결과 저장 (있는 경우)
            if 'csv_data' in analysis_result:
                csv_key = f"results/{user_id}/{analysis_id}/analysis_data.csv"
                self.aws_services.upload_to_s3(
                    analysis_result['csv_data'].encode('utf-8'),
                    csv_key,
                    'text/csv'
                )
                analysis_result['csv_path'] = csv_key
                del analysis_result['csv_data']  # 큰 데이터 제거

            # 최종 상태 업데이트
            self.aws_services.update_analysis_status(
                analysis_id, user_id, 'completed', 100, 'Analysis completed', analysis_result
            )

            logger.info(f"Analysis completed successfully: {analysis_id}")

            # SQS 메시지 삭제
            self.aws_services.delete_message(message['ReceiptHandle'])

        except Exception as e:
            logger.error(f"Error processing message: {str(e)}", exc_info=True)

            # 실패 상태로 업데이트
            try:
                if 'analysis_id' in locals() and 'user_id' in locals():
                    self.aws_services.update_analysis_status(
                        analysis_id, user_id, 'failed', 0, f'Processing failed: {str(e)}'
                    )
            except:
                pass

    def _handle_job_completion(self, future):
        """작업 완료 처리"""
        try:
            future.result()  # 예외 발생 시 여기서 raise
        except Exception as e:
            logger.error(f"Job failed with exception: {str(e)}", exc_info=True)

    def _signal_handler(self, signum, frame):
        """시그널 핸들러"""
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False

    def stop(self):
        """워커 중지"""
        logger.info("Stopping worker...")
        self.running = False
        self.executor.shutdown(wait=True)

def main():
    """메인 함수"""
    worker = VideoAnalysisWorker()

    try:
        worker.start()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.error(f"Worker crashed: {str(e)}", exc_info=True)
    finally:
        worker.stop()

if __name__ == "__main__":
    main()
```

#### B. 영상 분석 로직 (application/video_processor.py)

```python
"""
영상 분석 처리 로직
기존 lambda_eye_process.py의 로직을 EC2 환경에 맞게 개선
"""

import os
import cv2
import numpy as np
import pandas as pd
import math
import tempfile
import logging
from typing import Dict, Any, List, Callable, Optional

logger = logging.getLogger(__name__)

try:
    import mediapipe as mp
    mp_face_mesh = mp.solutions.face_mesh
    from mediapipe.python.solutions.face_mesh_connections import (
        FACEMESH_LEFT_IRIS, FACEMESH_RIGHT_IRIS,
    )
    MEDIAPIPE_AVAILABLE = True
except ImportError:
    logger.warning("MediaPipe not available, using fallback processing")
    MEDIAPIPE_AVAILABLE = False
    mp_face_mesh = None
    FACEMESH_LEFT_IRIS = []
    FACEMESH_RIGHT_IRIS = []

class VideoProcessor:
    def __init__(self, config):
        self.config = config
        self._face_mesh_model = None

        # MediaPipe 모델 초기화
        if MEDIAPIPE_AVAILABLE:
            self._initialize_mediapipe()

    def _initialize_mediapipe(self):
        """MediaPipe FaceMesh 모델 초기화"""
        try:
            self._face_mesh_model = mp_face_mesh.FaceMesh(
                static_image_mode=False,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
            logger.info("MediaPipe FaceMesh initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize MediaPipe: {str(e)}")
            self._face_mesh_model = None

    def analyze_video(self, video_data: bytes, progress_callback: Optional[Callable] = None) -> Dict[str, Any]:
        """
        영상 분석 메인 함수

        Args:
            video_data: 영상 파일 바이트 데이터
            progress_callback: 진행률 콜백 함수

        Returns:
            분석 결과 딕셔너리
        """
        try:
            # 임시 파일로 영상 저장
            with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp_file:
                tmp_file.write(video_data)
                tmp_file_path = tmp_file.name

            try:
                # 영상 분석 수행
                result = self._process_video_file(tmp_file_path, progress_callback)
                return result

            finally:
                # 임시 파일 정리
                if os.path.exists(tmp_file_path):
                    os.unlink(tmp_file_path)

        except Exception as e:
            logger.error(f"Video analysis failed: {str(e)}", exc_info=True)
            return {
                'status': 'error',
                'error': str(e),
                'detected': False
            }

    def _process_video_file(self, video_path: str, progress_callback: Optional[Callable] = None) -> Dict[str, Any]:
        """영상 파일 처리"""

        if not MEDIAPIPE_AVAILABLE or not self._face_mesh_model:
            return {
                'status': 'error',
                'error': 'MediaPipe not available',
                'detected': False
            }

        # OpenCV로 영상 열기
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise Exception("Cannot open video file")

        # 영상 정보 추출
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        logger.info(f"Video info: {width}x{height}, {fps} fps, {total_frames} frames")

        if progress_callback:
            progress_callback(0.1, "Video opened, starting frame analysis")

        # 분석 파라미터
        step = self.config.ANALYSIS_STEP
        max_frames = min(total_frames, self.config.MAX_FRAMES)
        vpp_thresh = self.config.VPP_THRESHOLD
        blink_thresh = self.config.BLINK_THRESHOLD

        rows = []
        frame_idx = 0
        processed = 0

        try:
            while processed < max_frames:
                ret, frame = cap.read()
                if not ret:
                    break

                if frame_idx % step != 0:
                    frame_idx += 1
                    continue

                # 진행률 업데이트
                if progress_callback and processed % 100 == 0:
                    progress = 0.1 + (processed / max_frames) * 0.7
                    progress_callback(progress, f"Processing frame {processed}/{max_frames}")

                # 프레임 분석
                t_sec = frame_idx / max(1e-6, fps)
                frame_result = self._analyze_frame(frame, width, height)

                if frame_result['detected']:
                    rows.append({
                        "frame_idx": frame_idx,
                        "time_sec": t_sec,
                        **frame_result['metrics']
                    })
                else:
                    # 검출 실패 시 NaN으로 채움
                    rows.append({
                        "frame_idx": frame_idx,
                        "time_sec": t_sec,
                        "L_iris_cx": np.nan, "L_iris_cy": np.nan,
                        "L_eye_open": np.nan, "L_v_offset": np.nan,
                        "R_iris_cx": np.nan, "R_iris_cy": np.nan,
                        "R_eye_open": np.nan, "R_v_offset": np.nan,
                        "eye_open": np.nan, "v_offset": np.nan,
                    })

                processed += 1
                frame_idx += 1

        finally:
            cap.release()

        if not rows:
            return {
                'status': 'error',
                'error': 'No frames processed',
                'detected': False
            }

        if progress_callback:
            progress_callback(0.9, "Calculating analysis results")

        # 결과 분석
        result = self._calculate_analysis_results(rows, fps, vpp_thresh, blink_thresh)

        if progress_callback:
            progress_callback(1.0, "Analysis completed")

        return result

    def _analyze_frame(self, frame: np.ndarray, width: int, height: int) -> Dict[str, Any]:
        """단일 프레임 분석"""
        try:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = self._face_mesh_model.process(rgb)

            if not results.multi_face_landmarks:
                return {"detected": False, "reason": "no_face"}

            landmarks = results.multi_face_landmarks[0].landmark

            # 왼쪽/오른쪽 눈 메트릭 계산
            left_metrics = self._calculate_eye_metrics(landmarks, width, height, is_left=True)
            right_metrics = self._calculate_eye_metrics(landmarks, width, height, is_left=False)

            # 전체 메트릭 계산
            eye_open = float(np.nanmean([left_metrics["eye_open"], right_metrics["eye_open"]]))
            v_offset = float(np.nanmean([left_metrics["v_offset"], right_metrics["v_offset"]]))

            return {
                "detected": True,
                "metrics": {
                    "L_iris_cx": left_metrics["iris_cx"],
                    "L_iris_cy": left_metrics["iris_cy"],
                    "L_eye_open": left_metrics["eye_open"],
                    "L_v_offset": left_metrics["v_offset"],
                    "R_iris_cx": right_metrics["iris_cx"],
                    "R_iris_cy": right_metrics["iris_cy"],
                    "R_eye_open": right_metrics["eye_open"],
                    "R_v_offset": right_metrics["v_offset"],
                    "eye_open": eye_open,
                    "v_offset": v_offset,
                }
            }

        except Exception as e:
            logger.error(f"Frame analysis error: {str(e)}")
            return {"detected": False, "reason": f"analysis_error: {str(e)}"}

    def _calculate_eye_metrics(self, landmarks, w: int, h: int, is_left: bool = True) -> Dict[str, float]:
        """눈 메트릭 계산 (기존 lambda_eye_process.py 로직)"""
        # 눈 랜드마크 인덱스
        L_CORNER_OUT, L_CORNER_IN = 33, 133
        L_LID_TOP, L_LID_BOT = 159, 145
        R_CORNER_OUT, R_CORNER_IN = 362, 263
        R_LID_TOP, R_LID_BOT = 386, 374

        if is_left:
            c_out, c_in = L_CORNER_OUT, L_CORNER_IN
            lid_top, lid_bot = L_LID_TOP, L_LID_BOT
            iris_idxs = self._uniq_indices(FACEMESH_LEFT_IRIS) if FACEMESH_LEFT_IRIS else []
        else:
            c_out, c_in = R_CORNER_OUT, R_CORNER_IN
            lid_top, lid_bot = R_LID_TOP, R_LID_BOT
            iris_idxs = self._uniq_indices(FACEMESH_RIGHT_IRIS) if FACEMESH_RIGHT_IRIS else []

        # 픽셀 좌표 변환
        def _px(lm):
            return lm.x * w, lm.y * h

        x_out, y_out = _px(landmarks[c_out])
        x_in, y_in = _px(landmarks[c_in])
        eye_width = max(1e-6, math.hypot(x_out - x_in, y_out - y_in))

        x_t, y_t = _px(landmarks[lid_top])
        x_b, y_b = _px(landmarks[lid_bot])
        eyelid_dist = math.hypot(x_t - x_b, y_t - y_b)

        eye_open = eyelid_dist / eye_width

        # 홍채 중심 계산
        ix, iy = self._iris_center(landmarks, iris_idxs, w, h)

        cx, cy = (x_out + x_in) / 2.0, (y_out + y_in) / 2.0
        eye_height = max(1e-6, eyelid_dist)
        v_offset_norm = (iy - cy) / eye_height if not np.isnan(iy) else np.nan

        return {
            "iris_cx": ix,
            "iris_cy": iy,
            "eye_open": eye_open,
            "v_offset": v_offset_norm,
        }

    def _iris_center(self, landmarks, idxs: List[int], w: int, h: int):
        """홍채 중심점 계산"""
        if not idxs:
            return float("nan"), float("nan")

        xs, ys = [], []
        for i in idxs:
            if i < len(landmarks):
                x, y = landmarks[i].x * w, landmarks[i].y * h
                xs.append(x)
                ys.append(y)

        if not xs:
            return float("nan"), float("nan")

        return float(np.mean(xs)), float(np.mean(ys))

    def _uniq_indices(self, conns: List[tuple]) -> List[int]:
        """연결점들에서 고유 인덱스 추출"""
        s = set()
        for a, b in conns:
            s.add(a)
            s.add(b)
        return sorted(list(s))

    def _calculate_analysis_results(self, rows: List[Dict], fps: float, vpp_thresh: float, blink_thresh: float) -> Dict[str, Any]:
        """분석 결과 계산"""
        df = pd.DataFrame(rows).sort_values("frame_idx").reset_index(drop=True)

        # CSV 데이터 생성
        csv_data = df.to_csv(index=False)

        # 통계 계산
        v_series = df["v_offset"].to_numpy(dtype=float)
        eye_open_series = df["eye_open"].to_numpy(dtype=float)
        v_valid = v_series[~np.isnan(v_series)]
        open_valid = eye_open_series[~np.isnan(eye_open_series)]

        def robust_ptp(x: np.ndarray) -> float:
            if x.size == 0:
                return float("nan")
            lo, hi = np.percentile(x, [5, 95])
            return float(hi - lo)

        v_ptp = robust_ptp(v_valid)
        v_std = float(np.nanstd(v_valid)) if v_valid.size else float("nan")

        # 블링크 카운트
        blink_count = self._count_blinks(open_valid.tolist(), thresh=blink_thresh)

        # 영상 시간 계산
        dur_sec = float(df["time_sec"].dropna().max() - df["time_sec"].dropna().min()) if df["time_sec"].notna().any() else float("nan")
        blink_rate_per_min = (blink_count / dur_sec * 60.0) if (dur_sec and not math.isnan(dur_sec) and dur_sec > 0) else float("nan")

        # PSP 의심 여부 판정
        psp_suspected = bool(v_ptp < vpp_thresh) if not math.isnan(v_ptp) else False
        psp_reason = f"vertical_peak_to_peak({v_ptp:.3f}) < threshold({vpp_thresh:.3f})" if psp_suspected else "criteria_not_met"

        return {
            'status': 'success',
            'detected': True,
            'summary': {
                "frames_processed": len(df),
                "fps": fps,
                "duration_sec": dur_sec,
                "vertical_offset_std": v_std,
                "vertical_peak_to_peak": v_ptp,
                "blink_count": blink_count,
                "blink_rate_per_min": blink_rate_per_min,
                "psp_suspected": psp_suspected,
                "psp_rule_reason": psp_reason,
            },
            'csv_data': csv_data,  # S3에 저장될 CSV 데이터
            'analysis_timestamp': pd.Timestamp.now().isoformat()
        }

    def _count_blinks(self, openness_series: List[float], thresh: float = 0.18, min_frames: int = 2) -> int:
        """블링크 카운트 (기존 로직)"""
        closed = False
        hold = 0
        count = 0

        for v in openness_series:
            if np.isnan(v):
                if closed and hold >= min_frames:
                    count += 1
                closed, hold = False, 0
                continue

            if v < thresh:
                if closed:
                    hold += 1
                else:
                    closed = True
                    hold = 1
            else:
                if closed and hold >= min_frames:
                    count += 1
                closed, hold = False, 0

        if closed and hold >= min_frames:
            count += 1
        return count
```

#### C. AWS 서비스 인터페이스 (application/aws_services.py)

```python
"""
AWS 서비스 인터페이스
S3, SQS, DynamoDB 등과의 상호작용을 처리
"""

import boto3
import json
import logging
from typing import List, Dict, Any, Optional
from datetime import datetime
from botocore.exceptions import ClientError, BotoCoreError

logger = logging.getLogger(__name__)

class AWSServices:
    def __init__(self, config):
        self.config = config

        # AWS 클라이언트 초기화
        try:
            self.s3_client = boto3.client('s3', region_name=config.AWS_REGION)
            self.sqs_client = boto3.client('sqs', region_name=config.AWS_REGION)
            self.dynamodb = boto3.resource('dynamodb', region_name=config.AWS_REGION)
            self.table = self.dynamodb.Table(config.DYNAMODB_TABLE)

            logger.info("AWS services initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize AWS services: {str(e)}")
            raise

    def receive_messages(self, max_messages: int = 1, wait_time: int = 20) -> List[Dict]:
        """SQS에서 메시지 받기"""
        try:
            response = self.sqs_client.receive_message(
                QueueUrl=self.config.SQS_QUEUE_URL,
                MaxNumberOfMessages=max_messages,
                WaitTimeSeconds=wait_time,
                AttributeNames=['All'],
                MessageAttributeNames=['All']
            )

            messages = response.get('Messages', [])
            logger.debug(f"Received {len(messages)} messages from SQS")
            return messages

        except Exception as e:
            logger.error(f"Failed to receive SQS messages: {str(e)}")
            return []

    def delete_message(self, receipt_handle: str) -> bool:
        """SQS 메시지 삭제"""
        try:
            self.sqs_client.delete_message(
                QueueUrl=self.config.SQS_QUEUE_URL,
                ReceiptHandle=receipt_handle
            )
            logger.debug("SQS message deleted successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to delete SQS message: {str(e)}")
            return False

    def download_from_s3(self, bucket: str, key: str) -> bytes:
        """S3에서 파일 다운로드"""
        try:
            logger.info(f"Downloading from S3: s3://{bucket}/{key}")
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            data = response['Body'].read()
            logger.info(f"Downloaded {len(data)} bytes from S3")
            return data

        except ClientError as e:
            error_code = e.response['Error']['Code']
            logger.error(f"S3 download failed ({error_code}): {str(e)}")
            raise Exception(f"S3 download failed: {error_code}")
        except Exception as e:
            logger.error(f"S3 download failed: {str(e)}")
            raise

    def upload_to_s3(self, data: bytes, key: str, content_type: str = 'application/octet-stream') -> str:
        """S3에 파일 업로드"""
        try:
            bucket = self.config.S3_BUCKET
            logger.info(f"Uploading to S3: s3://{bucket}/{key}")

            self.s3_client.put_object(
                Bucket=bucket,
                Key=key,
                Body=data,
                ContentType=content_type
            )

            s3_url = f"s3://{bucket}/{key}"
            logger.info(f"Uploaded to S3: {s3_url}")
            return s3_url

        except Exception as e:
            logger.error(f"S3 upload failed: {str(e)}")
            raise Exception(f"S3 upload failed: {str(e)}")

    def update_analysis_status(self, analysis_id: str, user_id: str, status: str,
                             progress: int, message: str = "", result_data: Optional[Dict] = None):
        """DynamoDB에 분석 상태 업데이트"""
        try:
            item = {
                'analysisId': analysis_id,
                'userId': user_id,
                'status': status,
                'progress': progress,
                'message': message,
                'updatedAt': int(datetime.now().timestamp()),
                'testType': 'eye-tracking'
            }

            if result_data:
                item['results'] = result_data

            self.table.put_item(Item=item)
            logger.debug(f"Updated analysis status: {analysis_id} -> {status} ({progress}%)")

        except Exception as e:
            logger.error(f"DynamoDB update failed: {str(e)}")
            # 상태 업데이트 실패는 치명적이지 않으므로 예외를 발생시키지 않음

    def get_analysis_status(self, analysis_id: str) -> Optional[Dict]:
        """분석 상태 조회"""
        try:
            response = self.table.get_item(
                Key={'analysisId': analysis_id}
            )

            if 'Item' in response:
                return response['Item']
            else:
                return None

        except Exception as e:
            logger.error(f"Failed to get analysis status: {str(e)}")
            return None
```

#### D. 설정 관리 (application/config.py)

```python
"""
설정 관리 클래스
환경 변수와 기본값을 관리합니다.
"""

import os

class Config:
    def __init__(self):
        # AWS 기본 설정
        self.AWS_REGION = os.environ.get('AWS_DEFAULT_REGION', 'ap-northeast-2')
        self.S3_BUCKET = os.environ.get('S3_BUCKET', '')
        self.SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL', '')
        self.DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', '')

        # SQS 설정
        self.SQS_MAX_MESSAGES = int(os.environ.get('SQS_MAX_MESSAGES', '1'))
        self.SQS_WAIT_TIME = int(os.environ.get('SQS_WAIT_TIME', '20'))

        # 워커 설정
        self.MAX_CONCURRENT_JOBS = int(os.environ.get('MAX_CONCURRENT_JOBS', '2'))

        # 분석 파라미터
        self.ANALYSIS_STEP = int(os.environ.get('ANALYSIS_STEP', '1'))
        self.MAX_FRAMES = int(os.environ.get('MAX_FRAMES', '12000'))
        self.VPP_THRESHOLD = float(os.environ.get('VPP_THRESHOLD', '0.06'))
        self.BLINK_THRESHOLD = float(os.environ.get('BLINK_THRESHOLD', '0.18'))

        # 로깅 설정
        self.LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')

        # 설정 검증
        self._validate_config()

    def _validate_config(self):
        """설정값 검증"""
        required_configs = [
            ('S3_BUCKET', self.S3_BUCKET),
            ('SQS_QUEUE_URL', self.SQS_QUEUE_URL),
            ('DYNAMODB_TABLE', self.DYNAMODB_TABLE),
        ]

        missing_configs = []
        for name, value in required_configs:
            if not value:
                missing_configs.append(name)

        if missing_configs:
            raise ValueError(f"Missing required configuration: {', '.join(missing_configs)}")

    def __str__(self):
        """설정 정보 출력 (민감한 정보 제외)"""
        return f"""
Configuration:
  AWS Region: {self.AWS_REGION}
  S3 Bucket: {self.S3_BUCKET}
  DynamoDB Table: {self.DYNAMODB_TABLE}
  Max Concurrent Jobs: {self.MAX_CONCURRENT_JOBS}
  Analysis Step: {self.ANALYSIS_STEP}
  Max Frames: {self.MAX_FRAMES}
"""
```

#### E. 의존성 파일 (application/requirements.txt)

```txt
# AWS SDK
boto3==1.34.0
botocore==1.34.0

# 영상 처리
opencv-python==4.8.1.78
mediapipe==0.10.7
numpy==1.24.3
pandas==2.0.3

# 유틸리티
python-dotenv==1.0.0
psutil==5.9.0
requests==2.31.0

# 로깅 및 모니터링
structlog==23.2.0
```

### 3. 시스템 서비스 설정

#### Systemd 서비스 파일 (/etc/systemd/system/video-analysis-worker.service)

```ini
[Unit]
Description=Video Analysis Worker
After=network.target
Wants=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/video-analysis
ExecStart=/opt/video-analysis/venv/bin/python /opt/video-analysis/worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# 환경 변수
Environment=AWS_DEFAULT_REGION=ap-northeast-2
Environment=PYTHONPATH=/opt/video-analysis
Environment=PYTHONUNBUFFERED=1

# 리소스 제한
LimitNOFILE=65536
MemoryMax=6G

[Install]
WantedBy=multi-user.target
```

### 4. 배포 스크립트

#### A. 인프라 배포 (deployment/deploy.sh)

```bash
#!/bin/bash

set -e

# 설정
STACK_NAME="ec2-video-analysis"
REGION="ap-northeast-2"
KEY_PAIR_NAME="your-key-pair"
VPC_ID="vpc-xxxxxxxxx"
SUBNET_IDS="subnet-xxxxxxxxx,subnet-yyyyyyyyy"
INSTANCE_TYPE="t3.large"

echo "🚀 EC2 기반 영상 분석 시스템 배포 시작..."

# 1. CloudFormation 스택 배포
echo "📦 Infrastructure 배포 중..."
aws cloudformation deploy \
    --template-file infrastructure/cloudformation-stack.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides \
        InstanceType=$INSTANCE_TYPE \
        KeyPairName=$KEY_PAIR_NAME \
        VpcId=$VPC_ID \
        SubnetIds=$SUBNET_IDS \
    --capabilities CAPABILITY_IAM \
    --region $REGION

if [ $? -eq 0 ]; then
    echo "✅ Infrastructure 배포 완료"
else
    echo "❌ Infrastructure 배포 실패"
    exit 1
fi

# 2. 스택 출력값 가져오기
echo "📊 배포된 리소스 정보 확인 중..."
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text \
    --region $REGION)

QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`QueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`TableName`].OutputValue' \
    --output text \
    --region $REGION)

echo "📋 배포된 리소스:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  SQS Queue: $QUEUE_URL"
echo "  DynamoDB Table: $TABLE_NAME"

# 3. 애플리케이션 코드 S3에 업로드
echo "📤 애플리케이션 코드 업로드 중..."
cd application
zip -r ../video-analysis-app.zip .
cd ..

aws s3 cp video-analysis-app.zip s3://$BUCKET_NAME/deployment/
rm video-analysis-app.zip

# 4. Auto Scaling Group 인스턴스들이 시작될 때까지 대기
echo "⏳ EC2 인스턴스 시작 대기 중..."
sleep 60

# 5. 코드 배포
echo "🔄 애플리케이션 코드 배포 중..."
./deployment/update-code.sh $STACK_NAME

echo "🎉 배포 완료!"
echo ""
echo "📝 다음 단계:"
echo "  1. AWS 콘솔에서 Auto Scaling Group 상태 확인"
echo "  2. CloudWatch 로그에서 워커 동작 확인"
echo "  3. 테스트 영상으로 시스템 검증"
echo ""
echo "🔍 모니터링:"
echo "  - CloudWatch 대시보드: https://console.aws.amazon.com/cloudwatch/"
echo "  - SQS 큐 모니터링: https://console.aws.amazon.com/sqs/"
echo "  - Auto Scaling Group: https://console.aws.amazon.com/ec2/autoscaling/"
```

#### B. 코드 업데이트 스크립트 (deployment/update-code.sh)

```bash
#!/bin/bash

set -e

STACK_NAME=${1:-"ec2-video-analysis"}
REGION="ap-northeast-2"

echo "🔄 애플리케이션 코드 업데이트 시작..."

# Auto Scaling Group의 인스턴스 목록 가져오기
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${STACK_NAME}-asg" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
    --output text \
    --region $REGION)

if [ -z "$INSTANCE_IDS" ]; then
    echo "❌ 활성 인스턴스를 찾을 수 없습니다."
    exit 1
fi

echo "📋 업데이트할 인스턴스: $INSTANCE_IDS"

# S3 버킷 이름 가져오기
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text \
    --region $REGION)

# 각 인스턴스에 SSM 명령 실행
for INSTANCE_ID in $INSTANCE_IDS; do
    echo "🔧 인스턴스 $INSTANCE_ID 업데이트 중..."

    aws ssm send-command \
        --instance-ids $INSTANCE_ID \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
            "cd /opt/video-analysis",
            "sudo systemctl stop video-analysis-worker",
            "aws s3 cp s3://'$BUCKET_NAME'/deployment/video-analysis-app.zip ./",
            "unzip -o video-analysis-app.zip",
            "rm video-analysis-app.zip",
            "source venv/bin/activate",
            "pip install -r requirements.txt",
            "sudo systemctl start video-analysis-worker",
            "sudo systemctl status video-analysis-worker"
        ]' \
        --region $REGION

done

echo "✅ 코드 업데이트 완료"
```

### 5. Flutter 클라이언트 통합

#### Flutter 서비스 클래스 (flutter-integration/ec2_analysis_service.dart)

```dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class EC2AnalysisService {
  static const String baseUrl = 'https://your-api-gateway-url';
  static const String s3Bucket = 'your-s3-bucket-name';

  /// EC2 시스템에 영상 업로드 및 분석 요청
  Future<String> startVideoAnalysis(File videoFile, String userId) async {
    try {
      // 1. 분석 ID 생성
      String analysisId = Uuid().v4();

      // 2. S3 키 생성
      String s3Key = 'input/$userId/$analysisId/${videoFile.path.split('/').last}';

      // 3. Presigned URL 요청
      final presignedUrl = await _getPresignedUrl(s3Key);

      // 4. S3에 직접 업로드
      await _uploadToS3(videoFile, presignedUrl);

      // 5. 분석 상태 초기화
      await _initializeAnalysisStatus(analysisId, userId);

      print('Video uploaded for EC2 analysis. Analysis ID: $analysisId');
      return analysisId;

    } catch (e) {
      throw Exception('Failed to start EC2 video analysis: $e');
    }
  }

  /// Presigned URL 요청
  Future<String> _getPresignedUrl(String s3Key) async {
    final response = await http.post(
      Uri.parse('$baseUrl/get-presigned-url'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'bucket': s3Bucket,
        'key': s3Key,
        'operation': 'put'
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['presignedUrl'];
    } else {
      throw Exception('Failed to get presigned URL: ${response.statusCode}');
    }
  }

  /// S3에 파일 업로드
  Future<void> _uploadToS3(File videoFile, String presignedUrl) async {
    final bytes = await videoFile.readAsBytes();

    final response = await http.put(
      Uri.parse(presignedUrl),
      body: bytes,
      headers: {
        'Content-Type': 'video/mp4',
        'Content-Length': bytes.length.toString(),
      },
    );

    if (response.statusCode != 200) {
      throw Exception('S3 upload failed: ${response.statusCode}');
    }
  }

  /// 분석 상태 초기화
  Future<void> _initializeAnalysisStatus(String analysisId, String userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/analysis/initialize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'analysisId': analysisId,
        'userId': userId,
        'status': 'queued',
        'progress': 0,
        'message': 'Video uploaded, waiting for processing'
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to initialize analysis status');
    }
  }

  /// 분석 상태 조회
  Future<EC2AnalysisStatus> getAnalysisStatus(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analysis/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return EC2AnalysisStatus.fromJson(data);
      } else if (response.statusCode == 404) {
        throw Exception('Analysis not found');
      } else {
        throw Exception('Failed to get analysis status: ${response.statusCode}');
      }

    } catch (e) {
      throw Exception('EC2 analysis status error: $e');
    }
  }

  /// 분석 결과 다운로드
  Future<Map<String, dynamic>> downloadAnalysisResults(String analysisId, String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analysis/$analysisId/results'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to download results: ${response.statusCode}');
      }

    } catch (e) {
      throw Exception('Results download error: $e');
    }
  }
}

class EC2AnalysisStatus {
  final String analysisId;
  final String userId;
  final String status; // queued, processing, completed, failed
  final double progress; // 0-100
  final String message;
  final DateTime updatedAt;
  final Map<String, dynamic>? results;

  EC2AnalysisStatus({
    required this.analysisId,
    required this.userId,
    required this.status,
    required this.progress,
    required this.message,
    required this.updatedAt,
    this.results,
  });

  factory EC2AnalysisStatus.fromJson(Map<String, dynamic> json) {
    return EC2AnalysisStatus(
      analysisId: json['analysisId'],
      userId: json['userId'],
      status: json['status'],
      progress: (json['progress'] ?? 0).toDouble(),
      message: json['message'] ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] * 1000),
      results: json['results'],
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing';
  bool get isQueued => status == 'queued';

  String get statusDisplayText {
    switch (status) {
      case 'queued':
        return '분석 대기 중';
      case 'processing':
        return '분석 중';
      case 'completed':
        return '분석 완료';
      case 'failed':
        return '분석 실패';
      default:
        return '알 수 없음';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'queued':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
```

## 📊 Phase 2: 고급 기능 및 최적화

### 1. Spot Instance 활용으로 비용 90% 절약

```yaml
# CloudFormation 템플릿에 추가
MixedInstancesPolicy:
  LaunchTemplate:
    LaunchTemplateSpecification:
      LaunchTemplateId: !Ref LaunchTemplate
      Version: !GetAtt LaunchTemplate.LatestVersionNumber
  InstancesDistribution:
    OnDemandPercentage: 20  # 20%는 On-Demand
    SpotAllocationStrategy: diversified
    SpotInstancePools: 3
    SpotMaxPrice: '0.10'  # 시간당 최대 $0.10
```

### 2. GPU 인스턴스 활용 (고성능 분석)

```yaml
# g4dn.xlarge 인스턴스 타입 사용
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    # NVIDIA 드라이버 설치
    yum install -y gcc kernel-devel-$(uname -r)

    # CUDA 설치
    wget https://developer.download.nvidia.com/compute/cuda/repos/amzn2/x86_64/cuda-repo-amzn2-10.2.89-1.noarch.rpm
    rpm -i cuda-repo-amzn2-10.2.89-1.noarch.rpm
    yum clean all
    yum install -y cuda

    # GPU 가속 MediaPipe 설치
    pip3 install mediapipe-gpu
```

### 3. Docker 컨테이너 기반 배포 (선택사항)

#### Dockerfile
```dockerfile
FROM nvidia/cuda:11.8-runtime-ubuntu20.04

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# 애플리케이션 디렉토리
WORKDIR /app

# Python 의존성 설치
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사
COPY . .

# 실행
CMD ["python3", "worker.py"]
```

## 📈 모니터링 및 운영

### 1. CloudWatch 대시보드

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/SQS", "ApproximateNumberOfMessages", "QueueName", "ec2-video-analysis-video-analysis-queue" ],
          [ "AWS/SQS", "NumberOfMessagesSent", "QueueName", "ec2-video-analysis-video-analysis-queue" ],
          [ "AWS/SQS", "NumberOfMessagesDeleted", "QueueName", "ec2-video-analysis-video-analysis-queue" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-2",
        "title": "SQS Queue Metrics",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "ec2-video-analysis-asg" ],
          [ "AWS/EC2", "NetworkIn", "AutoScalingGroupName", "ec2-video-analysis-asg" ],
          [ "AWS/EC2", "NetworkOut", "AutoScalingGroupName", "ec2-video-analysis-asg" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-2",
        "title": "EC2 Metrics"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/var/log/video-analysis-worker.log'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 50",
        "region": "ap-northeast-2",
        "title": "Recent Errors"
      }
    }
  ]
}
```

### 2. 알람 설정

```bash
# 큐 백로그 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2VideoAnalysis-Queue-Backlog" \
    --alarm-description "SQS queue has too many messages" \
    --metric-name ApproximateNumberOfMessages \
    --namespace AWS/SQS \
    --statistic Average \
    --period 300 \
    --threshold 20 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=QueueName,Value=ec2-video-analysis-video-analysis-queue \
    --evaluation-periods 2

# EC2 CPU 사용률 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2VideoAnalysis-High-CPU" \
    --alarm-description "EC2 instances have high CPU usage" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=AutoScalingGroupName,Value=ec2-video-analysis-asg \
    --evaluation-periods 3
```

## 💰 비용 최적화 전략

### 1. Instance 타입별 비용 비교 (ap-northeast-2 기준)

| 인스턴스 타입 | vCPU | 메모리 | 시간당 비용 | 월 비용 (24시간) | 처리 성능 |
|--------------|------|---------|-------------|------------------|-----------|
| t3.medium    | 2    | 4GB     | $0.0416     | $29.95          | 기본      |
| t3.large     | 2    | 8GB     | $0.0832     | $59.90          | 권장      |
| c5.large     | 2    | 4GB     | $0.085      | $61.20          | 고성능    |
| c5.xlarge    | 4    | 8GB     | $0.17       | $122.40         | 고성능+   |
| g4dn.xlarge  | 4    | 16GB    | $0.526      | $378.72         | GPU 가속  |

### 2. Spot Instance 할인율

- **On-Demand 대비 90% 할인** 가능
- t3.large Spot: ~$0.008/시간 (95% 할인)
- 안정성을 위해 20% On-Demand + 80% Spot 혼용 권장

### 3. Reserved Instance 장기 할인

- **1년 예약**: 40% 할인
- **3년 예약**: 60% 할인
- 안정적인 워크로드에 적합

## 🔧 트러블슈팅 가이드

### 자주 발생하는 문제

1. **MediaPipe 설치 실패**
   ```bash
   # 시스템 패키지 설치 후 재시도
   sudo yum install -y mesa-libGL libgomp gcc gcc-c++
   pip3 install --upgrade pip
   pip3 install mediapipe
   ```

2. **메모리 부족 오류**
   ```bash
   # 스왑 메모리 추가
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. **SQS 메시지 수신 실패**
   ```bash
   # IAM 권한 확인
   aws sts get-caller-identity
   aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All
   ```

4. **Auto Scaling 동작하지 않음**
   ```bash
   # CloudWatch 메트릭 확인
   aws cloudwatch get-metric-statistics \
       --namespace AWS/SQS \
       --metric-name ApproximateNumberOfMessages \
       --dimensions Name=QueueName,Value=queue-name \
       --start-time 2024-01-01T00:00:00Z \
       --end-time 2024-01-01T01:00:00Z \
       --period 300 \
       --statistics Average
   ```

## 📋 배포 체크리스트

### 사전 준비
- [ ] AWS CLI 설치 및 설정
- [ ] EC2 Key Pair 생성
- [ ] VPC 및 서브넷 확인
- [ ] IAM 권한 설정

### 배포 과정
- [ ] CloudFormation 스택 배포
- [ ] Auto Scaling Group 정상 동작 확인
- [ ] SQS 큐 생성 및 권한 설정
- [ ] DynamoDB 테이블 생성 확인
- [ ] 애플리케이션 코드 배포
- [ ] 시스템 서비스 등록 및 시작

### 배포 후 검증
- [ ] EC2 인스턴스 정상 시작 확인
- [ ] 워커 프로세스 실행 상태 확인
- [ ] SQS 메시지 수신 테스트
- [ ] 샘플 영상으로 전체 플로우 테스트
- [ ] CloudWatch 로그 정상 생성 확인
- [ ] Auto Scaling 동작 테스트

### 모니터링 설정
- [ ] CloudWatch 대시보드 구성
- [ ] 알람 설정 및 테스트
- [ ] 로그 회전 설정
- [ ] 백업 정책 수립

---

## 🚀 마이그레이션 전략

### Phase 1: Pilot 테스트 (1-2주)
- 단일 인스턴스로 기본 기능 검증
- 기존 Lambda 시스템과 병렬 운영
- 소량의 테스트 트래픽으로 검증

### Phase 2: 점진적 마이그레이션 (2-4주)
- Auto Scaling 적용
- 트래픽의 50% EC2로 이전
- 성능 및 비용 모니터링

### Phase 3: 완전 마이그레이션 (1-2주)
- 모든 트래픽 EC2로 이전
- Lambda 시스템 단계적 제거
- 최적화 및 튜닝

### Phase 4: 고도화 (지속적)
- Spot Instance 적용
- GPU 인스턴스 테스트
- ML 모델 최적화
- 비용 최적화 지속

이 EC2 방식으로 현재의 모든 제약사항을 해결하고, 더 나은 성능과 비용 효율성을 달성할 수 있습니다! 🎉