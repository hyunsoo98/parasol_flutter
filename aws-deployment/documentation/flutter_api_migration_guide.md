# 📱 Flutter API 엔드포인트 AWS 마이그레이션 가이드

## 🔄 **현재 상황 분석**

### **기존 API (ngrok + Python 서버)**
```dart
// 현재 사용 중인 엔드포인트
POST https://8426dcee48d2.ngrok-free.app/eye/process?step=2&vpp_thresh=0.06&blink_thresh=0.18&max_frames=12000&save=true&return_overlay=false
```

### **목표 API (AWS API Gateway)**
```dart
// 새로운 엔드포인트
POST https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/upload
GET  https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod/api/v1/status/{analysis_id}
```

## 🎯 **API 변경사항**

### **1. Eye Tracking 분석**

#### **기존 방식 (ngrok)**
```dart
// 기존 코드
Future<void> processEyeTracking(File videoFile) async {
  final url = 'https://8426dcee48d2.ngrok-free.app/eye/process';
  final params = {
    'step': '2',
    'vpp_thresh': '0.06',
    'blink_thresh': '0.18',
    'max_frames': '12000',
    'save': 'true',
    'return_overlay': 'false'
  };

  final request = http.MultipartRequest('POST', Uri.parse(url).replace(queryParameters: params));
  request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));
  request.headers['ngrok-skip-browser-warning'] = 'true';

  final response = await request.send();
  // 직접 처리 결과 수신
}
```

#### **새로운 방식 (AWS)**
```dart
// AWS API 사용
Future<String> uploadEyeTracking(File videoFile, String userId) async {
  // 1. 업로드 요청
  final uploadUrl = '$baseUrl/api/v1/upload';
  final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

  // Base64 인코딩 또는 presigned URL 사용
  final bytes = await videoFile.readAsBytes();
  final base64Video = base64Encode(bytes);

  final body = {
    'analysis_type': 'eye-tracking',
    'user_id': userId,
    'video_data': base64Video,
    'parameters': {
      'step': 2,
      'vpp_thresh': 0.06,
      'blink_thresh': 0.18,
      'max_frames': 12000,
      'save': true,
      'return_overlay': false
    }
  };

  final response = await http.post(
    Uri.parse(uploadUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );

  final result = jsonDecode(response.body);
  return result['analysis_id']; // 분석 ID 반환
}

// 2. 결과 폴링
Future<Map<String, dynamic>?> pollAnalysisResult(String analysisId) async {
  final statusUrl = '$baseUrl/api/v1/status/$analysisId';

  while (true) {
    final response = await http.get(Uri.parse(statusUrl));
    final result = jsonDecode(response.body);

    if (result['status'] == 'completed') {
      return result['results'];
    } else if (result['status'] == 'failed') {
      throw Exception('분석 실패: ${result['error']}');
    }

    // 5초 대기 후 재시도
    await Future.delayed(Duration(seconds: 5));
  }
}
```

## 🔧 **Flutter 앱 수정 가이드**

### **1. 기본 설정**
```dart
class ApiConfig {
  // AWS API Gateway 엔드포인트 (배포 후 설정)
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // 또는 개발/프로덕션 환경 분리
  static String get baseUrl {
    if (kDebugMode) {
      return 'https://dev-api-id.execute-api.us-west-1.amazonaws.com/prod';
    } else {
      return 'https://prod-api-id.execute-api.us-west-1.amazonaws.com/prod';
    }
  }
}
```

