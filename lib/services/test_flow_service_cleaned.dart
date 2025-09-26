import 'api_service_cleaned.dart';

/// 🎯 정리된 테스트 플로우 서비스
class TestFlowService {
  final ApiService _apiService;

  String? _currentSessionId;
  String? _currentUserId;
  Map<String, dynamic>? _eyeTestResults;

  TestFlowService({required ApiService apiService}) : _apiService = apiService;

  // Getters
  String? get currentSessionId => _currentSessionId;
  String? get currentUserId => _currentUserId;
  ApiService get apiService => _apiService;

  /// 새 테스트 세션 시작
  String startNewTestSession(String userId) {
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$userId';
    _currentUserId = userId;
    _eyeTestResults = null;
    print('🎯 새 테스트 세션 시작: $_currentSessionId');
    return _currentSessionId!;
  }

  /// 👁️ 시선 추적 테스트 완료
  Future<Map<String, dynamic>> completeEyeTest({
    required Map<String, dynamic> analysisResults,
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentSessionId == null || _currentUserId == null) {
      return {'error': 'No active test session'};
    }

    try {
      _eyeTestResults = {
        'session_id': _currentSessionId!,
        'user_id': _currentUserId!,
        'analysis_results': analysisResults,
        'metadata': metadata,
        'completed_at': DateTime.now().toIso8601String(),
      };

      // API로 결과 전송
      final response = await _apiService.submitEyeTrackingResults(
        userId: _currentUserId!,
        resultsData: analysisResults,
        sessionId: _currentSessionId,
      );

      print('✅ 시선 추적 테스트 완료: ${response['analysis_id']}');
      return response;

    } catch (e) {
      print('❌ 시선 추적 테스트 완료 실패: $e');
      return {'error': 'Failed to complete eye test', 'details': e.toString()};
    }
  }

  /// 👆 손가락 태핑 테스트 완료
  Future<Map<String, dynamic>> completeFingerTappingTest({
    required String videoData, // Base64 encoded
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentUserId == null) {
      return {'error': 'No active user'};
    }

    try {
      final response = await _apiService.submitFingerTappingVideo(
        userId: _currentUserId!,
        videoData: videoData,
        parameters: {
          'session_id': _currentSessionId,
          'metadata': metadata,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );

      print('✅ 손가락 태핑 테스트 완료: ${response['analysis_id']}');
      return response;

    } catch (e) {
      print('❌ 손가락 태핑 테스트 완료 실패: $e');
      return {'error': 'Failed to complete finger tapping test', 'details': e.toString()};
    }
  }

  /// 🎤 음성 분석 테스트 완료
  Future<Map<String, dynamic>> completeVoiceAnalysisTest({
    required String audioData, // Base64 encoded
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentUserId == null) {
      return {'error': 'No active user'};
    }

    try {
      final response = await _apiService.submitVoiceAnalysis(
        userId: _currentUserId!,
        audioData: audioData,
        parameters: {
          'session_id': _currentSessionId,
          'metadata': metadata,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );

      print('✅ 음성 분석 테스트 완료: ${response['analysis_id']}');
      return response;

    } catch (e) {
      print('❌ 음성 분석 테스트 완료 실패: $e');
      return {'error': 'Failed to complete voice analysis test', 'details': e.toString()};
    }
  }

  /// 📊 분석 상태 확인
  Future<Map<String, dynamic>> checkAnalysisStatus(String analysisId) {
    return _apiService.getAnalysisStatus(analysisId);
  }

  /// 📋 분석 결과 조회
  Future<Map<String, dynamic>> getAnalysisResults(String analysisId) {
    return _apiService.getAnalysisResults(analysisId);
  }

  /// 🧹 세션 정리
  void clearSession() {
    _currentSessionId = null;
    _currentUserId = null;
    _eyeTestResults = null;
    print('🧹 테스트 세션 정리 완료');
  }
}

/// 테스트 단계 열거형
enum TestStep {
  PHONE_MOUNT_GUIDE,
  EYE_TRACKING,
  FINGER_TAPPING_GUIDE,
  FINGER_TAPPING,
  VOICE_ANALYSIS,
  COMPLETED
}