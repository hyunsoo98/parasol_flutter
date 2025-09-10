import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

// 개발 환경에 맞게 수정
const String baseUrl = 'https://8426dcee48d2.ngrok-free.app';

class ApiService {
  static const String _baseUrl = baseUrl;

  // (선택) 개발 우회
  String? _devKey;
  String? _devUser;

  void configureDevBypass({required String devKey, String devUser = 'tester'}) {
    _devKey = devKey;
    _devUser = devUser;
  }

  Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken(true);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _authHeaders({bool jsonContent = true}) async {
    final token = await _getAuthToken();
    return {
      if (jsonContent) 'Content-Type': 'application/json', // multipart에서는 설정하지 말 것
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
      if (_devKey != null) 'X-Dev-Key': _devKey!,
      if (_devUser != null) 'X-Dev-User': _devUser!,
    };
  }

  /// 공통 POST(JSON) — 멀티파트가 아닌 엔드포인트만 사용
  Future<Map<String, dynamic>> _post(String endpoint, {Map<String, dynamic>? data}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _authHeaders(jsonContent: true),
        body: data != null ? jsonEncode(data) : null,
      ).timeout(const Duration(minutes: 1));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(utf8.decode(resp.bodyBytes));
      } else {
        throw Exception('API 오류 (상태 ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      print('$endpoint API 오류: $e');
      return {'error': e.toString()};
    }
  }

  /// 공통 POST(Multipart) — 파일 업로드용
  Future<Map<String, dynamic>> _multipartPost(
    String endpoint, {
    required File file,
    String fileFieldName = 'file',
    Map<String, String>? fields,
    Map<String, String>? query, // 쿼리 파라미터
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint').replace(queryParameters: query);
      final req = http.MultipartRequest('POST', uri);

      if (fields != null) req.fields.addAll(fields);
      req.files.add(await http.MultipartFile.fromPath(fileFieldName, file.path));

      // 멀티파트: Content-Type은 http가 알아서 설정 → 수동 지정 금지
      req.headers.addAll(await _authHeaders(jsonContent: false));

      final streamed = await req.send().timeout(const Duration(minutes: 5));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(utf8.decode(resp.bodyBytes));
      } else {
        throw Exception('API 오류 (상태 ${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      print('$endpoint API (multipart) 오류: $e');
      return {'error': e.toString()};
    }
  }

  // --- Gateway ---
  Future<bool> healthCheck() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/healthz'), headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      print('Health check 오류: $e');
      return false;
    }
  }

  // --- Speech ---
  Future<Map<String, dynamic>> predictSpeech(Map<String, dynamic> data) async {
    return await _post('/speech/predict', data: data);
  }

  // --- Finger ---
  Future<Map<String, dynamic>> predictFinger(Map<String, dynamic> data) async {
    return await _post('/finger/predict', data: data);
  }

  Future<Map<String, dynamic>> saveFingerFile(Map<String, dynamic> data) async {
    return await _post('/finger/save', data: data);
  }

  Future<Map<String, dynamic>> loadAndPredictLatestFinger() async {
    return await _post('/finger/load_predict');
  }

  // --- Eye ---
  Future<Map<String, dynamic>> analyzeEye(Map<String, dynamic> data) async {
    return await _post('/eye/analyze', data: data);
  }

  Future<Map<String, dynamic>> saveEyeRecord(Map<String, dynamic> data) async {
    return await _post('/eye/save', data: data);
  }

  Future<Map<String, dynamic>> loadAndPredictEye() async {
    return await _post('/eye/load_predict');
  }

  Future<Map<String, dynamic>> processEyeVideo(Map<String, dynamic> data) async {
    return await _post('/eye/process', data: data);
  }
}