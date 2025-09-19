# 비동기 영상 분석 시스템 구축 가이드

## 📋 개요

실시간 영상 분석의 한계를 해결하고 사용자 경험을 개선하기 위한 비동기 영상 분석 시스템 구축 가이드입니다.

### 현재 방식의 문제점
- 실시간 처리로 인한 Lambda 15분 타임아웃 위험
- API Gateway 29초 제한으로 긴 영상 처리 불가
- 큰 영상 파일의 Base64 인코딩/디코딩 오버헤드
- 사용자가 분석 완료까지 대기해야 하는 UX 문제
- 네트워크 불안정 시 전체 프로세스 실패

### 비동기 방식의 장점
- **즉시 응답**: 업로드 후 바로 분석 ID 반환
- **안정성**: SQS를 통한 메시지 큐 시스템으로 실패 시 재시도
- **확장성**: 여러 영상을 동시에 큐에서 처리
- **비용 효율**: 실제 처리 시간만 과금
- **UX 개선**: 진행률 표시 및 백그라운드 처리

## 🏗️ 시스템 아키텍처

```
Flutter App
    ↓ (1) 영상 업로드
   S3 Bucket
    ↓ (2) S3 Event Trigger
  SQS Queue
    ↓ (3) Lambda Trigger
Lambda Function (비동기 분석)
    ↓ (4) 결과 저장
 DynamoDB
    ↓ (5) 상태 조회
Flutter App (폴링/웹소켓)
```

### 구성 요소
1. **S3 Bucket**: 영상 파일 저장
2. **SQS Queue**: 분석 작업 대기열
3. **Lambda Functions**: 비동기 분석 처리
4. **DynamoDB**: 분석 상태 및 결과 저장
5. **SNS** (선택): 완료 알림

## 📁 프로젝트 구조

```
aws-deployment/
├── lambda-functions/
│   ├── lambda-upload-handler/          # 업로드 처리
│   │   ├── lambda_function.py
│   │   └── requirements.txt
│   ├── lambda-eye-process-async/       # 비동기 분석
│   │   ├── lambda_function.py
│   │   ├── lambda_eye_process.py       # 기존 분석 로직
│   │   └── requirements.txt
│   └── lambda-status-checker/          # 상태 조회
│       ├── lambda_function.py
│       └── requirements.txt
├── cloudformation/
│   └── async-video-analysis-stack.yaml
└── flutter-integration/
    ├── async_analysis_service.dart
    └── progress_widget.dart
```

## 🚀 구현 단계

### 1. AWS 인프라 구성

#### CloudFormation 템플릿 생성

