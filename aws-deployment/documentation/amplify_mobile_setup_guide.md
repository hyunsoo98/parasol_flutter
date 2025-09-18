# 📱 Amplify 모바일 앱 설정 가이드

## 🎯 **Flutter 모바일 앱 + AWS 서버리스 통합**

기존에 구축한 Lambda/API Gateway 백엔드를 Amplify 모바일 앱에 연결합니다.

---

## **📋 Step 1: Amplify CLI 설치 및 초기화**

### **1-1. Amplify CLI 설치**
```bash
npm install -g @aws-amplify/cli

# AWS 계정 설정
amplify configure
```

### **1-2. 프로젝트 초기화**
```bash
cd D:\parkinson

# Amplify 프로젝트 초기화
amplify init
```

**설정 값:**
```
? Enter a name for the project: parkinson-mobile
? Initialize the project with the above configuration? No
? Enter a name for the environment: dev
? Choose your default editor: Visual Studio Code
? Choose the type of app that you're building: flutter
? Where do you want to store your configuration file? ./lib/
? Do you want to use an AWS profile? Yes
? Please choose the profile you want to use: default
```

---

## **🔗 Step 2: 기존 API Gateway 연결**

### **2-1. API 카테고리 추가**
```bash
# 기존 API Gateway를 Amplify에 임포트
amplify import api
```

**설정:**
```
? What type of API would you like to import? REST
? Provide the REST API id: YOUR_API_GATEWAY_ID
? What would you like to name this REST API: parasolApi
? Provide the path you would like to import: /
```

### **2-2. API Gateway ID 찾기**
AWS Console → API Gateway → parasol-api → Settings에서 API ID 확인:
```
예: c7yw4o4948
```

---

## **🔐 Step 3: 인증 설정 (Custom Lambda)**

Amplify는 기본적으로 Cognito를 사용하지만, 우리는 **Custom Lambda 인증**을 사용합니다.

### **3-1. API 호출 설정**
`amplify/backend/api/parasolApi/parameters.json`:
```json
{
    "authRoleName": {
        "Ref": "AuthRoleName"
    },
    "unauthRoleName": {
        "Ref": "UnauthRoleName"
    },
    "authRoleArn": {
        "Ref": "AuthRoleArn"
    },
    "unauthRoleArn": {
        "Ref": "UnauthRoleArn"
    }
}
```

---

## **📦 Step 4: Flutter 의존성 추가**

### **4-1. pubspec.yaml 업데이트**
```yaml
dependencies:
  flutter:
    sdk: flutter

  # AWS Amplify (모바일 앱용)
  amplify_flutter: ^2.0.0
  amplify_api: ^2.0.0
  amplify_storage_s3: ^2.0.0

  # 기존 의존성들 유지
  http: ^1.1.2
  shared_preferences: ^2.2.2
  provider: ^6.1.1
  camera: ^0.10.5+5
  permission_handler: ^11.0.1
  # ... 기타 의존성들
```

### **4-2. 의존성 설치**
```bash
flutter pub get
```

---

## **⚙️ Step 5: Amplify 구성 파일 생성**

### **5-1. amplifyconfiguration.dart 생성**
```bash
# Amplify 구성 파일 생성
amplify codegen models
```

### **5-2. lib/amplifyconfiguration.dart 확인**
이 파일이 자동 생성되어야 합니다:
```dart
const amplifyconfig = '''{
    "api": {
        "plugins": {
            "awsAPIPlugin": {
                "parasolApi": {
                    "endpointType": "REST",
                    "endpoint": "https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod",
                    "region": "us-west-1",
                    "authorizationType": "NONE"
                }
            }
        }
    }
}''';
```

---

## **🔧 Step 6: Flutter 앱 Amplify 초기화**

### **6-1. main.dart 업데이트**
```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

import 'amplifyconfiguration.dart';
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _configureAmplify();
  }

  void _configureAmplify() async {
    try {
      // Amplify 플러그인 추가
      await Amplify.addPlugins([
        AmplifyAPI(),
        AmplifyStorageS3(),
      ]);

      // Amplify 구성
      await Amplify.configure(amplifyconfig);

      print('Successfully configured Amplify 🎉');
    } on AmplifyException catch (e) {
      print('Error configuring Amplify: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CustomAuthProvider(),
      child: MaterialApp(
        title: 'Parasol Parkinson Analysis',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: SplashScreen(),
        routes: {
          '/home': (context) => HomeScreen(),
          '/login': (context) => LoginScreen(),
          // ... 기타 라우트들
        },
      ),
    );
  }
}
```

