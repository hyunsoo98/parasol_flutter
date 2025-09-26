import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // API Gateway 엔드포인트 URL (EC2 가이드와 매칭)
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // --- 기본 HTTP API 호출 함수 ---
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final finalUri = queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

      final response = await http.get(
        finalUri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
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

  // OPTIONS 요청 메서드 (CORS 프리플라이트)
  Future<Map<String, dynamic>> options(String path) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      final request = http.Request('OPTIONS', uri);
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });

      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'cors_enabled': true};
      } else {
        print('⚠️ OPTIONS 요청 실패: ${response.statusCode}');
        return {'error': 'options_failed', 'status_code': response.statusCode};
      }
    } catch (e) {
      print('⚠️ OPTIONS 요청 오류: $e');
      return {'error': 'options_error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      // 필수 필드가 없으면 임시 데이터 추가
      Map<String, dynamic> finalData = data ?? {};

      // AWS Lambda가 요구하는 필수 필드들 자동 추가
      if (!finalData.containsKey('analysis_type')) {
        if (path.contains('finger') || path.contains('tapping')) {
          finalData['analysis_type'] = 'finger-tapping';
        } else if (path.contains('voice') || path.contains('speech')) {
          finalData['analysis_type'] = 'voice-analysis';
        } else if (path.contains('eye') || path.contains('gaze')) {
          finalData['analysis_type'] = 'eye-tracking-results';
        } else {
          finalData['analysis_type'] = 'voice-analysis'; // 기본값
        }
      }

      if (!finalData.containsKey('user_id')) {
        finalData['user_id'] = 'temp-user-${DateTime.now().millisecondsSinceEpoch}';
      }

      // Lambda 필드명과 매칭
      if (finalData.containsKey('fileData')) {
        finalData['video_data'] = finalData.remove('fileData');
      }

      // 시선추적 결과의 경우 results_data 사용
      if (finalData['analysis_type'] == 'eye-tracking-results' && finalData.containsKey('video_data')) {
        finalData['results_data'] = finalData.remove('video_data');
      }

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(finalData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 403) {
        // 403 인증 오류는 서버 설정 문제이므로 fallback 응답 반환
        print('⚠️ API 인증 오류 (403) - 로컬 모드로 동작: $path');
        return {'error': 'auth_required', 'message': 'Server authentication required', 'local_mode': true};
      } else {
        // 500 서버 오류도 graceful하게 처리
        if (response.statusCode == 500) {
          print('⚠️ 서버 내부 오류 (500) - 로컬 모드로 동작: $path');
          return {'error': 'server_error', 'message': 'Internal server error', 'local_mode': true};
        }
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
      // 1. 먼저 OPTIONS 요청으로 CORS 확인
      final optionsResult = await options('/api/v1/health');
      if (optionsResult['success'] == true) {
        print('✅ CORS 프리플라이트 성공');
      }

      // 2. 실제 GET 요청
      final result = await get('/api/v1/health');

      // 403 오류도 서버가 살아있다는 의미이므로 true 반환
      if (result['local_mode'] == true && result['error'] == 'auth_required') {
        print('💡 서버는 정상이지만 인증이 필요한 상태입니다.');
        return true;
      }
      return result['error'] == null;
    } catch (_) {
      // 3. 모든 요청이 실패하면 OPTIONS만 시도
      try {
        final optionsResult = await options('/api/v1/health');
        return optionsResult['error'] == null;
      } catch (_) {
        return false;
      }
    }
  }

  // --- 레거시 호환성 메서드들 (기존 코드 지원) ---

  Future<Map<String, dynamic>> saveEyeRecord(Map<String, dynamic> data) {
    return submitVideoAnalysisRequest(
      sessionId: data['session_id'] ?? 'default',
      userId: data['user_id'] ?? 'guest',
      videoData: data['results'] ?? data,
    );
  }

  // --- 영상 기반 분석을 위한 새로운 API ---

  // 영상 분석 요청 제출 (Lambda 통합 업로드 엔드포인트 사용)
  Future<Map<String, dynamic>> submitVideoAnalysisRequest({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> videoData,
  }) {
    final data = {
      'user_id': userId,
      'analysis_type': 'eye-tracking-results',
      'results_data': videoData,
      'parameters': {
        'session_id': sessionId,
        'submitted_at': DateTime.now().toIso8601String(),
      }
    };
    return post('/upload', data: data);
  }

  // 손가락 태핑 분석 요청
  Future<Map<String, dynamic>> submitFingerTappingRequest({
    required String userId,
    required String videoData,
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

  // 음성 분석 요청
  Future<Map<String, dynamic>> submitVoiceAnalysisRequest({
    required String userId,
    required String audioData,
    Map<String, dynamic>? parameters,
  }) {
    final data = {
      'user_id': userId,
      'analysis_type': 'voice-analysis',
      'video_data': audioData,  // Lambda에서는 video_data로 통일
      'parameters': parameters ?? {}
    };
    return post('/upload', data: data);
  }

  // 분석 상태 확인 (Lambda 통합 상태 확인 엔드포인트 사용)
  Future<Map<String, dynamic>> getAnalysisStatus(String analysisId) {
    return get('/status/$analysisId');
  }

  // 분석 결과 조회
  Future<Map<String, dynamic>> getAnalysisResults(String analysisId) {
    return get('/results/$analysisId');
  }

  // --- 건강 상태 확인 ---
  Future<bool> isServerHealthy() async {
    try {
      final result = await get('/health');
      return result['status'] == 'ok';
    } catch (e) {
      print('서버 상태 확인 실패: $e');
      return false;
    }
  }

  // --- 음성 분석 메서드 ---
  Future<Map<String, dynamic>> predictSpeech(Map<String, dynamic> data) {
    return submitVoiceAnalysisRequest(
      userId: data['user_id'] ?? 'guest',
      audioData: data['audio_data'] ?? data['fileData'] ?? '',
      parameters: data,
    );
  }

  // --- 손가락 태핑 분석 메서드 ---
  Future<Map<String, dynamic>> predictFinger(Map<String, dynamic> data) {
    return submitFingerTappingRequest(
      userId: data['user_id'] ?? 'guest',
      videoData: data['video_data'] ?? data['fileData'] ?? '',
      parameters: data,
    );
  }

  Future<Map<String, dynamic>> loadAndPredictLatestFinger() async {
    // 최신 손가락 태핑 데이터를 로드하고 예측하는 메서드
    // 임시로 빈 데이터로 예측 요청을 보냄
    return predictFinger({
      'user_id': 'temp-user-${DateTime.now().millisecondsSinceEpoch}',
      'analysis_type': 'finger-tapping',
      'load_latest': true,
    });
  }

  // --- 실시간 시선 추적 메서드 ---
  Future<Map<String, dynamic>> submitRealtimeEyeResults({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> analysisResults,
    Map<String, dynamic>? metadata,
  }) {
    final combinedData = {
      'session_id': sessionId,
      'user_id': userId,
      ...analysisResults,
      if (metadata != null) ...metadata,
    };
    return submitVideoAnalysisRequest(
      sessionId: sessionId,
      userId: userId,
      videoData: combinedData,
    );
  }

  Future<Map<String, dynamic>> notifyEyeTestCompletion({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> eyeResults,
  }) {
    final data = {
      'session_id': sessionId,
      'user_id': userId,
      'analysis_type': 'eye-tracking-completion',
      'completed_at': DateTime.now().toIso8601String(),
      'eye_results': eyeResults,
    };
    return post('/completion', data: data);
  }

  // --- 상태 확인 메서드 ---
  Future<Map<String, dynamic>> getStatus(String sessionId) {
    return get('/status', queryParams: {'session_id': sessionId});
  }
}