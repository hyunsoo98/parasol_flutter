import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

/// AWS 순수 비동기 Finger Tapping 서비스
/// FastAPI/Firebase 의존성 없이 AWS Lambda + SQS + DynamoDB 사용
class AwsFingerTappingService {
  // API Gateway URL
  static const String _baseUrl = 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';
  
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _statusTimeout = Duration(seconds: 30);
  static const Duration _pollingInterval = Duration(seconds: 3);

  /// 비동기 Finger Tapping 분석 시작
  static Future<FingerTappingStartResult> startAnalysis({
    required File videoFile,
    required String userId,
    int targetTaps = 10,
    int maxDuration = 30,
    String handPreference = 'both', // 'left', 'right', 'both'
    double threshold = 0.50,
    double delta = 0.05,
  }) async {
    try {
      // 파일 크기 확인 (100MB 제한)
      final fileSize = await videoFile.length();
      if (fileSize > 100 * 1024 * 1024) {
        throw FingerTappingException('파일 크기가 100MB를 초과합니다. 더 작은 파일을 사용해주세요.');
      }

      if (fileSize == 0) {
        throw FingerTappingException('빈 파일입니다.');
      }

      // 비디오를 Base64로 인코딩
      final bytes = await videoFile.readAsBytes();
      final base64Video = base64Encode(bytes);

      final requestBody = {
        'video_data': base64Video,
        'user_id': userId,
        'parameters': {
          'target_taps': targetTaps,
          'max_duration': maxDuration,
          'hand_preference': handPreference,
          'threshold': threshold,
          'delta': delta,
        },
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/analyze/finger-tapping'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(_uploadTimeout);

      if (response.statusCode == 202) {
        final result = jsonDecode(response.body);
        return FingerTappingStartResult.fromJson(result);
      } else {
        final error = jsonDecode(response.body);
        throw FingerTappingException(error['error'] ?? 'Unknown error');
      }
    } on TimeoutException {
      throw FingerTappingException('업로드 시간이 초과되었습니다. 네트워크를 확인해주세요.');
    } on SocketException {
      throw FingerTappingException('네트워크 연결을 확인해주세요.');
    } catch (e) {
      if (e is FingerTappingException) rethrow;
      throw FingerTappingException('분석 시작 실패: $e');
    }
  }

  /// 분석 상태 조회
  static Future<FingerTappingStatus> getAnalysisStatus({
    required String analysisId,
    bool includeResult = true,
    bool generateDownloadUrl = false,
  }) async {
    try {
      final queryParams = {
        'analysis_id': analysisId,
        'analysis_type': 'finger-tapping',
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
        return FingerTappingStatus.fromJson(result['data']);
      } else if (response.statusCode == 404) {
        throw FingerTappingException('분석을 찾을 수 없습니다.');
      } else {
        final error = jsonDecode(response.body);
        throw FingerTappingException(error['error'] ?? 'Unknown error');
      }
    } on TimeoutException {
      throw FingerTappingException('상태 조회 시간이 초과되었습니다.');
    } on SocketException {
      throw FingerTappingException('네트워크 연결을 확인해주세요.');
    } catch (e) {
      if (e is FingerTappingException) rethrow;
      throw FingerTappingException('상태 조회 실패: $e');
    }
  }

  /// 사용자별 Finger Tapping 분석 목록 조회
  static Future<List<FingerTappingSummary>> getUserAnalyses({
    required String userId,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/status')
          .replace(queryParameters: {
            'user_id': userId,
            'analysis_type': 'finger-tapping'
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
        return analyses.map((json) => FingerTappingSummary.fromJson(json)).toList();
      } else {
        final error = jsonDecode(response.body);
        throw FingerTappingException(error['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (e is FingerTappingException) rethrow;
      throw FingerTappingException('분석 목록 조회 실패: $e');
    }
  }

  /// 폴링으로 분석 완료 대기
  static Future<FingerTappingResult> waitForCompletion({
    required String analysisId,
    Duration? timeout,
    Function(int progress, String message)? onProgress,
  }) async {
    final maxWaitTime = timeout ?? const Duration(minutes: 10);
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
          case FingerTappingStatusEnum.completed:
            if (status.result != null) {
              return status.result!;
            } else {
              throw FingerTappingException('분석은 완료되었지만 결과를 찾을 수 없습니다.');
            }

          case FingerTappingStatusEnum.failed:
            throw FingerTappingException(status.error ?? '분석 실패');

          case FingerTappingStatusEnum.processing:
            // 계속 대기
            break;

          default:
            throw FingerTappingException('알 수 없는 분석 상태: ${status.status}');
        }

        // 폴링 간격 대기
        await Future.delayed(_pollingInterval);
      } catch (e) {
        if (e is FingerTappingException) rethrow;
        print('폴링 중 오류: $e');
        await Future.delayed(_pollingInterval);
      }
    }

    throw FingerTappingException('분석 시간이 초과되었습니다 (${maxWaitTime.inMinutes}분)');
  }

  /// 전체 분석 프로세스 (업로드 → 대기 → 결과)
  static Future<FingerTappingResult> analyzeVideoComplete({
    required File videoFile,
    required String userId,
    int targetTaps = 10,
    int maxDuration = 30,
    String handPreference = 'both',
    Duration? timeout,
    Function(String phase, int progress, String message)? onProgress,
  }) async {
    try {
      // 1단계: 분석 시작
      onProgress?.call('upload', 0, '파일 업로드 중...');
      final startResult = await startAnalysis(
        videoFile: videoFile,
        userId: userId,
        targetTaps: targetTaps,
        maxDuration: maxDuration,
        handPreference: handPreference,
      );

      onProgress?.call('processing', 0, 'Finger Tapping 분석 시작됨...');

      // 2단계: 완료 대기
      final result = await waitForCompletion(
        analysisId: startResult.analysisId,
        timeout: timeout,
        onProgress: (progress, message) {
          onProgress?.call('processing', progress, message);
        },
      );

      onProgress?.call('completed', 100, 'Finger Tapping 분석 완료!');
      return result;
    } catch (e) {
      onProgress?.call('error', 0, e.toString());
      rethrow;
    }
  }
}

/// Finger Tapping 분석 시작 결과
class FingerTappingStartResult {
  final String analysisId;
  final String analysisType;
  final String status;
  final String message;
  final int fileSize;
  final int estimatedTime;

  FingerTappingStartResult({
    required this.analysisId,
    required this.analysisType,
    required this.status,
    required this.message,
    required this.fileSize,
    required this.estimatedTime,
  });

  factory FingerTappingStartResult.fromJson(Map<String, dynamic> json) {
    return FingerTappingStartResult(
      analysisId: json['analysis_id'] ?? '',
      analysisType: json['analysis_type'] ?? 'finger-tapping',
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      fileSize: json['file_size'] ?? 0,
      estimatedTime: json['estimated_time'] ?? 180,
    );
  }
}

/// Finger Tapping 분석 상태
enum FingerTappingStatusEnum {
  processing,
  completed,
  failed,
  unknown,
}

FingerTappingStatusEnum parseFingerTappingStatus(String status) {
  switch (status.toLowerCase()) {
    case 'processing':
      return FingerTappingStatusEnum.processing;
    case 'completed':
      return FingerTappingStatusEnum.completed;
    case 'failed':
      return FingerTappingStatusEnum.failed;
    default:
      return FingerTappingStatusEnum.unknown;
  }
}

/// Finger Tapping 분석 상태 정보
class FingerTappingStatus {
  final String analysisId;
  final String userId;
  final String analysisType;
  final FingerTappingStatusEnum status;
  final int timestamp;
  final int progress;
  final String? progressMessage;
  final int? completedAt;
  final int? failedAt;
  final String? error;
  final FingerTappingResult? result;
  final FingerTappingSummaryInfo? summary;
  final List<HandSummary>? handSummary;
  final Map<String, String>? downloadUrls;

  FingerTappingStatus({
    required this.analysisId,
    required this.userId,
    required this.analysisType,
    required this.status,
    required this.timestamp,
    required this.progress,
    this.progressMessage,
    this.completedAt,
    this.failedAt,
    this.error,
    this.result,
    this.summary,
    this.handSummary,
    this.downloadUrls,
  });

  factory FingerTappingStatus.fromJson(Map<String, dynamic> json) {
    return FingerTappingStatus(
      analysisId: json['analysis_id'] ?? '',
      userId: json['user_id'] ?? '',
      analysisType: json['analysis_type'] ?? 'finger-tapping',
      status: parseFingerTappingStatus(json['status'] ?? ''),
      timestamp: json['timestamp'] ?? 0,
      progress: json['progress'] ?? 0,
      progressMessage: json['progress_message'],
      completedAt: json['completed_at'],
      failedAt: json['failed_at'],
      error: json['error'],
      result: json['result'] != null ? FingerTappingResult.fromJson(json['result']) : null,
      summary: json['summary'] != null ? FingerTappingSummaryInfo.fromJson(json['summary']) : null,
      handSummary: json['hand_summary'] != null 
          ? (json['hand_summary'] as List).map((e) => HandSummary.fromJson(e)).toList()
          : null,
      downloadUrls: json['download_urls'] != null 
          ? Map<String, String>.from(json['download_urls']) 
          : null,
    );
  }
}

/// Finger Tapping 분석 요약 정보 (목록용)
class FingerTappingSummary {
  final String analysisId;
  final String analysisType;
  final FingerTappingStatusEnum status;
  final int timestamp;
  final int progress;
  final int fileSize;

  FingerTappingSummary({
    required this.analysisId,
    required this.analysisType,
    required this.status,
    required this.timestamp,
    required this.progress,
    required this.fileSize,
  });

  factory FingerTappingSummary.fromJson(Map<String, dynamic> json) {
    return FingerTappingSummary(
      analysisId: json['analysis_id'] ?? '',
      analysisType: json['analysis_type'] ?? 'finger-tapping',
      status: parseFingerTappingStatus(json['status'] ?? ''),
      timestamp: json['timestamp'] ?? 0,
      progress: json['progress'] ?? 0,
      fileSize: json['file_size'] ?? 0,
    );
  }
}

/// Finger Tapping 분석 결과
class FingerTappingResult {
  final VideoMeta videoMeta;
  final Map<String, dynamic> analysisParams;
  final double durationSec;
  final Map<String, int> tapCounts;
  final List<HandPrediction> handPredictions;
  final CombinedResult combinedResult;

  FingerTappingResult({
    required this.videoMeta,
    required this.analysisParams,
    required this.durationSec,
    required this.tapCounts,
    required this.handPredictions,
    required this.combinedResult,
  });

  factory FingerTappingResult.fromJson(Map<String, dynamic> json) {
    return FingerTappingResult(
      videoMeta: VideoMeta.fromJson(json['video_meta'] ?? {}),
      analysisParams: Map<String, dynamic>.from(json['analysis_params'] ?? {}),
      durationSec: (json['duration_sec'] ?? 0).toDouble(),
      tapCounts: Map<String, int>.from(json['tap_counts'] ?? {}),
      handPredictions: (json['hand_predictions'] as List? ?? [])
          .map((e) => HandPrediction.fromJson(e))
          .toList(),
      combinedResult: CombinedResult.fromJson(json['combined_result'] ?? {}),
    );
  }
}

/// 비디오 메타데이터
class VideoMeta {
  final int width;
  final int height;
  final double fps;
  final int totalFrames;
  final int analyzedFrames;

  VideoMeta({
    required this.width,
    required this.height,
    required this.fps,
    required this.totalFrames,
    required this.analyzedFrames,
  });

  factory VideoMeta.fromJson(Map<String, dynamic> json) {
    return VideoMeta(
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      fps: (json['fps'] ?? 0).toDouble(),
      totalFrames: json['total_frames'] ?? 0,
      analyzedFrames: json['analyzed_frames'] ?? 0,
    );
  }
}

/// 손별 예측 결과
class HandPrediction {
  final String hand;
  final double probability;
  final int prediction;
  final int tapCount;
  final String label;

  HandPrediction({
    required this.hand,
    required this.probability,
    required this.prediction,
    required this.tapCount,
    required this.label,
  });

  factory HandPrediction.fromJson(Map<String, dynamic> json) {
    return HandPrediction(
      hand: json['hand'] ?? '',
      probability: (json['probability'] ?? 0).toDouble(),
      prediction: json['prediction'] ?? 0,
      tapCount: json['tap_count'] ?? 0,
      label: json['label'] ?? '',
    );
  }
}

/// 결합된 최종 결과
class CombinedResult {
  final double probability;
  final int prediction;
  final String label;

  CombinedResult({
    required this.probability,
    required this.prediction,
    required this.label,
  });

  factory CombinedResult.fromJson(Map<String, dynamic> json) {
    return CombinedResult(
      probability: (json['probability'] ?? 0).toDouble(),
      prediction: json['prediction'] ?? 0,
      label: json['label'] ?? '',
    );
  }
}

/// 분석 결과 요약 정보
class FingerTappingSummaryInfo {
  final String diagnosis;
  final double probability;
  final String confidenceLevel;

  FingerTappingSummaryInfo({
    required this.diagnosis,
    required this.probability,
    required this.confidenceLevel,
  });

  factory FingerTappingSummaryInfo.fromJson(Map<String, dynamic> json) {
    return FingerTappingSummaryInfo(
      diagnosis: json['diagnosis'] ?? '',
      probability: (json['probability'] ?? 0).toDouble(),
      confidenceLevel: json['confidence_level'] ?? '',
    );
  }
}

/// 손별 요약 정보
class HandSummary {
  final String hand;
  final int tapCount;
  final String diagnosis;
  final double probability;

  HandSummary({
    required this.hand,
    required this.tapCount,
    required this.diagnosis,
    required this.probability,
  });

  factory HandSummary.fromJson(Map<String, dynamic> json) {
    return HandSummary(
      hand: json['hand'] ?? '',
      tapCount: json['tap_count'] ?? 0,
      diagnosis: json['diagnosis'] ?? '',
      probability: (json['probability'] ?? 0).toDouble(),
    );
  }
}

/// Finger Tapping 분석 예외
class FingerTappingException implements Exception {
  final String message;
  FingerTappingException(this.message);

  @override
  String toString() => 'FingerTappingException: $message';
}