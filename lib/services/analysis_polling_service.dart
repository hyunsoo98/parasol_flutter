// lib/services/analysis_polling_service.dart
import 'dart:async';
import 'dart:math';
import 'unified_api_service.dart';

enum AnalysisStatus {
  uploaded,    // 업로드 완료, 처리 대기
  processing,  // 처리 중
  completed,   // 완료
  failed,      // 실패
  unknown,     // 알 수 없음
}

class AnalysisProgress {
  final String analysisId;
  final String analysisType;
  final AnalysisStatus status;
  final int progress; // 0-100
  final String? message;
  final Map<String, dynamic>? results;
  final String? error;
  final DateTime timestamp;

  AnalysisProgress({
    required this.analysisId,
    required this.analysisType,
    required this.status,
    required this.progress,
    this.message,
    this.results,
    this.error,
    required this.timestamp,
  });

  factory AnalysisProgress.fromApiResponse(Map<String, dynamic> response) {
    return AnalysisProgress(
      analysisId: response['analysis_id'] ?? '',
      analysisType: response['analysis_type'] ?? '',
      status: _parseStatus(response['status']),
      progress: response['progress'] ?? 0,
      message: response['message'],
      results: response['results'],
      error: response['error'],
      timestamp: DateTime.now(),
    );
  }

  static AnalysisStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'uploaded':
        return AnalysisStatus.uploaded;
      case 'processing':
        return AnalysisStatus.processing;
      case 'completed':
        return AnalysisStatus.completed;
      case 'failed':
      case 'error':
        return AnalysisStatus.failed;
      default:
        return AnalysisStatus.unknown;
    }
  }

  bool get isCompleted => status == AnalysisStatus.completed;
  bool get isFailed => status == AnalysisStatus.failed;
  bool get isFinished => isCompleted || isFailed;
}

class AnalysisPollingService {
  static final AnalysisPollingService _instance = AnalysisPollingService._internal();
  factory AnalysisPollingService() => _instance;
  AnalysisPollingService._internal();

  final Map<String, StreamController<AnalysisProgress>> _controllers = {};
  final Map<String, Timer> _timers = {};
  final Map<String, int> _retryCount = {};

  // 기본 폴링 설정
  static const Duration _baseInterval = Duration(seconds: 5);
  static const Duration _maxInterval = Duration(minutes: 2);
  static const int _maxRetries = 20; // 최대 20번 재시도 (약 10분)

  // 지수 백오프 계산
  Duration _calculateInterval(int retryCount) {
    final backoffFactor = min(pow(1.5, retryCount), 24); // 최대 24배
    final intervalMs = (_baseInterval.inMilliseconds * backoffFactor).round();
    return Duration(milliseconds: min(intervalMs, _maxInterval.inMilliseconds));
  }

  // 분석 상태 모니터링 시작
  Stream<AnalysisProgress> startMonitoring(String analysisId) {
    // 이미 모니터링 중이면 기존 스트림 반환
    if (_controllers.containsKey(analysisId)) {
      return _controllers[analysisId]!.stream;
    }

    // 새 스트림 컨트롤러 생성
    final controller = StreamController<AnalysisProgress>.broadcast();
    _controllers[analysisId] = controller;
    _retryCount[analysisId] = 0;

    // 즉시 첫 번째 상태 확인
    _checkStatus(analysisId);

    return controller.stream;
  }

  // 상태 확인 및 다음 폴링 스케줄링
  Future<void> _checkStatus(String analysisId) async {
    if (!_controllers.containsKey(analysisId)) {
      return; // 이미 취소됨
    }

    try {
      final response = await unifiedApi.getAnalysisStatus(analysisId);

      if (response['success'] != false) {
        final progress = AnalysisProgress.fromApiResponse(response);
        _controllers[analysisId]?.add(progress);

        // 완료되었으면 모니터링 종료
        if (progress.isFinished) {
          await stopMonitoring(analysisId);
          return;
        }

        // 재시도 카운트 리셋 (성공했으므로)
        _retryCount[analysisId] = 0;
      } else {
        // API 오류 처리
        _handleError(analysisId, response['error'] ?? '알 수 없는 오류');
      }
    } catch (e) {
      _handleError(analysisId, e.toString());
    }

    // 다음 폴링 스케줄링
    _scheduleNextCheck(analysisId);
  }

