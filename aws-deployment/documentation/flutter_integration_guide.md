# 📱 Flutter 통합 가이드

## 🎯 **새로운 통합 아키텍처 적용**

Firebase에서 AWS Lambda 기반 시스템으로 전환하는 완전한 가이드입니다.

---

## **📋 Step 1: 의존성 업데이트**

### **pubspec.yaml 수정**
```yaml
dependencies:
  flutter:
    sdk: flutter

  # HTTP 통신
  http: ^1.1.0

  # 로컬 저장소 (세션 관리)
  shared_preferences: ^2.2.2

  # 기존 의존성 (필요시 유지)
  camera: ^0.10.5+5
  permission_handler: ^11.0.1
  path_provider: ^2.1.1

  # Firebase 제거 가능 (선택)
  # firebase_auth: ^4.15.0  # 주석 처리 또는 제거
  # firebase_core: ^2.24.0  # 주석 처리 또는 제거
```

---

## **🔧 Step 2: API 엔드포인트 설정**

### **aws_config.dart 업데이트**
실제 API Gateway ID로 변경:
```dart
// lib/config/aws_config.dart
static const String apiEndpoint = 'https://YOUR_ACTUAL_API_ID.execute-api.us-west-1.amazonaws.com/prod';
```

**YOUR_ACTUAL_API_ID**를 API Gateway 배포 후 실제 ID로 교체하세요.

---

## **🔐 Step 3: 인증 시스템 전환**

### **기존 Firebase 코드 교체**

#### **로그인 화면 업데이트**
```dart
// lib/screens/login_screen.dart 업데이트
import '../services/parasol_auth_service.dart';

class LoginScreen extends StatefulWidget {
  // 기존 Firebase 코드를 ParasolAuth로 교체

  Future<void> _handleLogin() async {
    final result = await parasolAuth.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (result['success'] == true) {
      // 로그인 성공
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      // 로그인 실패
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }
}
```

#### **회원가입 화면 추가**
```dart
// lib/screens/register_screen.dart 생성
import '../services/parasol_auth_service.dart';

class RegisterScreen extends StatefulWidget {
  // 새로운 회원가입 화면 구현

  Future<void> _handleRegister() async {
    final result = await parasolAuth.register(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text,
    );

    if (result['success'] == true) {
      // 회원가입 성공 - 로그인 화면으로 이동
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해주세요.')),
      );
    } else {
      // 회원가입 실패
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }
}
```

---

## **🔄 Step 4: 분석 API 통합**

### **기존 분석 화면 업데이트**

#### **아이 트래킹 화면**
```dart
// lib/screens/eye_tracking_screen.dart 업데이트
import '../services/unified_api_service.dart';
import '../services/analysis_polling_service.dart';
import '../widgets/analysis_progress_card.dart';

class EyeTrackingScreen extends StatefulWidget {
  Future<void> _uploadAnalysis(String videoData) async {
    // 기존 ngrok 코드 교체
    final result = await unifiedApi.uploadEyeTracking(
      videoData: videoData,
      fileName: 'eye_tracking_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    if (result['success'] != false) {
      final analysisId = result['analysis_id'];

      // 실시간 진행률 모니터링 시작
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AnalysisProgressScreen(
            analysisId: analysisId,
            analysisType: 'eye-tracking',
          ),
        ),
      );
    }
  }
}
```

#### **손가락 태핑 화면**
```dart
// lib/screens/finger_tapping_screen.dart 업데이트
Future<void> _uploadAnalysis(String videoData) async {
  final result = await unifiedApi.uploadFingerTapping(
    videoData: videoData,
    fileName: 'finger_tapping_${DateTime.now().millisecondsSinceEpoch}.mp4',
  );

  // 동일한 진행률 모니터링 로직
}
```

#### **음성 분석 화면**
```dart
// lib/screens/voice_analysis_screen.dart 업데이트
Future<void> _uploadAnalysis(String audioData) async {
  final result = await unifiedApi.uploadVoiceAnalysis(
    audioData: audioData,
    fileName: 'voice_analysis_${DateTime.now().millisecondsSinceEpoch}.wav',
  );

  // 동일한 진행률 모니터링 로직
}
```

---

## **📊 Step 5: 진행률 모니터링 화면 추가**

