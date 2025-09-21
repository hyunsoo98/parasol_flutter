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
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API 오류 (GET ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('API Exception (GET $path): $e');
    }
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('${AwsConfig.apiGatewayBaseUrl}$path');

      final response = await http.post(
        uri,
        headers: AwsConfig.defaultHeaders,
        body: data != null ? jsonEncode(data) : null,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API 오류 (POST ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('API Exception (POST $path): $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 💡 다른 파일들이 필요로 하는 이전 메소드들을 모두 복구하고, 내부적으로 post/get을 호출
  // ────────────────────────────────────────────────────────────────────────────

  // --- Health Check ---
  Future<bool> healthCheck() async {
    try {
      await get('/api/v1/health');
      return true;
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
}