// lib/services/unified_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/aws_config.dart';
import 'parasol_auth_service.dart';

class UnifiedApiService {
  // 싱글톤 패턴
  static final UnifiedApiService _instance = UnifiedApiService._internal();
  factory UnifiedApiService() => _instance;
  UnifiedApiService._internal();

  // 공통 요청 메서드
  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String url, {
    Map<String, dynamic>? body,
    bool requiresAuth = false,
    Map<String, String>? customHeaders,
  }) async {
    try {
      // 헤더 준비
      Map<String, String> headers = AWSConfig.defaultHeaders;

      // 인증이 필요한 경우
      if (requiresAuth) {
        if (!parasolAuth.isLoggedIn) {
          throw Exception('로그인이 필요합니다.');
        }
        headers = parasolAuth.getAuthenticatedHeaders();
      }

      // 커스텀 헤더 추가
      if (customHeaders != null) {
        headers.addAll(customHeaders);
      }

      // 요청 실행
      http.Response response;
      final uri = Uri.parse(url);

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw Exception('지원하지 않는 HTTP 메서드: $method');
      }

      // 응답 처리
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return jsonDecode(response.body);
      } else {
        final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        throw Exception('API 오류 (${response.statusCode}): ${errorBody['error'] ?? errorBody['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('API 요청 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // === 인증 관련 API ===

  // 회원가입 (인증 불필요)
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
  }) async {
    return await _makeRequest(
      'POST',
      AWSConfig.getRegisterUrl(),
      body: {
        'email': email,
        'password': password,
        'name': name,
      },
      requiresAuth: false,
    );
  }

  // 로그인 (인증 불필요)
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return await _makeRequest(
      'POST',
      AWSConfig.getLoginUrl(),
      body: {
        'email': email,
        'password': password,
      },
      requiresAuth: false,
    );
  }

  // === 분석 관련 API ===

  // 통합 업로드 (인증 필요)
  Future<Map<String, dynamic>> uploadAnalysis({
    required String analysisType, // 'eye-tracking', 'finger-tapping', 'voice-analysis'
    required String fileData, // base64 인코딩된 데이터
    String? fileName,
    Map<String, dynamic>? parameters,
  }) async {
    if (!parasolAuth.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    return await _makeRequest(
      'POST',
      AWSConfig.getUploadUrl(),
      body: {
        'analysis_type': analysisType,
        'file_data': fileData,
        'user_id': parasolAuth.currentUserId,
        'file_name': fileName,
        'parameters': parameters ?? {},
      },
      requiresAuth: true,
    );
  }

  // 특정 분석 상태 조회 (인증 필요)
  Future<Map<String, dynamic>> getAnalysisStatus(String analysisId) async {
    return await _makeRequest(
      'GET',
      '${AWSConfig.getStatusUrl()}/$analysisId',
      requiresAuth: true,
    );
  }

  // 사용자의 모든 분석 상태 조회 (인증 필요)
  Future<Map<String, dynamic>> getUserAnalyses() async {
    if (!parasolAuth.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    return await _makeRequest(
      'GET',
      '${AWSConfig.getStatusUrl()}?user_id=${parasolAuth.currentUserId}',
      requiresAuth: true,
    );
  }

  // 특정 분석 결과 조회 (인증 필요)
  Future<Map<String, dynamic>> getAnalysisResults(String analysisId) async {
    return await _makeRequest(
      'GET',
      '${AWSConfig.getResultsUrl()}/$analysisId',
      requiresAuth: true,
    );
  }

  // === 종합 진단 관련 API ===

  // 종합 진단 시작 (인증 필요)
  Future<Map<String, dynamic>> startComprehensiveDiagnosis({
    required List<String> analysisIds,
  }) async {
    if (!parasolAuth.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    return await _makeRequest(
      'POST',
      AWSConfig.getDiagnosisStartUrl(),
      body: {
        'user_id': parasolAuth.currentUserId,
        'analysis_ids': analysisIds,
      },
      requiresAuth: true,
    );
  }

  // 종합 진단 상태 조회 (인증 필요)
  Future<Map<String, dynamic>> getDiagnosisStatus(String sessionId) async {
    return await _makeRequest(
      'GET',
      '${AWSConfig.getDiagnosisUrl()}/$sessionId',
      requiresAuth: true,
    );
  }

  // 종합 진단 완료 (인증 필요)
  Future<Map<String, dynamic>> completeDiagnosis(String sessionId) async {
    return await _makeRequest(
      'POST',
      '${AWSConfig.getDiagnosisUrl()}/$sessionId/complete',
      requiresAuth: true,
    );
  }

  // 사용자의 모든 종합 진단 조회 (인증 필요)
  Future<Map<String, dynamic>> getUserDiagnoses() async {
    if (!parasolAuth.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    return await _makeRequest(
      'GET',
      '${AWSConfig.getDiagnosisUrl()}/user/${parasolAuth.currentUserId}',
      requiresAuth: true,
    );
  }

  // === 편의 메서드들 ===

  // 아이 트래킹 업로드
  Future<Map<String, dynamic>> uploadEyeTracking({
    required String videoData,
    String? fileName,
    Map<String, dynamic>? parameters,
  }) async {
    return await uploadAnalysis(
      analysisType: 'eye-tracking',
      fileData: videoData,
      fileName: fileName,
      parameters: parameters,
    );
  }

  // 손가락 태핑 업로드
  Future<Map<String, dynamic>> uploadFingerTapping({
    required String videoData,
    String? fileName,
    Map<String, dynamic>? parameters,
  }) async {
    return await uploadAnalysis(
      analysisType: 'finger-tapping',
      fileData: videoData,
      fileName: fileName,
      parameters: parameters,
    );
  }

  // 음성 분석 업로드
  Future<Map<String, dynamic>> uploadVoiceAnalysis({
    required String audioData,
    String? fileName,
    Map<String, dynamic>? parameters,
  }) async {
    return await uploadAnalysis(
      analysisType: 'voice-analysis',
      fileData: audioData,
      fileName: fileName,
      parameters: parameters,
    );
  }

  // 분석 상태를 주기적으로 확인하는 스트림
  Stream<Map<String, dynamic>> watchAnalysisStatus(String analysisId) async* {
    while (true) {
      try {
        final status = await getAnalysisStatus(analysisId);
        yield status;

        // 완료되면 스트림 종료
        if (status['status'] == 'completed' || status['status'] == 'failed') {
          break;
        }

        // 5초 대기
        await Future.delayed(const Duration(seconds: 5));
      } catch (e) {
        yield {
          'success': false,
          'error': e.toString(),
        };
        break;
      }
    }
  }

  // === 헬스 체크 ===
  Future<bool> healthCheck() async {
    try {
      // 간단한 GET 요청으로 API 상태 확인
      final response = await http.get(
        Uri.parse(AWSConfig.apiEndpoint),
        headers: AWSConfig.defaultHeaders,
      ).timeout(const Duration(seconds: 10));

      return response.statusCode < 500; // 500 이상이 아니면 OK
    } catch (e) {
      print('Health check 실패: $e');
      return false;
    }
  }
}

// 전역 인스턴스
final unifiedApi = UnifiedApiService();