### **새로운 진행률 화면 생성**
```dart
// lib/screens/analysis_progress_screen.dart 생성
import '../services/analysis_polling_service.dart';
import '../widgets/analysis_progress_card.dart';

class AnalysisProgressScreen extends StatefulWidget {
  final String analysisId;
  final String analysisType;

  const AnalysisProgressScreen({
    required this.analysisId,
    required this.analysisType,
    super.key,
  });

  @override
  State<AnalysisProgressScreen> createState() => _AnalysisProgressScreenState();
}

class _AnalysisProgressScreenState extends State<AnalysisProgressScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 진행 상황'),
      ),
      body: StreamBuilder<AnalysisProgress>(
        stream: analysisPolling.startMonitoring(widget.analysisId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final progress = snapshot.data!;

          return Column(
            children: [
              AnalysisProgressCard(
                progress: progress,
                onTap: progress.isCompleted ? () {
                  // 결과 화면으로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AnalysisResultScreen(
                        analysisId: widget.analysisId,
                        results: progress.results!,
                      ),
                    ),
                  );
                } : null,
              ),

              if (progress.isCompleted)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text('홈으로 돌아가기'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    analysisPolling.stopMonitoring(widget.analysisId);
    super.dispose();
  }
}
```

---

## **🏠 Step 6: 홈 화면 업데이트**

### **사용자 분석 기록 표시**
```dart
// lib/screens/home_screen.dart 업데이트
import '../services/unified_api_service.dart';
import '../services/parasol_auth_service.dart';

class HomeScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parasol - ${parasolAuth.currentName ?? "사용자"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await parasolAuth.logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 새로운 분석 시작 버튼들
          _buildAnalysisButtons(),

          // 최근 분석 기록
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: unifiedApi.getUserAnalyses(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final analyses = snapshot.data!['analyses'] as List? ?? [];

                return ListView.builder(
                  itemCount: analyses.length,
                  itemBuilder: (context, index) {
                    final analysis = analyses[index];
                    return ListTile(
                      title: Text(analysis['analysis_type']),
                      subtitle: Text(analysis['status']),
                      trailing: Text(analysis['timestamp']),
                      onTap: () {
                        // 결과 화면으로 이동
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## **🧪 Step 7: 테스트 시나리오**

### **인증 테스트**
1. 회원가입 기능 테스트
2. 로그인/로그아웃 테스트
3. 세션 유지 테스트

### **분석 업로드 테스트**
1. 아이 트래킹 비디오 업로드
2. 손가락 태핑 비디오 업로드
3. 음성 분석 오디오 업로드

### **진행률 모니터링 테스트**
1. 실시간 상태 업데이트 확인
2. 완료/실패 상태 처리
3. 네트워크 오류 처리

### **결과 표시 테스트**
1. 분석 결과 조회
2. 사용자 기록 표시
3. 종합 진단 기능

---

## **⚠️ Step 8: 문제 해결**

### **일반적인 문제들**

#### **CORS 오류**
```
Access to fetch at '...' has been blocked by CORS policy
```
→ API Gateway CORS 설정 재확인

#### **인증 오류**
```
User is not authorized to perform: dynamodb:Scan
```
→ IAM 권한 설정 필요 (나중에 처리)

#### **네트워크 타임아웃**
```
SocketException: Failed host lookup
```
→ API 엔드포인트 URL 확인

### **디버깅 도구**

#### **로그 출력**
```dart
print('API Response: $response');
print('Auth Status: ${parasolAuth.isLoggedIn}');
```

#### **개발자 도구**
- Chrome DevTools Network 탭에서 API 호출 모니터링
- CloudWatch Logs에서 Lambda 실행 로그 확인

---

## **🚀 Step 9: 배포 준비**

### **프로덕션 설정**
1. API 엔드포인트 확인
2. 오류 처리 강화
3. 로딩 상태 개선
4. 오프라인 대응

### **성능 최적화**
1. 이미지/비디오 압축
2. 폴링 간격 조정
3. 캐싱 전략 구현

**Flutter 통합 완료!** 🎯

---

## **📝 체크리스트**

- ✅ AWS 인프라 배포 완료
- ✅ API Gateway 설정 완료
- ✅ Lambda 함수 배포 완료
- ✅ Flutter 코드 업데이트 완료
- ✅ 인증 시스템 전환 완료
- ✅ 비동기 폴링 로직 구현 완료
- ⏳ IAM 권한 설정 (권한 있는 관리자가 처리 필요)
- ⏳ 실제 API ID로 엔드포인트 업데이트
- ⏳ 통합 테스트 실행

이제 모든 구성 요소가 준비되었습니다! 🚀