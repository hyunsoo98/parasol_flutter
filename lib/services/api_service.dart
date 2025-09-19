import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// AWS API Gateway 베이스 URL (스테이지 포함)
const String baseUrl = 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';

class ApiService {
  static const String _baseUrl = baseUrl;

  // (선택) 개발 우회 헤더
  String? _devKey;
  String? _devUser;

  // (선택) API Key 헤더
  String? _apiKey;

  // ────────────────────────────────────────────────────────────────────────────
  // 구성/상태
  // ────────────────────────────────────────────────────────────────────────────

  void configureDevBypass({required String devKey, String devUser = 'tester'}) {
    _devKey = devKey;
    _devUser = devUser;
  }

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  // Firebase 미사용: 커스텀 JWT를 쓰게 되면 여기서 읽어오면 됨
  Future<String?> _getAuthToken() async {
    try {
      return null;
    } catch (_) {
      return null;
    }
  }

  // 공통 헤더 생성
  // includeAuth=false 이면 Authorization 절대 추가하지 않음
  Future<Map<String, String>> _authHeaders({
    bool jsonContent = true,
    bool includeAuth = true,
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{
      if (jsonContent) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (_apiKey != null && _apiKey!.isNotEmpty) 'x-api-key': _apiKey!, // 옵션
      if (_devKey != null) 'X-Dev-Key': _devKey!,
      if (_devUser != null) 'X-Dev-User': _devUser!,
      if (extra != null) ...extra,
    };

    if (includeAuth) {
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Uri _uri(String endpoint, {Map<String, String>? query}) {
    return Uri.parse('$_baseUrl$endpoint').replace(queryParameters: query);
  }

  // 응답 처리(항상 JSON으로 반환 시도)
  Map<String, dynamic> _okJson(http.Response resp) {
    if (resp.bodyBytes.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return {'raw': utf8.decode(resp.bodyBytes)};
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 공통 HTTP
  // ────────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String endpoint, {
    Map<String, String>? query,
    bool includeAuth = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final resp = await http
          .get(
            _uri(endpoint, query: query),
            headers: await _authHeaders(includeAuth: includeAuth),
          )
          .timeout(timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return _okJson(resp);
      } else {
        throw Exception('API 오류 (GET ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _post(
    String endpoint, {
    Map<String, dynamic>? data,
    Map<String, String>? query,
    bool includeAuth = true,
    Duration timeout = const Duration(minutes: 1),
  }) async {
    try {
      final resp = await http
          .post(
            _uri(endpoint, query: query),
            headers: await _authHeaders(jsonContent: true, includeAuth: includeAuth),
            body: data != null ? jsonEncode(data) : null,
          )
          .timeout(timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return _okJson(resp);
      } else {
        throw Exception('API 오류 (POST ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _multipartPost(
    String endpoint, {
    required File file,
    String fileFieldName = 'file',
    Map<String, String>? fields,
    Map<String, String>? query, // 쿼리 파라미터
    bool includeAuth = false, // 업로드는 기본적으로 Authorization 제거
    Duration timeout = const Duration(minutes: 5),
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final req = http.MultipartRequest('POST', _uri(endpoint, query: query));

      if (fields != null && fields.isNotEmpty) {
        req.fields.addAll(fields);
      }

      // Content-Type은 http가 자동 세팅(multipart/form-data; boundary=...)
      req.files.add(await http.MultipartFile.fromPath(fileFieldName, file.path));

      // Authorization 제거/유지 제어
      req.headers.addAll(await _authHeaders(
        jsonContent: false,
        includeAuth: includeAuth,
        extra: extraHeaders,
      ));

      final streamed = await req.send().timeout(timeout);
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return _okJson(resp);
      } else {
        throw Exception('API 오류 (MULTIPART ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Gateway / Health
  // ────────────────────────────────────────────────────────────────────────────

  // 설계 반영: GET /api/v1/health
  Future<bool> healthCheck() async {
    try {
      final resp = await http
          .get(
            _uri('/api/v1/health'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 업로드(통합) + 상태/결과 조회
  // ────────────────────────────────────────────────────────────────────────────

  /// 비디오 업로드(Finger-tapping용): POST /api/v1/upload
  /// - 시선추적은 클라이언트에서 분석하므로 제거됨
  /// - fields.analysis_type = 'finger-tapping'
  /// - Authorization은 붙이지 않음(includeAuth:false)
  Future<Map<String, dynamic>> analyzeFingerVideo(
    File video, {
    Map<String, String>? meta,
    Map<String, String>? query,
  }) {
    final fields = <String, String>{
      'analysis_type': 'finger-tapping',
      if (meta != null) ...meta,
    };
    return _multipartPost(
      '/api/v1/upload',
      file: video,
      fields: fields,
      query: query,
      includeAuth: false,
    );
    // 서버가 API Key를 요구한다면 setApiKey로 설정해 두면 자동 첨부됨
  }

  /// 상태 조회: GET /api/v1/status/{analysis_id}
  Future<Map<String, dynamic>> getStatus(String analysisId) {
    return _get('/api/v1/status/$analysisId');
  }

  /// 결과 조회: GET /api/v1/results/{analysis_id}
  Future<Map<String, dynamic>> getResults(String analysisId) {
    return _get('/api/v1/results/$analysisId');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // (기존 JSON 엔드포인트 유지 — 필요시 사용)
  // ────────────────────────────────────────────────────────────────────────────

  // Speech
  Future<Map<String, dynamic>> predictSpeech(Map<String, dynamic> data) {
    return _post('/speech/predict', data: data);
  }

  // Finger
  Future<Map<String, dynamic>> predictFinger(Map<String, dynamic> data) {
    return _post('/finger/predict', data: data);
  }

  Future<Map<String, dynamic>> saveFingerFile(Map<String, dynamic> data) {
    return _post('/finger/save', data: data);
  }

  Future<Map<String, dynamic>> loadAndPredictLatestFinger() {
    return _post('/finger/load_predict');
  }

  // Eye(JSON)
  Future<Map<String, dynamic>> analyzeEye(Map<String, dynamic> data) {
    return _post('/eye/analyze', data: data);
  }

  Future<Map<String, dynamic>> saveEyeRecord(Map<String, dynamic> data) {
    return _post('/eye/save', data: data);
  }

  Future<Map<String, dynamic>> loadAndPredictEye() {
    return _post('/eye/load_predict');
  }

  Future<Map<String, dynamic>> processEyeVideo(Map<String, dynamic> data) {
    return _post('/eye/process', data: data);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 실시간 분석 결과 전송 (eye.py 호환)
  // ────────────────────────────────────────────────────────────────────────────

  /// 실시간 시선추적 분석 결과를 기존 서버 API 형식으로 전송 (비디오 업로드 제거)
  /// 클라이언트에서 분석된 결과만 전송
  Future<Map<String, dynamic>> submitRealtimeEyeResults({
    required String sessionId,
    required Map<String, dynamic> analysisResults,
    required String userId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // 분석 결과를 기존 eye.py 포맷으로 변환하여 전송 (비디오 업로드 없음)
      final resultData = {
        'session_id': sessionId,
        'user_id': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'analysis_type': 'eye-tracking-realtime-client',
        'results': analysisResults,
        'metadata': {
          'platform': 'flutter',
          'analysis_engine': 'ml_kit_client',
          'test_duration': analysisResults['test_duration'] ?? 0,
          'total_frames': analysisResults['total_frames'] ?? 0,
          'processing_fps': analysisResults['processing_fps'] ?? 0,
          if (metadata != null) ...metadata,
        },
      };

      return await _post('/eye/save', data: resultData);
    } catch (e) {
      return {'error': 'Failed to submit realtime eye results: $e'};
    }
  }

  /// Finger-tapping 테스트 시작을 위한 결과 전달
  /// 시선추적 완료 후 다음 테스트 연계용
  Future<Map<String, dynamic>> notifyEyeTestCompletion({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> eyeResults,
  }) async {
    final data = {
      'session_id': sessionId,
      'user_id': userId,
      'previous_test': 'eye-tracking',
      'eye_results_summary': {
        'psp_detected': eyeResults['psp_detected'] ?? false,
        'vertical_range': eyeResults['vertical_range'] ?? 0.0,
        'blink_count': eyeResults['blink_count'] ?? 0,
        'test_duration': eyeResults['test_duration'] ?? 0,
      },
      'next_test': 'finger-tapping',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    return await _post('/api/v1/test/transition', data: data);
  }
}
