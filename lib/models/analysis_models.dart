// lib/models/analysis_models.dart

/// 분석 상태를 나타내는 열거형
enum AnalysisStatusType {
  uploaded,
  processing,
  completed,
  failed,
  cancelled
}

/// 분석 타입을 나타내는 열거형
enum AnalysisType {
  eyeTracking,
  fingerTapping,
  voiceAnalysis
}

/// 업로드 응답 모델
class UploadResponse {
  final String analysisId;
  final String analysisType;
  final String status;
  final String s3Key;
  final int timestamp;
  final String estimatedProcessingTime;

  const UploadResponse({
    required this.analysisId,
    required this.analysisType,
    required this.status,
    required this.s3Key,
    required this.timestamp,
    required this.estimatedProcessingTime,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    return UploadResponse(
      analysisId: json['analysisId'] ?? '',
      analysisType: json['analysis_type'] ?? '',
      status: json['status'] ?? '',
      s3Key: json['s3_key'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      estimatedProcessingTime: json['estimated_processing_time'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'analysisId': analysisId,
      'analysis_type': analysisType,
      'status': status,
      's3_key': s3Key,
      'timestamp': timestamp,
      'estimated_processing_time': estimatedProcessingTime,
    };
  }
}

/// 분석 상태 모델
class AnalysisStatus {
  final String analysisId;
  final String userId;
  final String analysisType;
  final AnalysisStatusType status;
  final int progress; // 0-100
  final String progressMessage;
  final DateTime timestamp;
  final int? estimatedCompletion; // 예상 완료까지 남은 시간 (초)
  final DateTime? completedAt;
  final DateTime? failedAt;
  final String? errorMessage;
  final Map<String, dynamic>? parameters;
  final Map<String, dynamic>? fileInfo;

  const AnalysisStatus({
    required this.analysisId,
    required this.userId,
    required this.analysisType,
    required this.status,
    required this.progress,
    required this.progressMessage,
    required this.timestamp,
    this.estimatedCompletion,
    this.completedAt,
    this.failedAt,
    this.errorMessage,
    this.parameters,
    this.fileInfo,
  });

  factory AnalysisStatus.fromJson(Map<String, dynamic> json) {
    return AnalysisStatus(
      analysisId: json['analysisId'] ?? '',
      userId: json['user_id'] ?? '',
      analysisType: json['analysis_type'] ?? '',
      status: _parseStatus(json['status']),
      progress: (json['progress'] ?? 0).toInt(),
      progressMessage: json['progress_message'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] ?? 0) * 1000),
      estimatedCompletion: json['estimated_completion'],
      completedAt: json['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['completed_at'] * 1000)
          : null,
      failedAt: json['failed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['failed_at'] * 1000)
          : null,
      errorMessage: json['error'],
      parameters: json['parameters'],
      fileInfo: json['file_info'],
    );
  }

  static AnalysisStatusType _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'uploaded':
        return AnalysisStatusType.uploaded;
      case 'processing':
        return AnalysisStatusType.processing;
      case 'completed':
        return AnalysisStatusType.completed;
      case 'failed':
        return AnalysisStatusType.failed;
      case 'cancelled':
        return AnalysisStatusType.cancelled;
      default:
        return AnalysisStatusType.uploaded;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'analysisId': analysisId,
      'user_id': userId,
      'analysis_type': analysisType,
      'status': status.name,
      'progress': progress,
      'progress_message': progressMessage,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'estimated_completion': estimatedCompletion,
      'completed_at': completedAt != null ? completedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'failed_at': failedAt != null ? failedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'error': errorMessage,
      'parameters': parameters,
      'file_info': fileInfo,
    };
  }

  /// 분석이 완료되었는지 확인
  bool get isCompleted => status == AnalysisStatusType.completed;

  /// 분석이 진행 중인지 확인
  bool get isProcessing => status == AnalysisStatusType.processing;

  /// 분석이 실패했는지 확인
  bool get isFailed => status == AnalysisStatusType.failed;

  /// 분석이 업로드 상태인지 확인
  bool get isUploaded => status == AnalysisStatusType.uploaded;
}

/// 다운로드 URL 모델
class DownloadUrl {
  final String type; // 'csv', 'json', 'video', etc.
  final String url;
  final String? contentType;
  final int? fileSize;
  final DateTime expiresAt;

  const DownloadUrl({
    required this.type,
    required this.url,
    this.contentType,
    this.fileSize,
    required this.expiresAt,
  });

