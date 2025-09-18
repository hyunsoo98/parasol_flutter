import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

/// AWS 순수 비동기 Eye Tracking 서비스
/// FastAPI/Firebase 의존성 없이 AWS Lambda + SQS + DynamoDB 사용
class AwsAsyncEyeTrackingService {
  // API Gateway URL - Replace with your actual API Gateway ID
  static const String _baseUrl = 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';
  
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _statusTimeout = Duration(seconds: 30);
  static const Duration _pollingInterval = Duration(seconds: 5);

  /// 비동기 분석 시작 (파일 업로드 및 큐 전송)
  static Future<AnalysisStartResult> startAnalysis({
    required File videoFile,
    required String userId,
    int step = 1,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
    int blinkMinFrames = 2,
  }) async {
    try {
      // 파일 크기 확인 (100MB 제한)
      final fileSize = await videoFile.length();
      if (fileSize > 100 * 1024 * 1024) {
        throw AnalysisException('파일 크기가 100MB를 초과합니다. 더 작은 파일을 사용해주세요.');
      }

      if (fileSize == 0) {
        throw AnalysisException('빈 파일입니다.');
      }

      // 비디오를 Base64로 인코딩
      final bytes = await videoFile.readAsBytes();
      final base64Video = base64Encode(bytes);

      final requestBody = {
        'video_data': base64Video,
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
        Uri.parse('$_baseUrl/api/v1/analyze/eye-tracking'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(_uploadTimeout);

      if (response.statusCode == 202) {
        final result = jsonDecode(response.body);
        return AnalysisStartResult.fromJson(result);
      } else {
        final error = jsonDecode(response.body);
        throw AnalysisException(error['error'] ?? 'Unknown error');
      }
    } on TimeoutException {
      throw AnalysisException('업로드 시간이 초과되었습니다. 네트워크를 확인해주세요.');
    } on SocketException {
      throw AnalysisException('네트워크 연결을 확인해주세요.');
    } catch (e) {
      if (e is AnalysisException) rethrow;
      throw AnalysisException('분석 시작 실패: $e');
    }
  }

  /// 분석 상태 조회
  static Future<AnalysisStatus> getAnalysisStatus({
    required String analysisId,
    bool includeResult = true,
    bool generateDownloadUrl = false,
  }) async {
    try {
      final queryParams = {
        'analysis_id': analysisId,
        'analysis_type': 'eye-tracking',
        'include_result': includeResult.toString(),
        'download_url': generateDownloadUrl.toString(),
      };

      final uri = Uri.parse('$_baseUrl/api/v1/status')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_statusTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return AnalysisStatus.fromJson(result['data']);
      } else if (response.statusCode == 404) {
        throw AnalysisException('분석을 찾을 수 없습니다.');
      } else {
        final error = jsonDecode(response.body);
        throw AnalysisException(error['error'] ?? 'Unknown error');
      }
    } on TimeoutException {
      throw AnalysisException('상태 조회 시간이 초과되었습니다.');
    } on SocketException {
      throw AnalysisException('네트워크 연결을 확인해주세요.');
    } catch (e) {
      if (e is AnalysisException) rethrow;
      throw AnalysisException('상태 조회 실패: $e');
    }
  }

  /// 사용자별 분석 목록 조회
  static Future<List<AnalysisSummary>> getUserAnalyses({
    required String userId,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/status')
          .replace(queryParameters: {
            'user_id': userId,
            'analysis_type': 'eye-tracking'
          });

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_statusTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final List<dynamic> analyses = result['analyses'] ?? [];
        return analyses.map((json) => AnalysisSummary.fromJson(json)).toList();
      } else {
        final error = jsonDecode(response.body);
        throw AnalysisException(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (e is AnalysisException) rethrow;
      throw AnalysisException('분석 목록 조회 실패: $e');
    }
  }

  /// 폴링으로 분석 완료 대기
  static Future<AnalysisResult> waitForCompletion({
    required String analysisId,
    Duration? timeout,
    Function(int progress, String message)? onProgress,
  }) async {
    final maxWaitTime = timeout ?? const Duration(minutes: 20);
    final stopTime = DateTime.now().add(maxWaitTime);

    while (DateTime.now().isBefore(stopTime)) {
      try {
        final status = await getAnalysisStatus(
          analysisId: analysisId,
          includeResult: true,
          generateDownloadUrl: true,
        );

        // 진행률 콜백 호출
        onProgress?.call(status.progress, status.progressMessage ?? '');

        switch (status.status) {
          case AnalysisStatusEnum.completed:
            if (status.result != null) {
              return status.result!;
            } else {
              throw AnalysisException('분석은 완료되었지만 결과를 찾을 수 없습니다.');
            }

          case AnalysisStatusEnum.failed:
            throw AnalysisException(status.error ?? '분석 실패');

          case AnalysisStatusEnum.processing:
            // 계속 대기
            break;

          default:
            throw AnalysisException('알 수 없는 분석 상태: ${status.status}');
        }

        // 폴링 간격 대기
        await Future.delayed(_pollingInterval);
      } catch (e) {
        if (e is AnalysisException) rethrow;
        print('폴링 중 오류: $e');
        await Future.delayed(_pollingInterval);
      }
    }

    throw AnalysisException('분석 시간이 초과되었습니다 (${maxWaitTime.inMinutes}분)');
  }

  /// 전체 분석 프로세스 (업로드 → 대기 → 결과)
  static Future<AnalysisResult> analyzeVideoComplete({
    required File videoFile,
    required String userId,
    int step = 1,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
    Duration? timeout,
    Function(String phase, int progress, String message)? onProgress,
  }) async {
    try {
      // 1단계: 분석 시작
      onProgress?.call('upload', 0, '파일 업로드 중...');
      final startResult = await startAnalysis(
        videoFile: videoFile,
        userId: userId,
        step: step,
        vppThresh: vppThresh,
        blinkThresh: blinkThresh,
        maxFrames: maxFrames,
      );

      onProgress?.call('processing', 0, '분석 시작됨...');

      // 2단계: 완료 대기
      final result = await waitForCompletion(
        analysisId: startResult.analysisId,
        timeout: timeout,
        onProgress: (progress, message) {
          onProgress?.call('processing', progress, message);
        },
      );

      onProgress?.call('completed', 100, '분석 완료!');
      return result;
    } catch (e) {
      onProgress?.call('error', 0, e.toString());
      rethrow;
    }
  }
}

/// 분석 시작 결과
class AnalysisStartResult {
  final String analysisId;
  final String status;
  final String message;
  final int fileSize;
  final int estimatedTime;

  AnalysisStartResult({
    required this.analysisId,
    required this.status,
    required this.message,
    required this.fileSize,
    required this.estimatedTime,
  });

  factory AnalysisStartResult.fromJson(Map<String, dynamic> json) {
    return AnalysisStartResult(
      analysisId: json['analysis_id'] ?? '',
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      fileSize: json['file_size'] ?? 0,
      estimatedTime: json['estimated_time'] ?? 300,
    );
  }
}

/// 분석 상태
enum AnalysisStatusEnum {
  processing,
  completed,
  failed,
  unknown,
}

AnalysisStatusEnum parseAnalysisStatus(String status) {
  switch (status.toLowerCase()) {
    case 'processing':
      return AnalysisStatusEnum.processing;
    case 'completed':
      return AnalysisStatusEnum.completed;
    case 'failed':
      return AnalysisStatusEnum.failed;
    default:
      return AnalysisStatusEnum.unknown;
  }
}

/// 분석 상태 정보
class AnalysisStatus {
  final String analysisId;
  final String userId;
  final AnalysisStatusEnum status;
  final int timestamp;
  final int progress;
  final String? progressMessage;
  final int? completedAt;
  final int? failedAt;
  final String? error;
  final AnalysisResult? result;
  final Map<String, String>? downloadUrls;

  AnalysisStatus({
    required this.analysisId,
    required this.userId,
    required this.status,
    required this.timestamp,
    required this.progress,
    this.progressMessage,
    this.completedAt,
    this.failedAt,
    this.error,
    this.result,
    this.downloadUrls,
  });

  factory AnalysisStatus.fromJson(Map<String, dynamic> json) {
    return AnalysisStatus(
      analysisId: json['analysis_id'] ?? '',
      userId: json['user_id'] ?? '',
      status: parseAnalysisStatus(json['status'] ?? ''),
      timestamp: json['timestamp'] ?? 0,
      progress: json['progress'] ?? 0,
      progressMessage: json['progress_message'],
      completedAt: json['completed_at'],
      failedAt: json['failed_at'],
      error: json['error'],
      result: json['result'] != null ? AnalysisResult.fromJson(json['result']) : null,
      downloadUrls: json['download_urls'] != null 
          ? Map<String, String>.from(json['download_urls']) 
          : null,
    );
  }
}

/// 분석 요약 정보 (목록용)
class AnalysisSummary {
  final String analysisId;
  final AnalysisStatusEnum status;
  final int timestamp;
  final int progress;
  final int fileSize;

  AnalysisSummary({
    required this.analysisId,
    required this.status,
    required this.timestamp,
    required this.progress,
    required this.fileSize,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) {
    return AnalysisSummary(
      analysisId: json['analysis_id'] ?? '',
      status: parseAnalysisStatus(json['status'] ?? ''),
      timestamp: json['timestamp'] ?? 0,
      progress: json['progress'] ?? 0,
      fileSize: json['file_size'] ?? 0,
    );
  }
}

/// 분석 결과
class AnalysisResult {
  final int framesProcessed;
  final double fps;
  final double durationSec;
  final VideoMeta videoMeta;
  final VerticalMovement verticalMovement;
  final BlinkAnalysis blinkAnalysis;
  final PspScreening pspScreening;

  AnalysisResult({
    required this.framesProcessed,
    required this.fps,
    required this.durationSec,
    required this.videoMeta,
    required this.verticalMovement,
    required this.blinkAnalysis,
    required this.pspScreening,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      framesProcessed: json['frames_processed'] ?? 0,
      fps: (json['fps'] ?? 0).toDouble(),
      durationSec: (json['duration_sec'] ?? 0).toDouble(),
      videoMeta: VideoMeta.fromJson(json['video_meta'] ?? {}),
      verticalMovement: VerticalMovement.fromJson(json['vertical_movement'] ?? {}),
      blinkAnalysis: BlinkAnalysis.fromJson(json['blink_analysis'] ?? {}),
      pspScreening: PspScreening.fromJson(json['psp_screening'] ?? {}),
    );
  }
}

/// 비디오 메타데이터
class VideoMeta {
  final int width;
  final int height;
  final double fps;
  final int totalFrames;

  VideoMeta({
    required this.width,
    required this.height,
    required this.fps,
    required this.totalFrames,
  });

  factory VideoMeta.fromJson(Map<String, dynamic> json) {
    return VideoMeta(
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      fps: (json['fps'] ?? 0).toDouble(),
      totalFrames: json['total_frames'] ?? 0,
    );
  }
}

/// 수직 움직임 분석
class VerticalMovement {
  final double std;
  final double peakToPeak;

  VerticalMovement({
    required this.std,
    required this.peakToPeak,
  });

  factory VerticalMovement.fromJson(Map<String, dynamic> json) {
    return VerticalMovement(
      std: (json['std'] ?? 0).toDouble(),
      peakToPeak: (json['peak_to_peak'] ?? 0).toDouble(),
    );
  }
}

/// 블링크 분석
class BlinkAnalysis {
  final int count;
  final double ratePerMinute;

  BlinkAnalysis({
    required this.count,
    required this.ratePerMinute,
  });

  factory BlinkAnalysis.fromJson(Map<String, dynamic> json) {
    return BlinkAnalysis(
      count: json['count'] ?? 0,
      ratePerMinute: (json['rate_per_minute'] ?? 0).toDouble(),
    );
  }
}

/// PSP 스크리닝
class PspScreening {
  final bool suspected;
  final double thresholdUsed;
  final double verticalPtpMeasured;

  PspScreening({
    required this.suspected,
    required this.thresholdUsed,
    required this.verticalPtpMeasured,
  });

  factory PspScreening.fromJson(Map<String, dynamic> json) {
    return PspScreening(
      suspected: json['suspected'] ?? false,
      thresholdUsed: (json['threshold_used'] ?? 0).toDouble(),
      verticalPtpMeasured: (json['vertical_ptp_measured'] ?? 0).toDouble(),
    );
  }
}

/// 분석 예외
class AnalysisException implements Exception {
  final String message;
  AnalysisException(this.message);

  @override
  String toString() => 'AnalysisException: $message';
}