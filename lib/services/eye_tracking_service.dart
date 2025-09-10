import 'dart:async';
import 'package:camera/camera.dart';
import 'dart:math' as math;

enum EyeTrackingMode {
  setup,
  pspTest,
}

enum TrackingPhase {
  preparation,
  faceDetection,
  eyeMarking,
  gazeTest,
  completed,
}

class EyeTrackingData {
  final String phase;
  final double? riskScore;
  final DateTime timestamp;
  final Map<String, dynamic>? additionalData;

  EyeTrackingData({
    required this.phase,
    this.riskScore,
    required this.timestamp,
    this.additionalData,
  });

  Map<String, dynamic> toJson() {
    return {
      'phase': phase,
      'riskScore': riskScore,
      'timestamp': timestamp.toIso8601String(),
      'additionalData': additionalData,
    };
  }
}

class FaceTrackingResult {
  final bool isValid;
  final dynamic face;
  final String? message;

  FaceTrackingResult({
    required this.isValid,
    this.face,
    this.message,
  });
}

class EyeTrackingService {
  // Mock face detector for now
  final dynamic _faceDetector = null;
  final StreamController<FaceTrackingResult> _faceStreamController;
  final List<EyeTrackingData> _trackingData;
  bool _isDisposed = false;
  
  Stream<FaceTrackingResult> get faceStream => _faceStreamController.stream;
  List<EyeTrackingData> get trackingData => List.unmodifiable(_trackingData);

  EyeTrackingService()
      : _faceStreamController = StreamController<FaceTrackingResult>.broadcast(),
        _trackingData = [];

  Future<void> processCameraImage(CameraImage image, TrackingPhase phase) async {
    if(_isDisposed) return;

    try {
      // Mock processing for now
      await Future.delayed(const Duration(milliseconds: 50));
      
      FaceTrackingResult result;
      
      switch (phase) {
        case TrackingPhase.faceDetection:
          result = FaceTrackingResult(isValid: true, message: '얼굴이 감지되었습니다');
          break;
        case TrackingPhase.eyeMarking:
          result = FaceTrackingResult(isValid: true, message: '눈 마킹이 완료되었습니다');
          break;
        default:
          result = FaceTrackingResult(isValid: false, message: 'Unknown phase');
      }
      if (!_isDisposed) { // ⬅️ 3. 데이터를 추가하기 직전 한 번 더 확인
        _faceStreamController.add(result);
      }

    } catch (e) {
      if (!_isDisposed) {
        _faceStreamController.add(
          FaceTrackingResult(isValid: false, message: 'Processing error: $e'),
        );
      }
    }
  }


  void addTrackingData(EyeTrackingData data) {
    _trackingData.add(data);
  }

  void clearTrackingData() {
    _trackingData.clear();
  }

  double calculatePSPRiskScore() {
    return math.Random().nextDouble() * 0.7;
  }

  void dispose() {
    _isDisposed = true;
    _faceStreamController.close();
  }
}