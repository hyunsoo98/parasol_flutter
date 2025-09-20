import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'server_compatibility_service.dart';

/// 시선추적 -> Finger-tapping 테스트 연계 관리 서비스
class TestFlowService {
  final ApiService _apiService;
  final ServerCompatibilityService _serverCompatibility;

  String? _currentSessionId;
  String? _currentUserId;
  Map<String, dynamic>? _eyeTestResults;

  TestFlowService({
    required ApiService apiService,
  }) : _apiService = apiService,
       _serverCompatibility = ServerCompatibilityService(apiService);

  /// 새로운 테스트 세션 시작
  String startNewTestSession(String userId) {
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$userId';
    _currentUserId = userId;
    _eyeTestResults = null;
    return _currentSessionId!;
  }

  /// 시선추적 테스트 완료 처리
  Future<Map<String, dynamic>> completeEyeTest({
    required List<Map<String, dynamic>> frameAnalyses,
    required double testDuration,
    required int totalFrames,
    required double processingFps,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    if (_currentSessionId == null || _currentUserId == null) {
      print('TestFlowService: 활성 세션이 없습니다');
      return {'error': 'No active test session'};
    }

    try {
      print('TestFlowService: 시선추적 결과 처리 시작');

      // 1. 분석 결과 저장 (로컬)
      _eyeTestResults = _serverCompatibility.convertToEyePyFormat(
        frameAnalyses: frameAnalyses,
        testDuration: testDuration,
        totalFrames: totalFrames,
        processingFps: processingFps,
      );
      print('TestFlowService: 분석 결과 변환 완료 - PSP 감지: ${_eyeTestResults!['psp_detected']}');

      // 2. 서버로 시선추적 결과 전송 (타임아웃 적용)
      try {
        print('TestFlowService: 서버로 결과 전송 중...');
        final submitResult = await _serverCompatibility.submitResults(
          sessionId: _currentSessionId!,
          userId: _currentUserId!,
          frameAnalyses: frameAnalyses,
          testDuration: testDuration,
          totalFrames: totalFrames,
          processingFps: processingFps,
          additionalMetadata: additionalMetadata,
        ).timeout(const Duration(seconds: 15));

        print('TestFlowService: 서버 전송 결과: $submitResult');

        if (submitResult.containsKey('error')) {
          print('TestFlowService: 서버 전송 실패, 로컬 결과 사용');
          // 서버 전송 실패해도 로컬 결과로 계속 진행
        }
      } catch (e) {
        print('TestFlowService: 서버 전송 예외 (무시하고 계속 진행): $e');
        // 서버 연결 실패해도 계속 진행
      }

      // 3. Finger-tapping 테스트 준비 알림 (선택적)
      try {
        print('TestFlowService: Finger-tapping 전환 알림 중...');
        final transitionResult = await _serverCompatibility.proceedToFingerTapping(
          sessionId: _currentSessionId!,
          userId: _currentUserId!,
          eyeTestResults: _eyeTestResults!,
        ).timeout(const Duration(seconds: 10));
        print('TestFlowService: 전환 알림 결과: $transitionResult');
      } catch (e) {
        print('TestFlowService: 전환 알림 실패 (무시하고 계속 진행): $e');
        // 전환 알림 실패해도 계속 진행
      }

      print('TestFlowService: 시선추적 결과 처리 완료');
      return {
        'success': true,
        'eye_results': _eyeTestResults,
        'session_id': _currentSessionId,
        'ready_for_finger_test': true,
      };
    } catch (e) {
      return {'error': 'Failed to complete eye test: $e'};
    }
  }

  /// Finger-tapping 테스트 시작 가능 여부 확인
  bool canStartFingerTapping() {
    return _currentSessionId != null &&
           _currentUserId != null &&
           _eyeTestResults != null;
  }

  /// Finger-tapping 테스트 시작 데이터 제공
  Map<String, dynamic>? getFingerTappingStartData() {
    if (!canStartFingerTapping()) return null;

    return {
      'session_id': _currentSessionId,
      'user_id': _currentUserId,
      'previous_eye_results': _eyeTestResults,
      'psp_risk_from_eye': _eyeTestResults!['psp_detected'] ?? false,
      'eye_vertical_range': _eyeTestResults!['vertical_range'] ?? 0.0,
    };
  }

  /// Finger-tapping 테스트 완료 처리
  Future<Map<String, dynamic>> completeFingerTapping({
    required Map<String, dynamic> fingerResults,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    if (_currentSessionId == null || _currentUserId == null) {
      return {'error': 'No active test session'};
    }

    try {
      // Finger-tapping 결과를 서버로 전송
      final submitResult = await _apiService.saveFingerFile({
        'session_id': _currentSessionId,
        'user_id': _currentUserId,
        'finger_results': fingerResults,
        'previous_eye_results': _eyeTestResults,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'metadata': {
          'test_flow': 'eye_to_finger',
          'platform': 'flutter',
          if (additionalMetadata != null) ...additionalMetadata,
        },
      });

      return {
        'success': true,
        'finger_results': fingerResults,
        'submit_result': submitResult,
        'session_id': _currentSessionId,
        'complete_test_data': {
          'eye_results': _eyeTestResults,
          'finger_results': fingerResults,
        },
      };
    } catch (e) {
      return {'error': 'Failed to complete finger tapping: $e'};
    }
  }

  /// 통합 분석 요청 (시선추적 + Finger-tapping)
  Future<Map<String, dynamic>> requestCombinedAnalysis() async {
    if (_currentSessionId == null || _currentUserId == null || _eyeTestResults == null) {
      return {'error': 'Incomplete test session data'};
    }

    try {
      // 서버에서 통합 분석 수행
      final analysisResult = await _apiService.loadAndPredictLatestFinger();

      return {
        'success': true,
        'session_id': _currentSessionId,
        'combined_analysis': analysisResult,
        'eye_contribution': _eyeTestResults!['psp_detected'],
        'finger_contribution': analysisResult['pd_risk'] ?? 0.0,
      };
    } catch (e) {
      return {'error': 'Failed to request combined analysis: $e'};
    }
  }

  /// 현재 세션 정보 조회
  Map<String, dynamic>? getCurrentSessionInfo() {
    if (_currentSessionId == null) return null;

    return {
      'session_id': _currentSessionId,
      'user_id': _currentUserId,
      'eye_test_completed': _eyeTestResults != null,
      'eye_results_summary': _eyeTestResults != null ? {
        'psp_detected': _eyeTestResults!['psp_detected'],
        'vertical_range': _eyeTestResults!['vertical_range'],
        'test_duration': _eyeTestResults!['test_duration'],
      } : null,
    };
  }

  /// 세션 종료 및 정리
  void endSession() {
    _currentSessionId = null;
    _currentUserId = null;
    _eyeTestResults = null;
  }

  /// 세션 상태 검증
  bool isSessionValid() {
    return _currentSessionId != null && _currentUserId != null;
  }

  /// 다음 단계 안내 메시지 생성
  String getNextStepMessage() {
    if (_currentSessionId == null) {
      return '새로운 테스트를 시작하세요.';
    }

    if (_eyeTestResults == null) {
      return '시선추적 테스트를 완료해주세요.';
    }

    return 'Finger-tapping 테스트를 진행할 수 있습니다.';
  }

  /// PSP 위험도 기반 다음 테스트 추천
  Map<String, dynamic> getTestRecommendation() {
    if (_eyeTestResults == null) {
      return {
        'recommended_test': 'eye_tracking',
        'priority': 'high',
        'message': '시선추적 테스트를 먼저 완료해주세요.',
      };
    }

    final pspDetected = _eyeTestResults!['psp_detected'] as bool? ?? false;
    final verticalRange = _eyeTestResults!['vertical_range'] as double? ?? 0.0;

    if (pspDetected || verticalRange < 0.08) {
      return {
        'recommended_test': 'finger_tapping',
        'priority': 'high',
        'message': '시선추적에서 이상 소견이 발견되었습니다. Finger-tapping 테스트를 진행하세요.',
        'risk_level': 'elevated',
      };
    } else {
      return {
        'recommended_test': 'finger_tapping',
        'priority': 'normal',
        'message': '시선추적 결과가 정상입니다. 추가 검사를 위해 Finger-tapping 테스트를 진행하세요.',
        'risk_level': 'normal',
      };
    }
  }
}