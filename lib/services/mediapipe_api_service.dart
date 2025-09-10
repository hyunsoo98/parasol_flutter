// lib/services/mediapipe_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/diagnosis_result.dart';

class MediaPipeApiService {
  static const String _baseUrl = 'https://8426dcee48d2.ngrok-free.app'; // Python API

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
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken(true); // 갱신
    } catch (e) {
      print('토큰 가져오기 실패: $e');
      return null;
    }
  }

  // 인증/공통 헤더 (멀티파트에서는 Content-Type 설정 금지)
  Future<Map<String, String>> _authHeaders() async {
    final token = await _getAuthToken();
    return {
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
      if (_devKey != null) 'X-Dev-Key': _devKey!,
      if (_devUser != null) 'X-Dev-User': _devUser!,
      'Accept': 'application/json',
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

  /// 시선 추적 분석 (MediaPipe 기반) — /eye/process (POST multipart)
  Future<EyeTrackingResult> analyzeEyeTracking({
    required File videoFile,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    try {
      // 쿼리 파라미터
      final uri = Uri.parse('$_baseUrl/eye/process').replace(queryParameters: {
        'step': step.toString(),
        'vpp_thresh': vppThresh.toString(),
        'blink_thresh': blinkThresh.toString(),
        'max_frames': maxFrames.toString(),
        'save': 'true',
        'return_overlay': 'false',
      });

      // 파일 존재/크기 체크
      if (!videoFile.existsSync()) {
        throw Exception('비디오 파일이 존재하지 않습니다: ${videoFile.path}');
      }
      final fileSize = await videoFile.length();
      if (fileSize == 0) throw Exception('비디오 파일이 비어있습니다');
      if (fileSize > 200 * 1024 * 1024) {
        throw Exception('비디오 파일이 너무 큽니다: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));
      request.headers.addAll(await _authHeaders());

      print('POST $uri');
      print('요청 헤더: ${request.headers}');
      print('파일 크기: ${fileSize} bytes');

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final respBody = await streamed.stream.transform(utf8.decoder).join();

      print('API 상태: ${streamed.statusCode}');
      print('API 응답: $respBody');

      if (streamed.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(respBody);
        return EyeTrackingResult.fromJson(data);
      } else {
        // 상세 에러 메시지
        String msg = '시선 추적 API 호출 실패';
        switch (streamed.statusCode) {
          case 400: msg = '잘못된 요청 (400): $respBody'; break;
          case 401: msg = '인증 실패 (401): 토큰/우회 키 확인'; break;
          case 404: msg = '엔드포인트 없음 (404): /eye/process'; break;
          case 413: msg = '파일 크기 초과 (413)'; break;
          case 422: msg = '처리 불가 (422): $respBody'; break;
          case 500: msg = '서버 내부 오류 (500): $respBody'; break;
          case 502: msg = '게이트웨이 오류 (502)'; break;
          case 503: msg = '서비스 불가 (503)'; break;
          default:  msg = '알 수 없는 오류 (${streamed.statusCode}): $respBody';
        }
        throw Exception(msg);
      }
    } catch (e) {
      print('시선 추적 분석 오류: $e');
      throw Exception('시선 추적 분석 실패: $e');
    }
  }

  /// 서버 상태 확인 — /healthz (GET)
  Future<bool> checkServerHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl/healthz');
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

  /// 시선 추적 분석 (MediaPipe 기반) - bytes 방식
  Future<EyeTrackingResult> analyzeEyeTrackingFromBytes({
    required List<int> videoBytes,
    required String fileName,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    try {
      // 쿼리 파라미터
      final uri = Uri.parse('$_baseUrl/eye/process').replace(queryParameters: {
        'step': step.toString(),
        'vpp_thresh': vppThresh.toString(),
        'blink_thresh': blinkThresh.toString(),
        'max_frames': maxFrames.toString(),
        'save': 'true',
        'return_overlay': 'false',
      });

      final request = http.MultipartRequest('POST', uri);

      // 파일 크기 체크
      final fileSize = videoBytes.length;
      if (fileSize == 0) throw Exception('비디오 데이터가 비어있습니다');
      if (fileSize > 200 * 1024 * 1024) {
        throw Exception('비디오 파일이 너무 큽니다: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      // bytes로 파일 추가
      request.files.add(
        http.MultipartFile.fromBytes(
          'file', 
          videoBytes,
          filename: fileName,
        ),
      );

      request.headers.addAll(await _authHeaders());

      print('POST $uri');
      print('요청 헤더: ${request.headers}');
      print('파일 크기: $fileSize bytes');

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final respBody = await streamed.stream.transform(utf8.decoder).join();

      print('API 상태: ${streamed.statusCode}');
      print('API 응답: $respBody');

      if (streamed.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(respBody);
        return EyeTrackingResult.fromJson(data);
      } else {
        // 상세 에러 메시지
        String msg = '시선 추적 API 호출 실패';
        switch (streamed.statusCode) {
          case 400: msg = '잘못된 요청 (400): $respBody'; break;
          case 401: msg = '인증 실패 (401): 토큰/우회 키 확인'; break;
          case 404: msg = '엔드포인트 없음 (404): /eye/process'; break;
          case 413: msg = '파일 크기 초과 (413)'; break;
          case 422: msg = '처리 불가 (422): $respBody'; break;
          case 500: msg = '서버 내부 오류 (500): $respBody'; break;
          case 502: msg = '게이트웨이 오류 (502)'; break;
          case 503: msg = '서비스 불가 (503)'; break;
          default:  msg = '알 수 없는 오류 (${streamed.statusCode}): $respBody';
        }
        throw Exception(msg);
      }
    } catch (e) {
      print('시선 추적 분석 오류: $e');
      throw Exception('시선 추적 분석 실패: $e');
    }
  }
}