---

## **🔄 Step 7: Amplify API 서비스 생성**

### **7-1. amplify_api_service.dart 생성**
```dart
// lib/services/amplify_api_service.dart
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';

class AmplifyApiService {
  static final AmplifyApiService _instance = AmplifyApiService._internal();
  factory AmplifyApiService() => _instance;
  AmplifyApiService._internal();

  // === 인증 관련 API ===

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/api/v1/auth/register',
        body: HttpPayload.json({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      final response = await Amplify.API.send(request: request).response;
      final data = response.decodeBody();

      return {
        'success': response.statusCode == 200,
        'data': data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/api/v1/auth/login',
        body: HttpPayload.json({
          'email': email,
          'password': password,
        }),
      );

      final response = await Amplify.API.send(request: request).response;
      final data = response.decodeBody();

      return {
        'success': response.statusCode == 200,
        'data': data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // === 분석 업로드 API ===

  Future<Map<String, dynamic>> uploadAnalysis({
    required String analysisType,
    required String fileData,
    required String userId,
    String? fileName,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/api/v1/upload',
        body: HttpPayload.json({
          'analysis_type': analysisType,
          'file_data': fileData,
          'user_id': userId,
          'file_name': fileName,
          'parameters': parameters ?? {},
        }),
      );

      final response = await Amplify.API.send(request: request).response;
      final data = response.decodeBody();

      return {
        'success': response.statusCode == 200,
        'data': data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // === 상태 조회 API ===

  Future<Map<String, dynamic>> getAnalysisStatus(String analysisId) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.get,
        path: '/api/v1/status/$analysisId',
      );

      final response = await Amplify.API.send(request: request).response;
      final data = response.decodeBody();

      return {
        'success': response.statusCode == 200,
        'data': data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // === 종합 진단 API ===

  Future<Map<String, dynamic>> startComprehensiveDiagnosis({
    required String userId,
    required List<String> analysisIds,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/api/v1/diagnosis/start',
        body: HttpPayload.json({
          'user_id': userId,
          'analysis_ids': analysisIds,
        }),
      );

      final response = await Amplify.API.send(request: request).response;
      final data = response.decodeBody();

      return {
        'success': response.statusCode == 200,
        'data': data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

// 전역 인스턴스
final amplifyApi = AmplifyApiService();
```

---

## **📱 Step 8: 모바일 앱 테스트**

### **8-1. 앱 빌드 및 실행**
```bash
# Android 앱 실행
flutter run

# 또는 iOS 앱 실행 (Mac에서)
flutter run -d ios
```

### **8-2. 테스트 시나리오**
1. **회원가입 테스트**
2. **로그인 테스트**
3. **분석 업로드 테스트**
4. **실시간 진행률 확인**
5. **결과 조회 테스트**

---

## **🔧 Step 9: 프로덕션 배포**

### **9-1. Android APK 빌드**
```bash
flutter build apk --release
```

### **9-2. iOS IPA 빌드** (Mac에서)
```bash
flutter build ios --release
```

### **9-3. 앱스토어 배포**
- **Google Play Store** (Android)
- **Apple App Store** (iOS)

---

## **📊 최종 아키텍처**

```
📱 Flutter Mobile App (Android/iOS)
    ↓ (Amplify API)
🌐 AWS API Gateway (parasol-api)
    ↓
⚡ Lambda Functions
    ├── parasol-login (인증)
    ├── unified-upload (업로드)
    ├── unified-status (상태)
    ├── eye-tracking-process
    ├── finger-tapping-process
    ├── voice-analysis-process
    └── comprehensive-diagnosis
    ↓
📨 SQS Queues → 🗄️ DynamoDB + 📦 S3
```

**이제 완전한 모바일 앱 + AWS 서버리스 시스템입니다!** 📱🚀