  factory DownloadUrl.fromJson(Map<String, dynamic> json) {
    return DownloadUrl(
      type: json['type'] ?? '',
      url: json['url'] ?? '',
      contentType: json['content_type'],
      fileSize: json['file_size'],
      expiresAt: DateTime.parse(json['expires_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'url': url,
      'content_type': contentType,
      'file_size': fileSize,
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  /// URL이 만료되었는지 확인
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// 분석 결과 모델
class AnalysisResult {
  final String analysisId;
  final String analysisType;
  final Map<String, dynamic> result;
  final Map<String, dynamic> summary;
  final List<DownloadUrl> downloadUrls;
  final DateTime completedAt;

  const AnalysisResult({
    required this.analysisId,
    required this.analysisType,
    required this.result,
    required this.summary,
    required this.downloadUrls,
    required this.completedAt,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      analysisId: json['analysisId'] ?? '',
      analysisType: json['analysis_type'] ?? '',
      result: json['result'] ?? {},
      summary: json['summary'] ?? {},
      downloadUrls: (json['download_urls'] as List<dynamic>?)
          ?.map((url) => DownloadUrl.fromJson(url))
          .toList() ?? [],
      completedAt: DateTime.parse(json['completed_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'analysisId': analysisId,
      'analysis_type': analysisType,
      'result': result,
      'summary': summary,
      'download_urls': downloadUrls.map((url) => url.toJson()).toList(),
      'completed_at': completedAt.toIso8601String(),
    };
  }

  /// 특정 타입의 다운로드 URL 가져오기
  DownloadUrl? getDownloadUrl(String type) {
    return downloadUrls.where((url) => url.type == type).firstOrNull;
  }

  /// CSV 다운로드 URL 가져오기
  DownloadUrl? get csvDownloadUrl => getDownloadUrl('csv');

  /// JSON 다운로드 URL 가져오기
  DownloadUrl? get jsonDownloadUrl => getDownloadUrl('json');
}

/// 분석 기록 모델 (목록 표시용)
class AnalysisRecord {
  final String analysisId;
  final String analysisType;
  final AnalysisStatusType status;
  final DateTime timestamp;
  final int progress;
  final int? fileSize;
  final String? diagnosis; // 요약 진단 결과
  final double? confidence; // 신뢰도

  const AnalysisRecord({
    required this.analysisId,
    required this.analysisType,
    required this.status,
    required this.timestamp,
    required this.progress,
    this.fileSize,
    this.diagnosis,
    this.confidence,
  });

  factory AnalysisRecord.fromJson(Map<String, dynamic> json) {
    return AnalysisRecord(
      analysisId: json['analysisId'] ?? '',
      analysisType: json['analysis_type'] ?? '',
      status: AnalysisStatus._parseStatus(json['status']),
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] ?? 0) * 1000),
      progress: (json['progress'] ?? 0).toInt(),
      fileSize: json['file_size'],
      diagnosis: json['diagnosis'],
      confidence: json['confidence']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'analysisId': analysisId,
      'analysis_type': analysisType,
      'status': status.name,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'progress': progress,
      'file_size': fileSize,
      'diagnosis': diagnosis,
      'confidence': confidence,
    };
  }

  /// 사용자 친화적인 분석 타입 이름
  String get displayAnalysisType {
    switch (analysisType.toLowerCase()) {
      case 'eye-tracking':
      case 'eye-tracking-results':
        return '시선 추적';
      case 'finger-tapping':
        return '손가락 탭핑';
      case 'voice-analysis':
        return '음성 분석';
      default:
        return analysisType;
    }
  }

  /// 상태에 따른 색상
  String get statusColor {
    switch (status) {
      case AnalysisStatusType.completed:
        return '#4CAF50'; // 녹색
      case AnalysisStatusType.processing:
        return '#FF9800'; // 주황색
      case AnalysisStatusType.failed:
        return '#F44336'; // 빨간색
      case AnalysisStatusType.uploaded:
        return '#2196F3'; // 파란색
      case AnalysisStatusType.cancelled:
        return '#9E9E9E'; // 회색
    }
  }

  /// 사용자 친화적인 상태 메시지
  String get displayStatus {
    switch (status) {
      case AnalysisStatusType.uploaded:
        return '업로드됨';
      case AnalysisStatusType.processing:
        return '분석 중';
      case AnalysisStatusType.completed:
        return '완료됨';
      case AnalysisStatusType.failed:
        return '실패';
      case AnalysisStatusType.cancelled:
        return '취소됨';
    }
  }
}

/// 배치 업로드 상태
class BatchUploadStatus {
  final List<AnalysisStatus> analyses;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final int processingCount;

  const BatchUploadStatus({
    required this.analyses,
    required this.totalCount,
    required this.completedCount,
    required this.failedCount,
    required this.processingCount,
  });

  factory BatchUploadStatus.fromAnalyses(List<AnalysisStatus> analyses) {
    final completed = analyses.where((a) => a.isCompleted).length;
    final failed = analyses.where((a) => a.isFailed).length;
    final processing = analyses.where((a) => a.isProcessing).length;

    return BatchUploadStatus(
      analyses: analyses,
      totalCount: analyses.length,
      completedCount: completed,
      failedCount: failed,
      processingCount: processing,
    );
  }

  /// 전체 진행률 (0-100)
  double get overallProgress {
    if (totalCount == 0) return 0.0;
    final totalProgress = analyses.fold<double>(0.0, (sum, analysis) => sum + analysis.progress);
    return totalProgress / totalCount;
  }

  /// 완료 비율 (0.0-1.0)
  double get completionRate {
    if (totalCount == 0) return 0.0;
    return completedCount / totalCount;
  }

  /// 실패 비율 (0.0-1.0)
  double get failureRate {
    if (totalCount == 0) return 0.0;
    return failedCount / totalCount;
  }

  /// 모든 분석이 완료되었는지 확인
  bool get isAllCompleted => completedCount == totalCount;

  /// 진행 중인 분석이 있는지 확인
  bool get hasProcessing => processingCount > 0;
}