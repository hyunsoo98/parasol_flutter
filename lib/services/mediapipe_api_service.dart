// lib/services/mediapipe_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
// import 'package:firebase_auth/firebase_auth.dart'; - 제거됨
import '../models/diagnosis_result.dart';
import 'parasol_auth_service.dart';

class MediaPipeApiService {
  static const String _baseUrl = 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod'; // AWS API Gateway

  // (선택) 개발 우회 헤더 지원
  String? _devKey;
  String? _devUser;

  static MediaPipeApiService? _instance;
  MediaPipeApiService._internal();
  factory MediaPipeApiService() {
    _instance ??= MediaPipeApiService._internal();
    return _instance!;
  }

  /// 개발 우회 모드 설정 (운영에서는 호출하지 마세요)
  void configureDevBypass({required String devKey, String devUser = 'tester'}) {
    _devKey = devKey;
    _devUser = devUser;
  }

  // Firebase 인증 토큰
  Future<String?> _getAuthToken() async {
    try {
      // final user = FirebaseAuth.instance.currentUser; - 제거됨
    final user = null; // 임시
      return await user?.getIdToken(true); // 갱신
    } catch (e) {
      print('토큰 가져오기 실패: $e');
      return null;
    }
  }

  // 인증/공통 헤더
  Future<Map<String, String>> _authHeaders({bool jsonContent = true}) async {
    return {
      if (jsonContent) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      // 게스트 사용자를 위해 인증 헤더 제거 (필요시 나중에 추가)
      // ParasolAuth 헤더는 AWS API Gateway에서 지원하지 않는 형식으로 보임
      // 개발용 헤더 (필요시)
      if (_devKey != null) 'X-Dev-Key': _devKey!,
      if (_devUser != null) 'X-Dev-User': _devUser!,
    };
  }

  /// 초기 분류 (이미지/비디오) — 서버에 해당 엔드포인트가 있을 때만 사용
  Future<DiagnosisResult> analyzeForInitialClassification({
    required File imageFile,
    File? videoFile,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/classify');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      if (videoFile != null) {
        request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));
      }

      request.headers.addAll(await _authHeaders());

      final streamed = await request.send().timeout(const Duration(minutes: 2));
      final responseData = await streamed.stream.transform(utf8.decoder).join();

      if (streamed.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(responseData);
        return DiagnosisResult.fromJson(data);
      } else {
        throw Exception('분류 API 호출 실패: ${streamed.statusCode} / $responseData');
      }
    } catch (e) {
      throw Exception('초기 분류 분석 실패: $e');
    }
  }

  /// 시선 추적 분석 (DEPRECATED - 클라이언트 실시간 분석으로 대체됨)
  /// 이 메서드는 더 이상 사용되지 않습니다. StructuredEyeTestService를 사용하세요.
  @Deprecated('Use StructuredEyeTestService for client-side real-time analysis')
  Future<EyeTrackingResult> analyzeEyeTracking({
    required File videoFile,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    throw Exception(
      '시선추적 분석이 클라이언트 실시간 분석으로 변경되었습니다. '
      'StructuredEyeTestService를 사용하세요.'
    );
  }

  /// 서버 상태 확인 — /api/v1/health (GET)
  Future<bool> checkServerHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/health');
      final resp = await http.get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));
      print('헬스체크: ${resp.statusCode} ${resp.body}');
      return resp.statusCode == 200;
    } catch (e) {
      print('헬스체크 오류: $e');
      // 네트워크 불가 상황에서도 앱 흐름을 막지 않으려면 true 반환 유지 가능
      return false;
    }
  }

  /// 시선 추적 분석 (DEPRECATED - 클라이언트 실시간 분석으로 대체됨)
  @Deprecated('Use StructuredEyeTestService for client-side real-time analysis')
  Future<EyeTrackingResult> analyzeEyeTrackingFromBytes({
    required List<int> videoBytes,
    required String fileName,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    throw Exception(
      '시선추적 분석이 클라이언트 실시간 분석으로 변경되었습니다. '
      'StructuredEyeTestService를 사용하세요.'
    );
  }

  /// 결과 폴링 (DEPRECATED - 더 이상 사용되지 않음)
  @Deprecated('Eye tracking analysis moved to client-side')
  Future<EyeTrackingResult> _pollForResults(String analysisId) async {
    throw Exception('시선추적 분석이 클라이언트에서 실시간으로 처리됩니다.');
  }
}