```yaml
# cloudformation/async-video-analysis-stack.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Async Video Analysis Infrastructure'

Parameters:
  BucketName:
    Type: String
    Default: 'parkinson-video-analysis'

Resources:
  # S3 버킷 - 영상 저장
  VideoBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      NotificationConfiguration:
        QueueConfigurations:
          - Event: s3:ObjectCreated:*
            Queue: !GetAtt AnalysisQueue.Arn
            Filter:
              S3Key:
                Rules:
                  - Name: prefix
                    Value: videos/
                  - Name: suffix
                    Value: .mp4

  # SQS 큐 - 분석 작업 대기열
  AnalysisQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: video-analysis-queue
      VisibilityTimeoutSeconds: 900  # Lambda 타임아웃과 맞춤
      MessageRetentionPeriod: 1209600  # 14일
      ReddrivePolicy:
        deadLetterTargetArn: !GetAtt DeadLetterQueue.Arn
        maxReceiveCount: 3

  # 데드 레터 큐
  DeadLetterQueue:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: video-analysis-dlq
      MessageRetentionPeriod: 1209600

  # SQS 정책 - S3가 메시지 발송할 수 있도록 허용
  QueuePolicy:
    Type: AWS::SQS::QueuePolicy
    Properties:
      Queues:
        - !Ref AnalysisQueue
      PolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: s3.amazonaws.com
            Action: sqs:SendMessage
            Resource: !GetAtt AnalysisQueue.Arn
            Condition:
              ArnEquals:
                aws:SourceArn: !Sub "${VideoBucket}/*"

  # DynamoDB 테이블 - 분석 상태 저장
  AnalysisStatusTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: video-analysis-status
      AttributeDefinitions:
        - AttributeName: analysisId
          AttributeType: S
        - AttributeName: userId
          AttributeType: S
      KeySchema:
        - AttributeName: analysisId
          KeyType: HASH
      GlobalSecondaryIndexes:
        - IndexName: UserIndex
          KeySchema:
            - AttributeName: userId
              KeyType: HASH
          Projection:
            ProjectionType: ALL
          BillingMode: PAY_PER_REQUEST
      BillingMode: PAY_PER_REQUEST

  # Lambda 실행 역할
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: VideoAnalysisPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                Resource: !Sub "${VideoBucket}/*"
              - Effect: Allow
                Action:
                  - sqs:ReceiveMessage
                  - sqs:DeleteMessage
                  - sqs:GetQueueAttributes
                Resource: !GetAtt AnalysisQueue.Arn
              - Effect: Allow
                Action:
                  - dynamodb:PutItem
                  - dynamodb:GetItem
                  - dynamodb:UpdateItem
                  - dynamodb:Query
                Resource:
                  - !GetAtt AnalysisStatusTable.Arn
                  - !Sub "${AnalysisStatusTable.Arn}/index/*"

  # 비동기 분석 Lambda 함수
  AsyncAnalysisFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: async-video-analysis
      Runtime: python3.11
      Handler: lambda_function.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def lambda_handler(event, context):
              return {'statusCode': 200, 'body': 'Placeholder'}
      Timeout: 900
      MemorySize: 3008
      Environment:
        Variables:
          S3_BUCKET: !Ref VideoBucket
          DYNAMODB_TABLE: !Ref AnalysisStatusTable

  # SQS 이벤트 소스 매핑
  SQSEventSourceMapping:
    Type: AWS::Lambda::EventSourceMapping
    Properties:
      EventSourceArn: !GetAtt AnalysisQueue.Arn
      FunctionName: !Ref AsyncAnalysisFunction
      BatchSize: 1
      MaximumBatchingWindowInSeconds: 5

  # 상태 조회 Lambda 함수
  StatusCheckerFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: video-analysis-status
      Runtime: python3.11
      Handler: lambda_function.lambda_handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def lambda_handler(event, context):
              return {'statusCode': 200, 'body': 'Placeholder'}
      Timeout: 30
      MemorySize: 512
      Environment:
        Variables:
          DYNAMODB_TABLE: !Ref AnalysisStatusTable

Outputs:
  BucketName:
    Description: S3 Bucket for video storage
    Value: !Ref VideoBucket
    Export:
      Name: !Sub "${AWS::StackName}-BucketName"

  QueueUrl:
    Description: SQS Queue URL
    Value: !Ref AnalysisQueue
    Export:
      Name: !Sub "${AWS::StackName}-QueueUrl"

  TableName:
    Description: DynamoDB Table Name
    Value: !Ref AnalysisStatusTable
    Export:
      Name: !Sub "${AWS::StackName}-TableName"
```

### 2. Lambda 함수 구현

#### A. 비동기 분석 Lambda (lambda-eye-process-async/lambda_function.py)