### **2. 통합 분석 서비스**
```dart
class AnalysisService {
  static const String _baseUrl = ApiConfig.baseUrl;

  // 업로드 및 분석 시작
  Future<String> startAnalysis({
    required String analysisType,
    required File file,
    required String userId,
    Map<String, dynamic>? parameters,
  }) async {
    final bytes = await file.readAsBytes();
    final base64Data = base64Encode(bytes);

    final body = {
      'analysis_type': analysisType,
      'user_id': userId,
      'video_data': base64Data, // 또는 audio_data
      'parameters': parameters ?? {},
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/api/v1/upload'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return result['analysis_id'];
    } else {
      throw Exception('업로드 실패: ${response.body}');
    }
  }

  // 결과 조회
  Future<Map<String, dynamic>> getAnalysisResult(String analysisId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/v1/status/$analysisId'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('상태 조회 실패: ${response.body}');
    }
  }

  // 종합 진단 시작
  Future<String> startComprehensiveDiagnosis({
    required List<String> analysisIds,
    required String userId,
  }) async {
    final body = {
      'user_id': userId,
      'analysis_ids': analysisIds,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/api/v1/diagnosis/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return result['session_id'];
    } else {
      throw Exception('종합 진단 시작 실패: ${response.body}');
    }
  }
}
```

### **3. UI 업데이트 예시**
```dart
class EyeTrackingScreen extends StatefulWidget {
  @override
  _EyeTrackingScreenState createState() => _EyeTrackingScreenState();
}

class _EyeTrackingScreenState extends State<EyeTrackingScreen> {
  final AnalysisService _analysisService = AnalysisService();
  String? _analysisId;
  String _status = 'idle';
  Map<String, dynamic>? _results;

  Future<void> _startEyeTrackingAnalysis(File videoFile) async {
    setState(() => _status = 'uploading');

    try {
      // 1. 업로드 및 분석 시작
      _analysisId = await _analysisService.startAnalysis(
        analysisType: 'eye-tracking',
        file: videoFile,
        userId: 'user_123', // 실제 사용자 ID
        parameters: {
          'step': 2,
          'vpp_thresh': 0.06,
          'blink_thresh': 0.18,
          'max_frames': 12000,
          'save': true,
          'return_overlay': false,
        },
      );

      setState(() => _status = 'processing');

      // 2. 결과 폴링
      while (true) {
        final result = await _analysisService.getAnalysisResult(_analysisId!);

        if (result['status'] == 'completed') {
          setState(() {
            _status = 'completed';
            _results = result['results'];
          });
          break;
        } else if (result['status'] == 'failed') {
          setState(() => _status = 'failed');
          throw Exception('분석 실패');
        }

        // 5초 대기
        await Future.delayed(Duration(seconds: 5));
      }
    } catch (e) {
      setState(() => _status = 'error');
      print('분석 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Eye Tracking 분석')),
      body: Column(
        children: [
          // 상태 표시
          Text('상태: $_status'),

          // 업로드 버튼
          if (_status == 'idle')
            ElevatedButton(
              onPressed: () async {
                // 비디오 파일 선택 후
                final videoFile = await _pickVideoFile();
                if (videoFile != null) {
                  await _startEyeTrackingAnalysis(videoFile);
                }
              },
              child: Text('비디오 업로드 및 분석 시작'),
            ),

          // 진행률 표시
          if (_status == 'uploading' || _status == 'processing')
            CircularProgressIndicator(),

          // 결과 표시
          if (_results != null)
            ResultWidget(results: _results!),
        ],
      ),
    );
  }
}
```

## 🚀 **마이그레이션 단계**

### **1단계: AWS 인프라 배포**
- Lambda 함수들 배포
- API Gateway 설정
- DynamoDB 테이블 생성
- S3 버킷 설정

### **2단계: API 엔드포인트 확인**
```bash
# API Gateway 배포 후 엔드포인트 확인
aws apigateway get-rest-apis --region us-west-1
```

### **3단계: Flutter 코드 수정**
- `ApiConfig.baseUrl` 업데이트
- 기존 ngrok 코드를 AWS API 호출로 변경
- 비동기 폴링 로직 추가

### **4단계: 테스트**
- 개발 환경에서 테스트
- 각 분석 타입별 동작 확인
- 에러 처리 검증

이제 Flutter 앱을 AWS 아키텍처로 전환할 준비가 완료되었습니다! 🎯