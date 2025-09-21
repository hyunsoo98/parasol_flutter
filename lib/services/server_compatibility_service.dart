import 'api_service.dart';

class ServerCompatibilityService {
  final ApiService _apiService;

  ServerCompatibilityService(this._apiService);

  // 시선추적 분석 결과를 구버전 eye.py 서버 포맷으로 변환
  Map<String, dynamic> convertToEyePyFormat({
    required List<Map<String, dynamic>> frameAnalyses,
    required double testDuration,
    required int totalFrames,
    required double processingFps,
  }) {
    // ... (이 함수의 내용은 기존과 동일하므로 생략)
    // 이 부분은 기존 코드를 그대로 두시면 됩니다.
    // ...
    return {
      'psp_detected': false, // 예시
      'vertical_range': 0.0,
      'blink_count': 0,
      'test_duration': testDuration,
      'total_frames': totalFrames,
      'processing_fps': processingFps,
      'frame_data': frameAnalyses,
      'summary': {},
    };
  }

  // 결과 제출
  Future<Map<String, dynamic>> submitResults({
    required String sessionId,
    required String userId,
    required List<Map<String, dynamic>> frameAnalyses,
    required double testDuration,
    required int totalFrames,
    required double processingFps,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    final analysisResults = convertToEyePyFormat(
        frameAnalyses: frameAnalyses,
        testDuration: testDuration,
        totalFrames: totalFrames,
        processingFps: processingFps);

    final result = await _apiService.submitRealtimeEyeResults(
      sessionId: sessionId,
      userId: userId,
      analysisResults: analysisResults,
      metadata: additionalMetadata,
    );
    return result;
  }
  
  // 다음 단계로 진행 알림
  Future<Map<String, dynamic>> proceedToFingerTapping({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> eyeTestResults,
  }) {
    return _apiService.notifyEyeTestCompletion(
      sessionId: sessionId,
      userId: userId,
      eyeResults: eyeTestResults,
    );
  }

  // 영상 기반 분석을 위한 새로운 메서드들

  // 영상 파일 제출 및 분석 요청
  Future<Map<String, dynamic>> submitVideoForAnalysis({
    required String sessionId,
    required String userId,
    required String videoPath,
    required List<Map<String, dynamic>> basicMetrics,
    required double testDuration,
    required int totalFrames,
    required double recordingFps,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    final analysisRequest = {
      'session_id': sessionId,
      'user_id': userId,
      'video_path': videoPath,
      'test_duration': testDuration,
      'total_frames': totalFrames,
      'recording_fps': recordingFps,
      'basic_metrics': basicMetrics,
      'metadata': additionalMetadata ?? {},
      'analysis_type': 'eye_tracking_video',
      'status': 'pending_analysis',
      'submitted_at': DateTime.now().toIso8601String(),
    };

    // 영상 분석 요청 제출
    final result = await _apiService.submitVideoAnalysisRequest(
      sessionId: sessionId,
      userId: userId,
      videoData: analysisRequest,
    );

    return result;
  }

  // 분석 상태 확인
  Future<Map<String, dynamic>> checkAnalysisStatus(String sessionId) async {
    final result = await _apiService.getAnalysisStatus(sessionId);
    return result;
  }

  // 분석 결과 조회
  Future<Map<String, dynamic>> getAnalysisResults(String sessionId) async {
    final result = await _apiService.getAnalysisResults(sessionId);
    return result;
  }

  // 상태 조회 (기존)
  Future<Map<String, dynamic>> checkStatus(String sessionId) {
    return _apiService.getStatus(sessionId);
  }
}