```python
import json
import boto3
import base64
import uuid
import traceback
from datetime import datetime
from lambda_eye_process import lambda_handler as process_video

# AWS 서비스 클라이언트
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('video-analysis-status')

def lambda_handler(event, context):
    """
    SQS 메시지를 받아 비동기로 영상 분석 수행
    """
    try:
        for record in event['Records']:
            # SQS 메시지 파싱
            s3_event = json.loads(record['body'])

            # S3 이벤트에서 버킷과 키 추출
            bucket = s3_event['Records'][0]['s3']['bucket']['name']
            key = s3_event['Records'][0]['s3']['object']['key']

            # 분석 ID 추출 (파일 경로에서)
            # 예: videos/user123/analysis456/video.mp4 -> analysis456
            path_parts = key.split('/')
            analysis_id = path_parts[2] if len(path_parts) > 2 else str(uuid.uuid4())
            user_id = path_parts[1] if len(path_parts) > 1 else 'anonymous'

            print(f"Processing video analysis: {analysis_id}")

            # 상태를 processing으로 업데이트
            update_status(analysis_id, user_id, 'processing', 0)

            # S3에서 영상 다운로드
            video_data = download_from_s3(bucket, key)

            # 진행률 업데이트
            update_status(analysis_id, user_id, 'processing', 25)

            # Base64 인코딩하여 기존 분석 함수 호출
            video_base64 = base64.b64encode(video_data).decode('utf-8')

            analysis_event = {
                'action': 'analyze_video',
                'file_data': video_base64,
                'user_id': user_id,
                'parameters': {
                    'step': 1,
                    'vpp_thresh': 0.06,
                    'blink_thresh': 0.18,
                    'max_frames': 12000
                }
            }

            # 진행률 업데이트
            update_status(analysis_id, user_id, 'processing', 50)

            # 기존 분석 로직 실행
            result = process_video(analysis_event, context)

            if result['statusCode'] == 200:
                analysis_data = json.loads(result['body'])

                # 분석 완료 상태로 업데이트
                update_status(
                    analysis_id,
                    user_id,
                    'completed',
                    100,
                    analysis_data
                )

                print(f"Analysis completed successfully: {analysis_id}")
            else:
                # 분석 실패
                error_data = json.loads(result['body'])
                update_status(
                    analysis_id,
                    user_id,
                    'failed',
                    0,
                    {'error': error_data.get('error', 'Unknown error')}
                )
                print(f"Analysis failed: {analysis_id}, Error: {error_data}")

    except Exception as e:
        print(f"Error processing SQS message: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")

        # 실패 상태로 업데이트
        try:
            update_status(analysis_id, user_id, 'failed', 0, {'error': str(e)})
        except:
            pass

        raise e

def download_from_s3(bucket, key):
    """S3에서 파일 다운로드"""
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        return response['Body'].read()
    except Exception as e:
        raise Exception(f"S3 download failed: {str(e)}")

def update_status(analysis_id, user_id, status, progress, result_data=None):
    """DynamoDB에 상태 업데이트"""
    try:
        item = {
            'analysisId': analysis_id,
            'userId': user_id,
            'status': status,
            'progress': progress,
            'updatedAt': int(datetime.now().timestamp()),
            'testType': 'eye-tracking'
        }

        if result_data:
            item['results'] = result_data

        table.put_item(Item=item)

    except Exception as e:
        print(f"DynamoDB update failed: {str(e)}")
        raise e
```

#### B. 상태 조회 Lambda (lambda-status-checker/lambda_function.py)

```python
import json
import boto3
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('video-analysis-status')

def lambda_handler(event, context):
    """
    분석 상태 및 결과 조회 API
    """
    try:
        # CORS 헤더
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }

        # OPTIONS 요청 처리
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'OK'})
            }

        # 경로에서 analysis_id 추출
        analysis_id = event['pathParameters']['analysis_id'] if event.get('pathParameters') else None

        if not analysis_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing analysis_id'})
            }

        # DynamoDB에서 상태 조회
        response = table.get_item(
            Key={'analysisId': analysis_id}
        )

        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Analysis not found'})
            }

        item = response['Item']

        # Decimal을 float로 변환
        def decimal_to_float(obj):
            if isinstance(obj, Decimal):
                return float(obj)
            elif isinstance(obj, dict):
                return {k: decimal_to_float(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [decimal_to_float(i) for i in obj]
            return obj

        result = decimal_to_float(item)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(result)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }

def list_user_analyses(event, context):
    """
    사용자의 모든 분석 목록 조회
    """
    try:
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }

        user_id = event['pathParameters']['user_id'] if event.get('pathParameters') else None

        if not user_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing user_id'})
            }

        # GSI를 사용하여 사용자별 분석 목록 조회
        response = table.query(
            IndexName='UserIndex',
            KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(user_id),
            ScanIndexForward=False  # 최신 순 정렬
        )

        analyses = []
        for item in response['Items']:
            analyses.append({
                'analysisId': item['analysisId'],
                'status': item['status'],
                'progress': float(item.get('progress', 0)),
                'updatedAt': int(item['updatedAt']),
                'testType': item.get('testType', 'eye-tracking')
            })

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'analyses': analyses,
                'count': len(analyses)
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }
```

### 3. Flutter 클라이언트 구현

#### A. 비동기 분석 서비스 (flutter-integration/async_analysis_service.dart)

```dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:aws_s3_upload/aws_s3_upload.dart';

class AsyncAnalysisService {
  static const String baseUrl = 'https://your-api-gateway-url';
  static const String s3Bucket = 'parkinson-video-analysis';
  static const String awsRegion = 'ap-northeast-2';

  /// 영상 업로드 및 분석 요청
  Future<String> startVideoAnalysis(File videoFile, String userId) async {
    try {
      // 1. 분석 ID 생성
      String analysisId = Uuid().v4();

      // 2. S3에 영상 업로드
      String s3Key = 'videos/$userId/$analysisId/${videoFile.path.split('/').last}';

      await _uploadToS3(videoFile, s3Key);

      // 3. 분석 상태 초기화 (DynamoDB)
      await _initializeAnalysisStatus(analysisId, userId);

      print('Video uploaded successfully. Analysis ID: $analysisId');
      return analysisId;

    } catch (e) {
      throw Exception('Failed to start video analysis: $e');
    }
  }

  /// S3에 파일 업로드 (Presigned URL 사용)
  Future<void> _uploadToS3(File videoFile, String s3Key) async {
    try {
      // Presigned URL 요청
      final presignedUrl = await _getPresignedUrl(s3Key);

      // 파일 업로드
      final bytes = await videoFile.readAsBytes();

      final response = await http.put(
        Uri.parse(presignedUrl),
        body: bytes,
        headers: {
          'Content-Type': 'video/mp4',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('S3 upload failed: ${response.statusCode}');
      }

    } catch (e) {
      throw Exception('S3 upload error: $e');
    }
  }

  /// Presigned URL 획득
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
      throw Exception('Failed to get presigned URL');
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
        'progress': 0
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to initialize analysis status');
    }
  }

  /// 분석 상태 조회
  Future<AnalysisStatus> getAnalysisStatus(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analysis/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AnalysisStatus.fromJson(data);
      } else if (response.statusCode == 404) {
        throw Exception('Analysis not found');
      } else {
        throw Exception('Failed to get analysis status');
      }

    } catch (e) {
      throw Exception('Status check error: $e');
    }
  }

  /// 사용자의 모든 분석 목록 조회
  Future<List<AnalysisSummary>> getUserAnalyses(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId/analyses'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<AnalysisSummary> analyses = [];

        for (var item in data['analyses']) {
          analyses.add(AnalysisSummary.fromJson(item));
        }

        return analyses;
      } else {
        throw Exception('Failed to get user analyses');
      }

    } catch (e) {
      throw Exception('User analyses error: $e');
    }
  }
}

class AnalysisStatus {
  final String analysisId;
  final String userId;
  final String status; // queued, processing, completed, failed
  final double progress; // 0-100
  final DateTime updatedAt;
  final Map<String, dynamic>? results;
  final String? error;

  AnalysisStatus({
    required this.analysisId,
    required this.userId,
    required this.status,
    required this.progress,
    required this.updatedAt,
    this.results,
    this.error,
  });

  factory AnalysisStatus.fromJson(Map<String, dynamic> json) {
    return AnalysisStatus(
      analysisId: json['analysisId'],
      userId: json['userId'],
      status: json['status'],
      progress: json['progress'].toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] * 1000),
      results: json['results'],
      error: json['results']?['error'],
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing';
  bool get isQueued => status == 'queued';
}

class AnalysisSummary {
  final String analysisId;
  final String status;
  final double progress;
  final DateTime updatedAt;
  final String testType;

  AnalysisSummary({
    required this.analysisId,
    required this.status,
    required this.progress,
    required this.updatedAt,
    required this.testType,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) {
    return AnalysisSummary(
      analysisId: json['analysisId'],
      status: json['status'],
      progress: json['progress'].toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] * 1000),
      testType: json['testType'],
    );
  }
}
```

#### B. 진행률 표시 위젯 (flutter-integration/progress_widget.dart)

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'async_analysis_service.dart';

class AnalysisProgressWidget extends StatefulWidget {
  final String analysisId;
  final VoidCallback? onCompleted;
  final Function(String)? onError;

  const AnalysisProgressWidget({
    Key? key,
    required this.analysisId,
    this.onCompleted,
    this.onError,
  }) : super(key: key);

  @override
  _AnalysisProgressWidgetState createState() => _AnalysisProgressWidgetState();
}

class _AnalysisProgressWidgetState extends State<AnalysisProgressWidget> {
  final AsyncAnalysisService _service = AsyncAnalysisService();
  Timer? _timer;

