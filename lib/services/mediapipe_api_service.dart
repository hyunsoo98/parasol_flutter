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

  /// 시선 추적 분석 (AWS 통합 API 기반) — /api/v1/upload (POST JSON)
  Future<EyeTrackingResult> analyzeEyeTracking({
    required File videoFile,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    try {
      // AWS 통합 업로드 API 사용 (올바른 엔드포인트)
      final uri = Uri.parse('$_baseUrl/api/v1/upload');

      // 파일 존재/크기 체크
      if (!videoFile.existsSync()) {
        throw Exception('비디오 파일이 존재하지 않습니다: ${videoFile.path}');
      }
      final fileSize = await videoFile.length();
      if (fileSize == 0) throw Exception('비디오 파일이 비어있습니다');
      if (fileSize > 100 * 1024 * 1024) {
        throw Exception('비디오 파일이 너무 큽니다: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      // 파일을 base64로 인코딩
      final bytes = await videoFile.readAsBytes();
      final base64Video = base64Encode(bytes);

      // 현재 사용자 ID 가져오기
      if (!parasolAuth.isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // AWS 통합 API 요청 본문 (업로드 엔드포인트 형식)
      final requestBody = {
        'analysis_type': 'eye-tracking',
        'video_data': base64Video,  // 'file_data' -> 'video_data'로 변경
        'user_id': parasolAuth.currentUserId,
        'parameters': {
          'step': step,
          'max_frames': maxFrames,
          'skip_db_save': false,  // DynamoDB 저장 활성화
          // 서버에서 기본값 사용: vpp_thresh=0.06, blink_thresh=0.18
        },
      };

      print('POST $uri');
      print('파일 크기: $fileSize bytes');

      final response = await http.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(requestBody),
      ).timeout(const Duration(minutes: 5));

      print('API 상태: ${response.statusCode}');
      print('API 응답: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // 업로드 성공 - analysis_id 받아서 결과 폴링 시작
        if (data.containsKey('analysisId')) {
          final analysisId = data['analysisId'];
          print('업로드 성공, analysis_id: $analysisId');

          // 결과 폴링 시작
          return await _pollForResults(analysisId);
        } else {
          throw Exception('업로드 응답에 analysisId가 없습니다: $data');
        }
      } else {
        // 상세 에러 메시지
        String msg = '시선 추적 API 호출 실패';
        switch (response.statusCode) {
          case 400: msg = '잘못된 요청 (400): ${response.body}'; break;
          case 401: msg = '인증 실패 (401): 토큰/우회 키 확인'; break;
          case 403: msg = '접근 권한 없음 (403): ${response.body}'; break;
          case 404: msg = '엔드포인트 없음 (404): /api/v1/analyze/eye-tracking'; break;
          case 413: msg = '파일 크기 초과 (413)'; break;
          case 422: msg = '처리 불가 (422): ${response.body}'; break;
          case 500: msg = '서버 내부 오류 (500): ${response.body}'; break;
          case 502: msg = '게이트웨이 오류 (502)'; break;
          case 503: msg = '서비스 불가 (503)'; break;
          default:  msg = '알 수 없는 오류 (${response.statusCode}): ${response.body}';
        }
        throw Exception(msg);
      }
    } catch (e) {
      print('시선 추적 분석 오류: $e');
      throw Exception('시선 추적 분석 실패: $e');
    }
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

  /// 시선 추적 분석 (AWS 통합 API 기반) - bytes 방식
  Future<EyeTrackingResult> analyzeEyeTrackingFromBytes({
    required List<int> videoBytes,
    required String fileName,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    try {
      // AWS 통합 업로드 API 사용 (올바른 엔드포인트)
      final uri = Uri.parse('$_baseUrl/api/v1/upload');

      // 파일 크기 체크
      final fileSize = videoBytes.length;
      if (fileSize == 0) throw Exception('비디오 데이터가 비어있습니다');
      if (fileSize > 100 * 1024 * 1024) {
        throw Exception('비디오 파일이 너무 큽니다: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      // 파일을 base64로 인코딩
      final base64Video = base64Encode(videoBytes);

      // 현재 사용자 ID 가져오기
      if (!parasolAuth.isLoggedIn) {
        throw Exception('로그인이 필요합니다.');
      }

      // AWS 통합 API 요청 본문 (업로드 엔드포인트 형식)
      final requestBody = {
        'analysis_type': 'eye-tracking',
        'video_data': base64Video,  // 'file_data' -> 'video_data'로 변경
        'user_id': parasolAuth.currentUserId,
        'parameters': {
          'step': step,
          'max_frames': maxFrames,
          'skip_db_save': false,  // DynamoDB 저장 활성화
          // 서버에서 기본값 사용: vpp_thresh=0.06, blink_thresh=0.18
        },
      };

      print('POST $uri');
      print('파일 크기: $fileSize bytes');

      final response = await http.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(requestBody),
      ).timeout(const Duration(minutes: 5));

      print('API 상태: ${response.statusCode}');
      print('API 응답: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // 업로드 성공 - analysis_id 받아서 결과 폴링 시작
        if (data.containsKey('analysisId')) {
          final analysisId = data['analysisId'];
          print('업로드 성공, analysis_id: $analysisId');

          // 결과 폴링 시작
          return await _pollForResults(analysisId);
        } else {
          throw Exception('업로드 응답에 analysisId가 없습니다: $data');
        }
      } else {
        // 상세 에러 메시지
        String msg = '시선 추적 API 호출 실패';
        switch (response.statusCode) {
          case 400: msg = '잘못된 요청 (400): ${response.body}'; break;
          case 401: msg = '인증 실패 (401): 토큰/우회 키 확인'; break;
          case 403: msg = '접근 권한 없음 (403): ${response.body}'; break;
          case 404: msg = '엔드포인트 없음 (404): /api/v1/analyze/eye-tracking'; break;
          case 413: msg = '파일 크기 초과 (413)'; break;
          case 422: msg = '처리 불가 (422): ${response.body}'; break;
          case 500: msg = '서버 내부 오류 (500): ${response.body}'; break;
          case 502: msg = '게이트웨이 오류 (502)'; break;
          case 503: msg = '서비스 불가 (503)'; break;
          default:  msg = '알 수 없는 오류 (${response.statusCode}): ${response.body}';
        }
        throw Exception(msg);
      }
    } catch (e) {
      print('시선 추적 분석 오류: $e');
      throw Exception('시선 추적 분석 실패: $e');
    }
  }

  /// 결과 폴링 - /api/v1/status/{analysis_id} 및 /api/v1/results/{analysis_id}
  Future<EyeTrackingResult> _pollForResults(String analysisId) async {
    const maxAttempts = 60; // 최대 5분 대기 (5초 간격)
    const pollInterval = Duration(seconds: 5);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // 상태 확인 - Path Parameter 방식 (API Gateway 구조에 맞춤)
        final statusUri = Uri.parse('$_baseUrl/api/v1/status/$analysisId');
        final statusResponse = await http.get(
          statusUri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        print('상태 확인 ($attempt/$maxAttempts): ${statusResponse.statusCode}');

        if (statusResponse.statusCode == 200) {
          final statusData = json.decode(statusResponse.body);
          final status = statusData['data']['status'];

          print('분석 상태: $status');

          if (status == 'completed') {
            // 완료됨 - 결과 가져오기 (Query Parameter 방식)
            final resultsUri = Uri.parse('$_baseUrl/api/v1/results?analysis_id=$analysisId');
            final resultsResponse = await http.get(
              resultsUri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ).timeout(const Duration(seconds: 10));

            if (resultsResponse.statusCode == 200) {
              final resultsData = json.decode(resultsResponse.body);
              print('분석 결과 받음: ${resultsData['result']}');
              return EyeTrackingResult.fromJson(resultsData['result']);
            } else {
              throw Exception('결과 조회 실패: ${resultsResponse.statusCode} ${resultsResponse.body}');
            }
          } else if (status == 'failed') {
            final error = statusData['data']['error'] ?? '알 수 없는 오류';
            throw Exception('분석 실패: $error');
          } else if (status == 'processing' || status == 'uploaded') {
            // 계속 대기
            print('분석 진행 중... ${statusData['data']['progress'] ?? 0}%');
            if (attempt < maxAttempts - 1) {
              await Future.delayed(pollInterval);
              continue;
            }
          } else {
            throw Exception('알 수 없는 상태: $status');
          }
        } else {
          throw Exception('상태 확인 실패: ${statusResponse.statusCode} ${statusResponse.body}');
        }
      } catch (e) {
        print('폴링 오류 ($attempt): $e');
        if (attempt == maxAttempts - 1) {
          throw Exception('결과 폴링 실패: $e');
        }
        await Future.delayed(pollInterval);
      }
    }

    throw Exception('분석 시간 초과 (5분)');
  }
}
