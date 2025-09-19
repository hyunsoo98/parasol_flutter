import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'api_service.dart';

/// 실시간 분석 결과를 기존 eye.py 서버 API와 호환되는 형식으로 변환하고 전송하는 서비스
class ServerCompatibilityService {
  final ApiService _apiService;

  ServerCompatibilityService(this._apiService);

  /// 실시간 시선추적 분석 결과를 eye.py 호환 포맷으로 변환
  Map<String, dynamic> convertToEyePyFormat({
    required List<Map<String, dynamic>> frameAnalyses,
    required double testDuration,
    required int totalFrames,
    required double processingFps,
  }) {
    if (frameAnalyses.isEmpty) {
      return {
        'psp_detected': false,
        'vertical_range': 0.0,
        'blink_count': 0,
        'test_duration': testDuration,
        'total_frames': totalFrames,
        'processing_fps': processingFps,
        'frame_data': [],
      };
    }

    // 1. 수직 움직임 범위 계산 (PSP 판정 핵심)
    final verticalPositions = frameAnalyses
        .where((frame) => frame['iris_y'] != null)
        .map((frame) => frame['iris_y'] as double)
        .toList();

    double verticalRange = 0.0;
    if (verticalPositions.isNotEmpty) {
      final minY = verticalPositions.reduce((a, b) => a < b ? a : b);
      final maxY = verticalPositions.reduce((a, b) => a > b ? a : b);
      verticalRange = maxY - minY;
    }

    // 2. 깜빡임 횟수 계산
    int blinkCount = 0;
    bool wasEyeOpen = true;
    for (final frame in frameAnalyses) {
      final eyeOpen = frame['eye_open'] as bool? ?? true;
      if (wasEyeOpen && !eyeOpen) {
        blinkCount++;
      }
      wasEyeOpen = eyeOpen;
    }

    // 3. PSP 판정 (eye.py의 v_ptp < 0.06 기준)
    final pspDetected = verticalRange < 0.06;

    // 4. eye.py 호환 프레임 데이터 변환
    final frameData = frameAnalyses.map((frame) => {
      'timestamp': frame['timestamp'],
      'iris_x': frame['iris_x'] ?? 0.5,
      'iris_y': frame['iris_y'] ?? 0.5,
      'eye_open': frame['eye_open'] ?? true,
      'face_detected': frame['face_detected'] ?? false,
      'confidence': frame['confidence'] ?? 0.0,
      'phase': frame['phase'] ?? 'unknown',
    }).toList();

    // 5. 최종 결과 (eye.py analyze_frame() 출력과 동일)
    return {
      'psp_detected': pspDetected,
      'vertical_range': verticalRange,
      'blink_count': blinkCount,
      'test_duration': testDuration,
      'total_frames': totalFrames,
      'processing_fps': processingFps,
      'frame_data': frameData,
      'summary': {
        'vertical_peak_to_peak': verticalRange,
        'blink_frequency': blinkCount / (testDuration / 60), // 분당 깜빡임
        'data_quality': frameData.where((f) => f['face_detected'] == true).length / frameData.length,
        'analysis_confidence': _calculateOverallConfidence(frameData),
      },
    };
  }

  /// 전체 분석 신뢰도 계산
  double _calculateOverallConfidence(List<Map<String, dynamic>> frameData) {
    if (frameData.isEmpty) return 0.0;

    final confidences = frameData
        .map((frame) => frame['confidence'] as double? ?? 0.0)
        .where((conf) => conf > 0)
        .toList();

    if (confidences.isEmpty) return 0.0;

    return confidences.reduce((a, b) => a + b) / confidences.length;
  }

  /// 비디오 바이트를 임시 파일로 저장
  Future<File?> _saveVideoToTempFile(Uint8List videoBytes, String sessionId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'eye_test_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File(path.join(tempDir.path, fileName));

      await file.writeAsBytes(videoBytes);
      return file;
    } catch (e) {
      print('비디오 임시 파일 저장 실패: $e');
      return null;
    }
  }

  /// 서버로 실시간 분석 결과 전송 (비디오 업로드 제거)
  Future<Map<String, dynamic>> submitResults({
    required String sessionId,
    required String userId,
    required List<Map<String, dynamic>> frameAnalyses,
    required double testDuration,
    required int totalFrames,
    required double processingFps,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    try {
      // 1. 분석 결과를 eye.py 포맷으로 변환
      final eyePyResults = convertToEyePyFormat(
        frameAnalyses: frameAnalyses,
        testDuration: testDuration,
        totalFrames: totalFrames,
        processingFps: processingFps,
      );

      // 2. 서버로 결과 전송 (비디오 업로드 없음)
      final result = await _apiService.submitRealtimeEyeResults(
        sessionId: sessionId,
        analysisResults: eyePyResults,
        userId: userId,
        metadata: {
          'test_type': 'structured_eye_test_client',
          'client_version': '1.0.0',
          'analysis_timestamp': DateTime.now().toIso8601String(),
          if (additionalMetadata != null) ...additionalMetadata,
        },
      );

      return result;
    } catch (e) {
      return {'error': 'Failed to submit results to server: $e'};
    }
  }

  /// Finger-tapping 테스트로 연계
  Future<Map<String, dynamic>> proceedToFingerTapping({
    required String sessionId,
    required String userId,
    required Map<String, dynamic> eyeTestResults,
  }) async {
    try {
      return await _apiService.notifyEyeTestCompletion(
        sessionId: sessionId,
        userId: userId,
        eyeResults: eyeTestResults,
      );
    } catch (e) {
      return {'error': 'Failed to proceed to finger tapping: $e'};
    }
  }

  /// 테스트 세션 상태 조회
  Future<Map<String, dynamic>> getTestSessionStatus(String sessionId) async {
    try {
      return await _apiService.getStatus(sessionId);
    } catch (e) {
      return {'error': 'Failed to get session status: $e'};
    }
  }
}