  double _progress = 0.0;
  String _status = 'queued';
  String _statusMessage = '분석 대기 중...';
  bool _isCompleted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(Duration(seconds: 3), (timer) async {
      try {
        final status = await _service.getAnalysisStatus(widget.analysisId);

        setState(() {
          _progress = status.progress / 100.0;
          _status = status.status;
          _statusMessage = _getStatusMessage(status.status, status.progress);

          if (status.isCompleted) {
            _isCompleted = true;
            timer.cancel();
            widget.onCompleted?.call();
          } else if (status.isFailed) {
            _error = status.error ?? '분석에 실패했습니다';
            timer.cancel();
            widget.onError?.call(_error!);
          }
        });

      } catch (e) {
        print('Status polling error: $e');
        // 에러가 발생해도 계속 폴링 (네트워크 일시 오류일 수 있음)
      }
    });
  }

  String _getStatusMessage(String status, double progress) {
    switch (status) {
      case 'queued':
        return '분석 대기 중...';
      case 'processing':
        if (progress < 25) return '영상 분석 준비 중...';
        if (progress < 50) return '프레임 추출 중...';
        if (progress < 75) return '눈 움직임 분석 중...';
        if (progress < 95) return '결과 계산 중...';
        return '분석 완료 처리 중...';
      case 'completed':
        return '분석 완료!';
      case 'failed':
        return '분석 실패';
      default:
        return '상태 확인 중...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 상태 아이콘
            _buildStatusIcon(),
            SizedBox(height: 16),

            // 진행률 표시
            if (!_isCompleted && _error == null) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _status == 'processing' ? Colors.blue : Colors.orange
                ),
              ),
              SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _status == 'processing' ? Colors.blue : Colors.orange,
                ),
              ),
            ],

            SizedBox(height: 16),

            // 상태 메시지
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 16,
                color: _error != null ? Colors.red : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),

            // 에러 메시지
            if (_error != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            ],

            // 분석 ID 표시
            SizedBox(height: 16),
            Text(
              '분석 ID: ${widget.analysisId.substring(0, 8)}...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (_isCompleted) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check,
          color: Colors.white,
          size: 30,
        ),
      );
    } else if (_error != null) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.error,
          color: Colors.white,
          size: 30,
        ),
      );
    } else {
      return Container(
        width: 60,
        height: 60,
        child: CircularProgressIndicator(
          strokeWidth: 6,
          valueColor: AlwaysStoppedAnimation<Color>(
            _status == 'processing' ? Colors.blue : Colors.orange
          ),
        ),
      );
    }
  }
}

// 사용 예시
class VideoAnalysisScreen extends StatefulWidget {
  @override
  _VideoAnalysisScreenState createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  final AsyncAnalysisService _service = AsyncAnalysisService();
  String? _currentAnalysisId;
  bool _isUploading = false;

  Future<void> _startAnalysis(File videoFile) async {
    setState(() {
      _isUploading = true;
    });

    try {
      String analysisId = await _service.startVideoAnalysis(
        videoFile,
        'user123' // 실제 사용자 ID
      );

      setState(() {
        _currentAnalysisId = analysisId;
        _isUploading = false;
      });

    } catch (e) {
      setState(() {
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('영상 분석')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 업로드 버튼
            if (_currentAnalysisId == null && !_isUploading)
              ElevatedButton(
                onPressed: () => _selectAndUploadVideo(),
                child: Text('영상 선택 및 업로드'),
              ),

            // 업로딩 상태
            if (_isUploading)
              Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('영상 업로드 중...'),
                  ],
                ),
              ),

            // 분석 진행률
            if (_currentAnalysisId != null)
              AnalysisProgressWidget(
                analysisId: _currentAnalysisId!,
                onCompleted: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('분석이 완료되었습니다!')),
                  );
                },
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('분석 실패: $error')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAndUploadVideo() async {
    // 파일 선택 로직 (file_picker 패키지 사용)
    // File videoFile = await FilePicker...
    // await _startAnalysis(videoFile);
  }
}
```

### 4. 배포 스크립트

#### 인프라 배포 스크립트 (deploy_infrastructure.sh)

```bash
#!/bin/bash

# AWS 설정
STACK_NAME="async-video-analysis"
REGION="ap-northeast-2"
BUCKET_NAME="parkinson-video-analysis-$(date +%s)"

echo "🚀 비동기 영상 분석 인프라 배포 시작..."

# 1. CloudFormation 스택 배포
echo "📦 CloudFormation 스택 배포 중..."
aws cloudformation deploy \
    --template-file cloudformation/async-video-analysis-stack.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides BucketName=$BUCKET_NAME \
    --capabilities CAPABILITY_IAM \
    --region $REGION

if [ $? -eq 0 ]; then
    echo "✅ 인프라 배포 완료"
else
    echo "❌ 인프라 배포 실패"
    exit 1
fi

# 2. 스택 출력값 확인
echo "📊 배포된 리소스 정보:"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs' \
    --output table

