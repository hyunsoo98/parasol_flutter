# 🗃️ DynamoDB 최종 설정 가이드

## 📊 **현재 상황 정리**

### **기존 DynamoDB 테이블들 (스크린샷 확인)**
- ✅ **parasol-analysis**: `analysisId (S)` + `testType (S)`
- ✅ **parasol-users**: `userId (S)` + `timestamp (N)`
- ✅ **eye-tracking-results**: `analysisId (S)`
- ✅ **finger-tapping-results**: `analysis_id (S)`
- ✅ **parasol-finger-tapping-results**: `analysisId (S)`

## 🎯 **최종 결정: 단일 테이블 활용**

### **parasol-analysis 테이블만 사용**
```
Primary Key: analysisId (S)
Sort Key: testType (S)
```

## 📋 **데이터 구조 설계**

### **1. 개별 분석 데이터**
```json
{
  "analysisId": "eye_20240917_abc123",
  "testType": "eye-tracking",
  "userId": "user_20240917_abc123",
  "status": "completed",
  "createdAt": "2024-09-17T10:30:00Z",
  "updatedAt": "2024-09-17T10:35:00Z",
  "s3Paths": {
    "input": "eye-tracking/eye_20240917_abc123/video.mp4",
    "result": "eye-tracking/eye_20240917_abc123/result.json"
  },
  "results": {
    "classification": {"pd_probability": 0.78},
    "metrics": {"saccade_count": 234}
  },
  "parameters": {
    "step": 2,
    "vpp_thresh": 0.06,
    "blink_thresh": 0.18
  }
}
```

### **2. 종합 진단 데이터 (같은 테이블)**
```json
{
  "analysisId": "session_20240917_xyz789",
  "testType": "comprehensive-diagnosis",
  "userId": "user_20240917_abc123",
  "status": "completed",
  "createdAt": "2024-09-17T11:00:00Z",
  "updatedAt": "2024-09-17T11:05:00Z",
  "individualAnalyses": {
    "eyeTracking": "eye_20240917_abc123",
    "fingerTapping": "finger_20240917_def456",
    "voiceAnalysis": "voice_20240917_ghi789"
  },
  "comprehensiveResults": {
    "overallScore": 7.17,
    "riskLevel": "high",
    "recommendations": [...]
  }
}
```

## 🔧 **Lambda 함수별 DynamoDB 사용법**

### **1. unified-upload Lambda**
```python
# 새 분석 레코드 생성
def create_analysis_record(analysis_id, test_type, user_id):
    table = dynamodb.Table('parasol-analysis')

    item = {
        'analysisId': analysis_id,
        'testType': test_type,
        'userId': user_id,
        'status': 'uploaded',
        'createdAt': datetime.utcnow().isoformat(),
        'updatedAt': datetime.utcnow().isoformat()
    }

    table.put_item(Item=item)
```

### **2. unified-status Lambda**
```python
# 분석 상태 조회
def get_analysis_status(analysis_id, test_type):
    table = dynamodb.Table('parasol-analysis')

    response = table.get_item(
        Key={
            'analysisId': analysis_id,
            'testType': test_type
        }
    )

    return response.get('Item')

# 사용자별 분석 목록 조회
def get_user_analyses(user_id):
    table = dynamodb.Table('parasol-analysis')

    # GSI 필요 시 추가하거나 Scan 사용
    response = table.scan(
        FilterExpression='userId = :uid',
        ExpressionAttributeValues={':uid': user_id}
    )

    return response['Items']
```

### **3. Processing Lambda들**
```python
# 분석 완료 후 결과 업데이트
def update_analysis_result(analysis_id, test_type, results):
    table = dynamodb.Table('parasol-analysis')

    table.update_item(
        Key={
            'analysisId': analysis_id,
            'testType': test_type
        },
        UpdateExpression='SET #status = :status, #results = :results, #updated = :updated',
        ExpressionAttributeNames={
            '#status': 'status',
            '#results': 'results',
            '#updated': 'updatedAt'
        },
        ExpressionAttributeValues={
            ':status': 'completed',
            ':results': results,
            ':updated': datetime.utcnow().isoformat()
        }
    )
```

### **4. comprehensive-diagnosis Lambda**
```python
# 종합 진단 세션 생성
def create_comprehensive_session(session_id, user_id, analysis_ids):
    table = dynamodb.Table('parasol-analysis')

    item = {
        'analysisId': session_id,
        'testType': 'comprehensive-diagnosis',
        'userId': user_id,
        'status': 'processing',
        'createdAt': datetime.utcnow().isoformat(),
        'individualAnalyses': {
            'eyeTracking': analysis_ids.get('eye'),
            'fingerTapping': analysis_ids.get('finger'),
            'voiceAnalysis': analysis_ids.get('voice')
        }
    }

    table.put_item(Item=item)

# 개별 분석 결과 수집
def collect_individual_results(analysis_ids):
    table = dynamodb.Table('parasol-analysis')
    results = {}

    for test_type, analysis_id in analysis_ids.items():
        response = table.get_item(
            Key={
                'analysisId': analysis_id,
                'testType': test_type
            }
        )
        results[test_type] = response.get('Item', {}).get('results', {})

    return results
```

## 🚀 **Lambda 환경변수 설정**

### **모든 Lambda 함수에서 사용**
```bash
DYNAMODB_TABLE=parasol-analysis
```

## 📊 **분석 ID 네이밍 규칙**

### **개별 분석**
```
eye_20240917_abc123       (testType: "eye-tracking")
finger_20240917_def456    (testType: "finger-tapping")
voice_20240917_ghi789     (testType: "voice-analysis")
```

### **종합 진단**
```
session_20240917_xyz789   (testType: "comprehensive-diagnosis")
```

## ✅ **장점**

1. **단순함**: 테이블 하나만 관리
2. **일관성**: 모든 분석 데이터가 한 곳에
3. **확장성**: 새로운 분석 타입 쉽게 추가
4. **비용 효율**: 테이블 하나만 운영

## 🔧 **필요한 작업**

### **기존 테이블 확인**
```bash
# parasol-analysis 테이블 구조 확인
aws dynamodb describe-table --table-name parasol-analysis --region us-west-1
```

### **GSI 추가 (필요 시)**
사용자별 분석 조회를 위해 GSI 추가:
```json
{
  "IndexName": "user-index",
  "KeySchema": [
    {"AttributeName": "userId", "KeyType": "HASH"},
    {"AttributeName": "createdAt", "KeyType": "RANGE"}
  ]
}
```

**이제 DynamoDB 설정이 명확해졌습니다! parasol-analysis 테이블 하나로 모든 분석과 종합 진단을 처리합니다.** 🎯