  // 오류 처리
  void _handleError(String analysisId, String error) {
    final retryCount = _retryCount[analysisId] ?? 0;

    if (retryCount >= _maxRetries) {
      // 최대 재시도 초과 - 실패로 처리
      final failedProgress = AnalysisProgress(
        analysisId: analysisId,
        analysisType: 'unknown',
        status: AnalysisStatus.failed,
        progress: 0,
        error: '최대 재시도 횟수를 초과했습니다: $error',
        timestamp: DateTime.now(),
      );
      _controllers[analysisId]?.add(failedProgress);
      stopMonitoring(analysisId);
    } else {
      // 재시도 카운트 증가
      _retryCount[analysisId] = retryCount + 1;
      print('분석 $analysisId 상태 확인 실패 (재시도 ${retryCount + 1}/$_maxRetries): $error');
    }
  }

  // 다음 폴링 스케줄링
  void _scheduleNextCheck(String analysisId) {
    if (!_controllers.containsKey(analysisId)) {
      return; // 이미 취소됨
    }

    final retryCount = _retryCount[analysisId] ?? 0;
    final interval = _calculateInterval(retryCount);

    _timers[analysisId]?.cancel();
    _timers[analysisId] = Timer(interval, () => _checkStatus(analysisId));
  }

  // 모니터링 중지
  Future<void> stopMonitoring(String analysisId) async {
    _timers[analysisId]?.cancel();
    _timers.remove(analysisId);

    await _controllers[analysisId]?.close();
    _controllers.remove(analysisId);

    _retryCount.remove(analysisId);
  }

  // 모든 모니터링 중지
  Future<void> stopAllMonitoring() async {
    final analysisIds = List<String>.from(_controllers.keys);
    for (final analysisId in analysisIds) {
      await stopMonitoring(analysisId);
    }
  }

  // 현재 모니터링 중인 분석 목록
  List<String> get monitoringAnalyses => List<String>.from(_controllers.keys);

  // 모니터링 상태 확인
  bool isMonitoring(String analysisId) => _controllers.containsKey(analysisId);

  // 종합 진단 모니터링 (여러 분석을 동시에 모니터링)
  Stream<Map<String, AnalysisProgress>> monitorMultipleAnalyses(List<String> analysisIds) {
    final controller = StreamController<Map<String, AnalysisProgress>>.broadcast();
    final Map<String, AnalysisProgress> currentProgress = {};
    final Map<String, StreamSubscription> subscriptions = {};

    // 각 분석에 대해 개별 모니터링 시작
    for (final analysisId in analysisIds) {
      subscriptions[analysisId] = startMonitoring(analysisId).listen(
        (progress) {
          currentProgress[analysisId] = progress;
          controller.add(Map<String, AnalysisProgress>.from(currentProgress));
        },
        onError: (error) {
          final failedProgress = AnalysisProgress(
            analysisId: analysisId,
            analysisType: 'unknown',
            status: AnalysisStatus.failed,
            progress: 0,
            error: error.toString(),
            timestamp: DateTime.now(),
          );
          currentProgress[analysisId] = failedProgress;
          controller.add(Map<String, AnalysisProgress>.from(currentProgress));
        },
      );
    }

    // 모든 분석이 완료되었는지 확인
    controller.stream.listen((progressMap) {
      final allFinished = progressMap.values.every((p) => p.isFinished);
      if (allFinished) {
        // 모든 분석이 완료됨 - 구독 정리
        for (final subscription in subscriptions.values) {
          subscription.cancel();
        }
        controller.close();
      }
    });

    return controller.stream;
  }

  // 예상 완료 시간 계산 (분석 타입별)
  Duration getEstimatedDuration(String analysisType) {
    switch (analysisType.toLowerCase()) {
      case 'eye-tracking':
        return const Duration(minutes: 3);
      case 'finger-tapping':
        return const Duration(minutes: 2);
      case 'voice-analysis':
        return const Duration(minutes: 5);
      default:
        return const Duration(minutes: 3);
    }
  }

  // 리소스 정리
  void dispose() {
    stopAllMonitoring();
  }
}

// 전역 인스턴스
final analysisPolling = AnalysisPollingService();