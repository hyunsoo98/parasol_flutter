import 'dart:convert';
import 'package:http/http.dart' as http;

/// 🎯 정리된 API 서비스 - EC2 Lambda 통합 버전
class ApiService {
  // API Gateway 엔드포인트 URL (실제 배포 시 변경 필요)
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // HTTP 헤더
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// GET 요청
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final finalUri = queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

      final response = await http.get(finalUri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API 오류 (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('⚠️ API 호출 실패: $path - $e');
      return {'error': 'network_error', 'message': 'API call failed', 'local_mode': true};
    }
  }

  /// POST 요청
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      Map<String, dynamic> finalData = data ?? {};

      // 필수 필드 자동 추가
      if (!finalData.containsKey('user_id')) {
        finalData['user_id'] = 'guest_${DateTime.now().millisecondsSinceEpoch}';
      }

      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(finalData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('API 오류 (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('⚠️ API 호출 실패: $path - $e');
      return {'error': 'network_error', 'message': 'API call failed', 'local_mode': true};
    }
  }

  /// 👁️ 시선 추적 결과 업로드
  Future<Map<String, dynamic>> submitEyeTrackingResults({
    required String userId,
    required Map<String, dynamic> resultsData,
    String? sessionId,
  }) {
    final data = {
      'user_id': userId,
      'analysis_type': 'eye-tracking-results',
      'results_data': resultsData,
      'parameters': {
        'session_id': sessionId ?? 'default',
        'submitted_at': DateTime.now().toIso8601String(),
      }
    };
    return post('/upload', data: data);
  }

  /// 👆 손가락 태핑 비디오 업로드
  Future<Map<String, dynamic>> submitFingerTappingVideo({
    required String userId,
    required String videoData, // Base64 encoded
    Map<String, dynamic>? parameters,
  }) {
    final data = {
      'user_id': userId,
      'analysis_type': 'finger-tapping',
      'video_data': videoData,
      'parameters': parameters ?? {}
    };
    return post('/upload', data: data);
  }

  /// 🎤 음성 분석 오디오 업로드
  Future<Map<String, dynamic>> submitVoiceAnalysis({
    required String userId,
    required String audioData, // Base64 encoded
    Map<String, dynamic>? parameters,
  }) {
    final data = {
      'user_id': userId,
      'analysis_type': 'voice-analysis',
      'video_data': audioData, // Lambda에서는 video_data로 통일
      'parameters': parameters ?? {}
    };
    return post('/upload', data: data);
  }

  /// 📊 분석 상태 확인
  Future<Map<String, dynamic>> getAnalysisStatus(String analysisId) {
    return get('/status/$analysisId');
  }

  /// 📋 분석 결과 조회
  Future<Map<String, dynamic>> getAnalysisResults(String analysisId) {
    return get('/results/$analysisId');
  }

  /// 🏥 서버 상태 확인
  Future<bool> isServerHealthy() async {
    try {
      final result = await get('/health');
      return result['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  /// 🔄 레거시 호환성 - 기존 코드 지원용
  Future<Map<String, dynamic>> saveEyeRecord(Map<String, dynamic> data) {
    return submitEyeTrackingResults(
      userId: data['user_id'] ?? 'guest',
      resultsData: data['results'] ?? data,
      sessionId: data['session_id'],
    );
  }
}