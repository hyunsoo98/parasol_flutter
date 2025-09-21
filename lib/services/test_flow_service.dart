import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'server_compatibility_service.dart';

class TestFlowService {
  final ApiService _apiService;
  final ServerCompatibilityService _serverCompatibility;

  String? _currentSessionId;
  String? _currentUserId;
  Map<String, dynamic>? _eyeTestResults;

  TestFlowService({
    required ApiService apiService,
  })  : _apiService = apiService,
        _serverCompatibility = ServerCompatibilityService(apiService);

  String startNewTestSession(String userId) {
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$userId';
    _currentUserId = userId;
    _eyeTestResults = null;
    return _currentSessionId!;
  }

  Future<Map<String, dynamic>> completeEyeTest({
    required String videoPath,
    required List<Map<String, dynamic>> basicMetrics,
    required double testDuration,
    required int totalFrames,
    required double recordingFps,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    if (_currentSessionId == null || _currentUserId == null) {
      return {'error': 'No active test session'};
    }
    try {
      // 영상 파일과 기본 메트릭만 저장하고, 상세 분석은 별도로 진행
      _eyeTestResults = {
        'session_id': _currentSessionId!,
        'user_id': _currentUserId!,
        'video_path': videoPath,
        'test_duration': testDuration,
        'total_frames': totalFrames,
        'recording_fps': recordingFps,
        'basic_metrics': basicMetrics,
        'status': 'recorded', // 녹화 완료, 분석 대기
        'created_at': DateTime.now().toIso8601String(),
      };

      await _serverCompatibility.submitVideoForAnalysis(
        sessionId: _currentSessionId!,
        userId: _currentUserId!,
        videoPath: videoPath,
        basicMetrics: basicMetrics,
        testDuration: testDuration,
        totalFrames: totalFrames,
        recordingFps: recordingFps,
        additionalMetadata: additionalMetadata,
      );
      return {
        'success': true,
        'eye_results': _eyeTestResults,
        'analysis_status': 'pending', // 분석 대기 중
        'ready_for_finger_test': true,
      };
    } catch (e) {
      return {'error': 'Failed to complete eye test: $e'};
    }
  }

  Future<Map<String, dynamic>> requestCombinedAnalysis() async {
    if (_currentSessionId == null) {
      return {'error': 'No session ID'};
    }
    try {
      final result = await _apiService.loadAndPredictLatestFinger();
      return {'success': true, 'data': result};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  String? get currentSessionId => _currentSessionId;

  bool canStartFingerTapping() => _currentSessionId != null && _eyeTestResults != null;
  
  Map<String, dynamic>? getFingerTappingStartData() {
     if (!canStartFingerTapping()) return null;
      return {
      'session_id': _currentSessionId,
      'user_id': _currentUserId,
      'previous_eye_results': _eyeTestResults,
    };
  }

  Future<Map<String, dynamic>> completeFingerTapping({
    required Map<String, dynamic> fingerTappingData,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    if (_currentSessionId == null || _currentUserId == null) {
      return {'error': 'No active test session'};
    }

    try {
      // 손가락 태핑 결과를 서버에 전송
      final result = await _apiService.predictFinger({
        'session_id': _currentSessionId!,
        'user_id': _currentUserId!,
        'finger_tapping_data': fingerTappingData,
        'metadata': additionalMetadata,
      });

      return {'success': true, 'data': result};
    } catch (e) {
      return {'error': 'Failed to complete finger tapping: $e'};
    }
  }

  void endSession() {
    _currentSessionId = null;
    _currentUserId = null;
    _eyeTestResults = null;
  }
}