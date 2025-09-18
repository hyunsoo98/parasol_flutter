# 🔥 Firebase + AWS 하이브리드 아키텍처

## 🎯 **현재 상황 분석**

### **Firebase 사용 중인 부분**
- ✅ **사용자 인증**: 전화번호 로그인
- ✅ **사용자 관리**: Firebase Auth
- ❓ **데이터 저장**: Firestore 사용 여부 확인 필요

### **AWS로 이전할 부분**
- 🎯 **분석 처리**: Lambda 함수들 (eye/finger/voice)
- 🎯 **파일 저장**: S3 버킷
- 🎯 **API 관리**: API Gateway
- 🎯 **분석 결과**: DynamoDB

## 🏗️ **하이브리드 아키텍처 설계**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               FIREBASE + AWS 하이브리드                                  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                  │    │                 │    │                 │
│  Flutter App    │───▶│  Firebase Auth   │    │  AWS API        │───▶│  AWS Lambda     │
│                 │    │  (전화번호 로그인)  │    │  Gateway        │    │  (분석 처리)     │
│                 │    │                  │    │                 │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │                       │
        │                       │                       ▼                       ▼
        │                       │              ┌─────────────────┐    ┌─────────────────┐
        │                       │              │  DynamoDB       │    │  S3 Bucket      │
        │                       │              │  (분석 결과)     │    │  (파일 저장)     │
        │                       │              └─────────────────┘    └─────────────────┘
        │                       │
        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│  Firestore      │    │  Firebase Token  │
│  (사용자 프로필)   │    │  → AWS 인증     │
└─────────────────┘    └──────────────────┘
```

## 🔐 **인증 통합 방식**

### **Option 1: Firebase Token을 AWS에 전달 (추천)**
```dart
class AuthService {
  // Firebase 토큰 가져오기
  Future<String> getFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken();
    }
    throw Exception('사용자가 로그인하지 않음');
  }

  // AWS API 호출 시 Firebase 토큰 사용
  Future<http.Response> callAwsApi(String endpoint, Map<String, dynamic> data) async {
    final token = await getFirebaseToken();

    return await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Firebase 토큰
      },
      body: jsonEncode(data),
    );
  }
}
```

### **Option 2: Firebase UID를 사용자 ID로 사용**
```dart
class AnalysisService {
  Future<String> startAnalysis({
    required String analysisType,
    required File file,
    Map<String, dynamic>? parameters,
  }) async {
    // Firebase 사용자 UID 사용
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';

    final body = {
      'analysis_type': analysisType,
      'user_id': userId, // Firebase UID 사용
      'video_data': base64Video,
      'parameters': parameters ?? {},
    };

    final response = await http.post(
      Uri.parse('$awsApiUrl/api/v1/upload'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    return jsonDecode(response.body)['analysis_id'];
  }
}
```

## 🎯 **사용자 데이터 관리**

### **Firebase에서 관리**
```dart
// 사용자 프로필, 설정 등
class UserProfile {
  final String uid;
  final String phoneNumber;
  final String name;
  final DateTime createdAt;
  final Map<String, dynamic> settings;

  // Firestore에 저장
  Future<void> saveToFirestore() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(toMap());
  }
}
```

### **AWS에서 관리**
```dart
// 분석 기록, 의료 데이터 등
class AnalysisRecord {
  final String analysisId;
  final String userId; // Firebase UID
  final String analysisType;
  final DateTime timestamp;
  final Map<String, dynamic> results;

  // DynamoDB에 저장 (Lambda에서 처리)
}
```

## 🔄 **수정된 Flutter 앱 구조**

### **서비스 분리**
```dart
// Firebase 관련
class AuthService {
  FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> signInWithPhone(String phoneNumber) async {
    // 기존 Firebase 인증 로직
  }

  User? get currentUser => _auth.currentUser;
  String? get userId => _auth.currentUser?.uid;
}

class UserProfileService {
  FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<UserProfile?> getUserProfile(String uid) async {
    // Firestore에서 사용자 프로필 조회
  }
}

// AWS 관련
class AnalysisService {
  static const String awsApiUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  Future<String> startAnalysis(...) async {
    // AWS API 호출
  }

  Future<Map<String, dynamic>> getAnalysisResult(String analysisId) async {
    // AWS에서 결과 조회
  }
}
```

## 🚀 **업데이트된 TODO 리스트**

Firebase와 AWS 통합을 고려한 수정된 단계:

1. **Firebase 현황 확인** ← 현재 단계
2. **AWS 인프라 배포** (Firebase UID 고려)
3. **API Gateway에서 Firebase 토큰 검증** (선택사항)
4. **Flutter 앱에서 하이브리드 서비스 구현**
5. **테스트 및 검증**

## 🤔 **확인이 필요한 사항**

1. **현재 Firebase 사용 범위**:
   - Firestore 사용하고 있나요?
   - Firebase Storage 사용하고 있나요?
   - Firebase Cloud Functions 사용하고 있나요?

2. **사용자 데이터**:
   - 사용자 프로필은 어디에 저장되어 있나요?
   - 기존 분석 결과는 어디에 저장되어 있나요?

3. **인증 방식**:
   - AWS API에 Firebase 토큰 검증을 추가할지
   - 단순히 Firebase UID만 사용할지

**현재 Firebase 사용 범위를 알려주시면 최적화된 하이브리드 구조를 설계하겠습니다!** 🎯