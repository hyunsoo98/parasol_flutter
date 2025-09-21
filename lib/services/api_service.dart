import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/aws_config.dart';

class ApiService {
  // ⚠️ 중요: 이 값은 amplify add api 로 설정한 실제 API 이름이어야 합니다.
  final String _apiName = 'parasolApi'; // <- 실제 API 이름으로 수정하세요!

  // --- 기본 HTTP API 호출 함수 ---
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    try {
      final uri = Uri.parse('${AwsConfig.apiGatewayBaseUrl}$path');
      final finalUri = queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

      final response = await http.get(
        finalUri,
        headers: AwsConfig.defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 403) {
        // 403 인증 오류는 서버 설정 문제이므로 fallback 응답 반환
        print('⚠️ API 인증 오류 (403) - 로컬 모드로 동작: $path');
        return {'error': 'auth_required', 'message': 'Server authentication required', 'local_mode': true};
      } else {
        throw Exception('API 오류 (GET ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      // 네트워크 오류나 타임아웃 시 fallback
      print('⚠️ API 호출 실패 - 로컬 모드로 동작: $path - $e');
      return {'error': 'network_error', 'message': 'API call failed', 'local_mode': true};
    }
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('${AwsConfig.apiGatewayBaseUrl}$path');

      final response = await http.post(
        uri,
        headers: AwsConfig.defaultHeaders,
        body: data != null ? jsonEncode(data) : null,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 403) {
        // 403 인증 오류는 서버 설정 문제이므로 fallback 응답 반환
        print('⚠️ API 인증 오류 (403) - 로컬 모드로 동작: $path');
        return {'error': 'auth_required', 'message': 'Server authentication required', 'local_mode': true};
      } else {
        throw Exception('API 오류 (POST ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      // 네트워크 오류나 타임아웃 시 fallback
      print('⚠️ API 호출 실패 - 로컬 모드로 동작: $path - $e');
      return {'error': 'network_error', 'message': 'API call failed', 'local_mode': true};
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 💡 다른 파일들이 필요로 하는 이전 메소드들을 모두 복구하고, 내부적으로 post/get을 호출
  // ────────────────────────────────────────────────────────────────────────────

  // --- Health Check ---
  Future<bool> healthCheck() async {
    try {
      final result = await get('/api/v1/health');
      // 403 오류도 서버가 살아있다는 의미이므로 true 반환
      if (result['local_mode'] == true && result['error'] == 'auth_required') {
        print('💡 서버는 정상이지만 인증이 필요한 상태입니다.');
        return true;
      }
      return result['error'] == null;
    } catch (_) {
      return false;
    }
  }

  // --- Status & Results ---
  Future<Map<String, dynamic>> getStatus(String analysisId) {
    return get('/api/v1/status/$analysisId');
  }

  Future<Map<String, dynamic>> getResults(String analysisId) {
    return get('/api/v1/results/$analysisId');
  }
  
  // --- Speech ---
  Future<Map<String, dynamic>> predictSpeech(Map<String, dynamic> data) {
    return post('/speech/predict', data: data);
  }

  // --- Finger ---
  Future<Map<String, dynamic>> predictFinger(Map<String, dynamic> data) {
    return post('/finger/predict', data: data);
  }
  Future<Map<String, dynamic>> saveFingerFile(Map<String, dynamic> data) {
    return post('/finger/save', data: data);
  }
  Future<Map<String, dynamic>> loadAndPredictLatestFinger() {
    return post('/finger/load_predict');
  }

  // --- Eye ---
  Future<Map<String, dynamic>> analyzeEye(Map<String, dynamic> data) {
    return post('/eye/analyze', data: data);
  }
  Future<Map<String, dynamic>> saveEyeRecord(Map<String, dynamic> data) {
    return post('/eye/save', data: data);
  }
  Future<Map<String, dynamic>> loadAndPredictEye() {
    return post('/eye/load_predict');
  }
  Future<Map<String, dynamic>> processEyeVideo(Map<String, dynamic> data) {
    return post('/eye/process', data: data);
  }

  // --- Test Flow 연동 ---
  Future<Map<String, dynamic>> submitRealtimeEyeResults({
    required String sessionId,
    required Map<String, dynamic> analysisResults,
    required String userId,
    Map<String, dynamic>? metadata,
  }) {
    final data = {
      'session_id': sessionId,
      'user_id': userId,
      'analysis_type': 'eye-tracking-realtime-client',
      'results': analysisResults,
      'metadata': metadata,
    };
    return post('/eye/save', data: data);
  }
    
  Future<Map<String, dynamic>> notifyEyeTestCompletion({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> eyeResults,
  }) {
    final data = {
      'session_id': sessionId,
      'user_id': userId,
      'previous_test': 'eye-tracking',
      'eye_results_summary': eyeResults,
      'next_test': 'finger-tapping',
    };
    return post('/api/v1/test/transition', data: data);
  }

  // --- 영상 기반 분석을 위한 새로운 API ---

  // 영상 분석 요청 제출
  Future<Map<String, dynamic>> submitVideoAnalysisRequest({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> videoData,
  }) {
    final data = {
      'session_id': sessionId,
      'user_id': userId,
      'analysis_type': 'eye-tracking-video',
      'video_data': videoData,
      'submitted_at': DateTime.now().toIso8601String(),
    };
    return post('/eye/video/submit', data: data);
  }

  // 분석 상태 확인
  Future<Map<String, dynamic>> getAnalysisStatus(String sessionId) {
    return get('/eye/video/status/$sessionId');
  }

  // 분석 결과 조회
  Future<Map<String, dynamic>> getAnalysisResults(String sessionId) {
    return get('/eye/video/results/$sessionId');
  }

  // --- 건너뛰기 기록 ---
  Future<Map<String, dynamic>> recordSkippedTest(Map<String, dynamic> data) {
    return post('/api/v1/test/skipped', data: data);
  }
}