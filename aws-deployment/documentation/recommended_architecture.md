# 🏗️ AWS Lambda Eye Tracking 권장 아키텍처

## 📊 분석 결과: 하이브리드 아키텍처가 최적

### 🔍 eye.py 분석 요약
- **처리 시간**: 비디오 분석 시 1-5분 소요 예상
- **메모리 사용**: MediaPipe + OpenCV로 높은 메모리 요구
- **Firebase 연동**: 기존 코드가 Firebase에 의존

### ⚡ 권장 솔루션: 단계별 하이브리드

## 1️⃣ 1단계: 동기 패턴 (빠른 구현)

### 장점
✅ **구현 간단**: 기존 FastAPI 코드 거의 그대로 사용  
✅ **테스트 용이**: API Gateway 테스트 이벤트로 바로 확인  
✅ **실시간 응답**: Flutter에서 즉시 결과 받기  

### 제약사항  
❌ **29초 제한**: API Gateway timeout  
❌ **6MB 제한**: Lambda payload 크기  
❌ **높은 비용**: 대기시간 동안 과금  

### 구현 방법
```python
# lambda_eye_sync.py
import json
import base64
from eye_analysis import analyze_frame, process_video_sync

def lambda_handler(event, context):
    try:
        # API Gateway에서 오는 데이터
        body = json.loads(event['body'])
        video_data = base64.b64decode(body['video_data'])
        
        # 짧은 비디오만 처리 (10초 이하)
        if len(video_data) > 5 * 1024 * 1024:  # 5MB
            return {
                'statusCode': 400,
                'body': json.dumps({'error': '파일이 너무 큽니다'})
            }
        
        # 동기 분석 실행
        result = process_video_sync(video_data, max_duration=10)
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(result)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

## 2️⃣ 2단계: 비동기 패턴 (완전한 솔루션)

### 장점
✅ **긴 처리시간**: 15분까지 가능  
✅ **큰 파일**: S3 업로드 후 처리  
✅ **비용 효율**: 실제 처리시간만 과금  
✅ **확장성**: 동시 여러 요청 처리  

### 아키텍처 구성
```
Flutter App → API Gateway → Lambda (Upload) → S3
                                    ↓
                                   SQS → Lambda (Process) → DynamoDB
                                    ↓
Flutter App ← API Gateway ← Lambda (Status Check) ← DynamoDB
```

### 구현 방법

#### 1) 업로드 Lambda
```python
# lambda_upload.py
import boto3
import json
import uuid

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        # 파일을 S3에 업로드
        file_data = base64.b64decode(event['body']['file_data'])
        analysis_id = str(uuid.uuid4())
        s3_key = f"videos/{analysis_id}.mp4"
        
        s3.put_object(
            Bucket='eye-tracking-bucket',
            Key=s3_key,
            Body=file_data
        )
        
        # SQS에 처리 요청
        sqs.send_message(
            QueueUrl='eye-tracking-queue',
            MessageBody=json.dumps({
                'analysis_id': analysis_id,
                's3_key': s3_key,
                'user_id': event['body']['user_id']
            })
        )
        
        return {
            'statusCode': 202,
            'body': json.dumps({
                'analysis_id': analysis_id,
                'status': 'processing'
            })
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
```

#### 2) 처리 Lambda
```python
# lambda_process.py
import boto3
import json
from eye_analysis import process_video_full

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('eye-tracking-results')

def lambda_handler(event, context):
    for record in event['Records']:
        try:
            message = json.loads(record['body'])
            analysis_id = message['analysis_id']
            s3_key = message['s3_key']
            
            # S3에서 비디오 다운로드
            video_data = s3.get_object(Bucket='eye-tracking-bucket', Key=s3_key)['Body'].read()
            
            # 완전한 분석 실행 (15분까지 가능)
            result = process_video_full(video_data)
            
            # 결과를 DynamoDB에 저장
            table.put_item(Item={
                'analysis_id': analysis_id,
                'status': 'completed',
                'result': result,
                'timestamp': int(time.time())
            })
            
        except Exception as e:
            # 실패 시 상태 업데이트
            table.put_item(Item={
                'analysis_id': analysis_id,
                'status': 'failed',
                'error': str(e),
                'timestamp': int(time.time())
            })
```

#### 3) 상태 확인 Lambda
```python
# lambda_status.py
import boto3
import json

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('eye-tracking-results')

def lambda_handler(event, context):
    try:
        analysis_id = event['pathParameters']['analysis_id']
        
        response = table.get_item(Key={'analysis_id': analysis_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Analysis not found'})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response['Item'])
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
```

## 3️⃣ Flutter 앱 적응

### 동기 패턴용
```dart
class SyncEyeTrackingService {
  static Future<Map<String, dynamic>> analyzeShortVideo(File video) async {
    final bytes = await video.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('파일이 너무 큽니다 (5MB 제한)');
    }
    
    final response = await http.post(
      Uri.parse('$API_URL/analyze-sync'),
      body: jsonEncode({'video_data': base64Encode(bytes)}),
    );
    
    return jsonDecode(response.body);
  }
}
```

### 비동기 패턴용
```dart
class AsyncEyeTrackingService {
  static Future<String> startAnalysis(File video) async {
    // 1단계: 업로드 및 분석 시작
    final bytes = await video.readAsBytes();
    final response = await http.post(
      Uri.parse('$API_URL/analyze-async'),
      body: jsonEncode({'video_data': base64Encode(bytes)}),
    );
    final result = jsonDecode(response.body);
    return result['analysis_id'];
  }
  
  static Future<Map<String, dynamic>> getStatus(String analysisId) async {
    // 2단계: 상태 확인
    final response = await http.get(
      Uri.parse('$API_URL/status/$analysisId'),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> waitForResult(String analysisId) async {
    // 3단계: 폴링으로 완료 대기
    while (true) {
      final status = await getStatus(analysisId);
      if (status['status'] == 'completed') {
        return status['result'];
      } else if (status['status'] == 'failed') {
        throw Exception(status['error']);
      }
      await Future.delayed(Duration(seconds: 5)); // 5초마다 체크
    }
  }
}
```

## 🎯 단계별 구현 권장

### Phase 1: 동기 패턴으로 시작 (1-2일)
1. **기존 eye.py를 Lambda로 포팅**
2. **API Gateway 연결**
3. **짧은 비디오 (10초 이하) 테스트**
4. **Flutter에서 즉시 결과 확인**

```bash
# 테스트 이벤트 설정
{
  "body": "{\"video_data\":\"base64_encoded_video\",\"user_id\":\"test\"}",
  "httpMethod": "POST"
}
```

### Phase 2: 비동기 패턴으로 확장 (3-5일)
1. **SQS + DynamoDB 설정**
2. **3개 Lambda 함수 배포**
3. **긴 비디오 처리 테스트**
4. **Flutter 폴링 로직 구현**

## 🚀 즉시 시작 가능한 방법

**가장 빠른 구현: 동기 패턴**
```python
# 기존 eye.py 함수들을 그대로 사용
from eye import analyze_frame, process_eye_video

def lambda_handler(event, context):
    # eye.py의 기존 로직을 Lambda 환경에 맞게 간단 수정
    return process_eye_video(event)
```

결론: **동기 패턴으로 빠르게 프로토타입을 만들고, 필요시 비동기로 확장**하는 것이 가장 실용적입니다! 🎉