echo "🎉 배포 완료!"
echo "📝 다음 단계:"
echo "   1. Lambda 함수 코드 업로드"
echo "   2. API Gateway 설정"
echo "   3. Flutter 앱에서 엔드포인트 업데이트"
```

#### Lambda 함수 배포 스크립트 (deploy_lambda_functions.sh)

```bash
#!/bin/bash

REGION="ap-northeast-2"

echo "🚀 Lambda 함수 배포 시작..."

# 1. 비동기 분석 Lambda
echo "📦 비동기 분석 Lambda 배포 중..."
cd lambda-functions/lambda-eye-process-async
zip -r ../async-analysis.zip .
aws lambda update-function-code \
    --function-name async-video-analysis \
    --zip-file fileb://../async-analysis.zip \
    --region $REGION
cd ../..

# 2. 상태 조회 Lambda
echo "📦 상태 조회 Lambda 배포 중..."
cd lambda-functions/lambda-status-checker
zip -r ../status-checker.zip .
aws lambda update-function-code \
    --function-name video-analysis-status \
    --zip-file fileb://../status-checker.zip \
    --region $REGION
cd ../..

# 3. 정리
rm lambda-functions/*.zip

echo "✅ Lambda 함수 배포 완료"
```

## 📊 모니터링 및 운영

### CloudWatch 대시보드 설정

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "async-video-analysis" ],
          [ "AWS/Lambda", "Errors", "FunctionName", "async-video-analysis" ],
          [ "AWS/SQS", "ApproximateNumberOfMessages", "QueueName", "video-analysis-queue" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-2",
        "title": "Video Analysis Metrics"
      }
    }
  ]
}
```

### 알람 설정

```bash
# Lambda 에러 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "VideoAnalysis-Lambda-Errors" \
    --alarm-description "Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=FunctionName,Value=async-video-analysis \
    --evaluation-periods 1

# SQS 메시지 적체 알람
aws cloudwatch put-metric-alarm \
    --alarm-name "VideoAnalysis-Queue-Backlog" \
    --alarm-description "SQS queue backlog" \
    --metric-name ApproximateNumberOfMessages \
    --namespace AWS/SQS \
    --statistic Average \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=QueueName,Value=video-analysis-queue \
    --evaluation-periods 2
```

## 💰 비용 최적화

### 예상 비용 (월 기준)

- **S3 저장**: $0.023/GB (영상 파일)
- **Lambda 실행**: $0.0000166/GB-초
- **SQS 메시지**: $0.40/100만 요청
- **DynamoDB**: $0.25/GB + $0.25/백만 요청
- **CloudWatch**: $0.30/지표/월

### 최적화 방안

1. **S3 Lifecycle 정책** - 오래된 영상 자동 삭제
2. **Lambda Provisioned Concurrency** - Cold Start 최소화
3. **DynamoDB On-Demand** - 사용량에 따른 과금
4. **SQS 배치 처리** - 메시지 처리 효율성 향상

## 🛠️ 트러블슈팅

### 자주 발생하는 문제

1. **Lambda 타임아웃**
   ```bash
   # 타임아웃 15분으로 증가
   aws lambda update-function-configuration \
       --function-name async-video-analysis \
       --timeout 900
   ```

2. **SQS 메시지 처리 실패**
   ```bash
   # Dead Letter Queue 확인
   aws sqs receive-message \
       --queue-url https://sqs.region.amazonaws.com/account/video-analysis-dlq
   ```

3. **S3 업로드 권한 문제**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "s3:PutObject",
         "Resource": "arn:aws:s3:::bucket-name/videos/*"
       }
     ]
   }
   ```

## 📋 배포 체크리스트

### 사전 준비
- [ ] AWS CLI 설치 및 설정
- [ ] CloudFormation 템플릿 검토
- [ ] Lambda 함수 코드 준비
- [ ] Flutter 앱 업데이트

### 배포 과정
- [ ] CloudFormation 스택 배포
- [ ] Lambda 함수 업로드
- [ ] API Gateway 설정
- [ ] 권한 설정 확인
- [ ] 테스트 영상으로 검증

### 배포 후 확인
- [ ] SQS 큐 생성 확인
- [ ] Lambda 함수 정상 작동 확인
- [ ] S3 버킷 접근 권한 확인
- [ ] DynamoDB 테이블 생성 확인
- [ ] CloudWatch 로그 확인

---

**💡 참고**: 이 시스템은 확장 가능하고 안정적인 비동기 영상 분석을 제공합니다. 초기 설정은 복잡하지만, 운영 중에는 높은 안정성과 사용자 경험을 제공합니다.