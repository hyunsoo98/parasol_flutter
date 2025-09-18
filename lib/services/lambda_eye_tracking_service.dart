import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class LambdaEyeTrackingService {
  // API Gateway URL (배포 후 실제 URL로 변경)
  static const String _apiGatewayUrl = 'https://your-api-id.execute-api.us-west-1.amazonaws.com/prod';
  
  // 분석 결과 모델
  static const Duration _timeout = Duration(minutes: 5);

  /// 이미지 분석 (단일 프레임)
  static Future<Map<String, dynamic>> analyzeImage({
    required File imageFile,
    required String userId,
  }) async {
    try {
      // 이미지를 Base64로 인코딩
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final requestBody = {
        'action': 'analyze_image',
        'file_data': base64Image,
        'user_id': userId,
      };

      final response = await http.post(
        Uri.parse('$_apiGatewayUrl/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return {
          'success': true,
          'data': result,
        };
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('이미지 분석 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 비디오 분석 (전체 파일)
  static Future<Map<String, dynamic>> analyzeVideo({
    required File videoFile,
    required String userId,
    int step = 1,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
    int blinkMinFrames = 2,
  }) async {
    try {
      // 파일 크기 확인 (Lambda 제한: 6MB)
      final fileSize = await videoFile.length();
      if (fileSize > 6 * 1024 * 1024) {
        return {
          'success': false,
          'error': '파일 크기가 너무 큽니다. 6MB 이하의 파일을 사용해주세요.',
        };
      }

      // 비디오를 Base64로 인코딩
      final bytes = await videoFile.readAsBytes();
      final base64Video = base64Encode(bytes);

      final requestBody = {
        'action': 'analyze_video',
        'file_data': base64Video,
        'user_id': userId,
        'parameters': {
          'step': step,
          'vpp_thresh': vppThresh,
          'blink_thresh': blinkThresh,
          'max_frames': maxFrames,
          'blink_min_frames': blinkMinFrames,
        },
      };

      final response = await http.post(
        Uri.parse('$_apiGatewayUrl/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return {
          'success': true,
          'data': result,
        };
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('비디오 분석 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// S3에 업로드된 파일 분석
  static Future<Map<String, dynamic>> analyzeS3File({
    required String s3Key,
    required String fileName,
    required String userId,
  }) async {
    try {
      final requestBody = {
        'action': 'process_s3_file',
        's3_key': s3Key,
        'file_name': fileName,
        'user_id': userId,
      };

      final response = await http.post(
        Uri.parse('$_apiGatewayUrl/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return {
          'success': true,
          'data': result,
        };
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('S3 파일 분석 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 비디오를 청크로 나누어 분석 (대용량 파일용)
  static Future<Map<String, dynamic>> analyzeVideoInChunks({
    required File videoFile,
    required String userId,
    int chunkDurationSeconds = 30,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      // TODO: 비디오를 작은 청크로 나누는 로직 구현
      // FFmpeg 또는 다른 비디오 처리 라이브러리 사용
      
      // 현재는 전체 파일 분석으로 폴백
      return await analyzeVideo(
        videoFile: videoFile,
        userId: userId,
        step: parameters?['step'] ?? 1,
        vppThresh: parameters?['vpp_thresh'] ?? 0.06,
        blinkThresh: parameters?['blink_thresh'] ?? 0.18,
        maxFrames: parameters?['max_frames'] ?? 12000,
      );
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 분석 상태 확인 (비동기 처리용)
  static Future<Map<String, dynamic>> getAnalysisStatus({
    required String analysisId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiGatewayUrl/status/$analysisId'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return {
          'success': true,
          'data': result,
        };
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('분석 상태 확인 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 분석 결과 파싱 및 검증
  static Map<String, dynamic> parseAnalysisResult(Map<String, dynamic> rawResult) {
    try {
      final summary = rawResult['summary'] ?? {};
      
      return {
        'frames_processed': summary['frames_processed'] ?? 0,
        'duration_sec': summary['duration_sec_est'] ?? 0.0,
        'vertical_movement': {
          'std': summary['vertical_offset_std'] ?? 0.0,
          'peak_to_peak': summary['vertical_peak_to_peak'] ?? 0.0,
        },
        'blink_analysis': {
          'count': summary['blink_count'] ?? 0,
          'rate_per_minute': summary['blink_rate_per_min'] ?? 0.0,
        },
        'psp_screening': {
          'suspected': summary['psp_suspected'] ?? false,
          'reason': summary['psp_rule_reason'] ?? '',
        },
        'video_meta': summary['video_meta'] ?? {},
        'analysis_id': rawResult['analysis_id'],
        'video_path': rawResult['video_path'],
        'csv_path': rawResult['csv_path'],
      };
    } catch (e) {
      throw Exception('결과 파싱 오류: $e');
    }
  }

  /// 오류 메시지 현지화
  static String getLocalizedError(String error) {
    if (error.contains('file size')) {
      return '파일 크기가 너무 큽니다. 더 작은 파일을 사용해주세요.';
    } else if (error.contains('timeout')) {
      return '분석 시간이 초과되었습니다. 다시 시도해주세요.';
    } else if (error.contains('network')) {
      return '네트워크 연결을 확인해주세요.';
    } else if (error.contains('Invalid image')) {
      return '올바르지 않은 이미지 파일입니다.';
    } else if (error.contains('Cannot open video')) {
      return '비디오 파일을 열 수 없습니다.';
    } else {
      return '분석 중 오류가 발생했습니다: $error';
    }
  }
}