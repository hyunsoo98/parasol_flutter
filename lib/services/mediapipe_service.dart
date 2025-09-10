import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'dart:math' as math;
import 'integrated_face_eye_service.dart';
import 'face_mesh_iris_service.dart';

// MediaPipe Face Landmarker 478개 포인트 기준 눈 랜드마크 인덱스 (통합됨)
class EyeLandmarkIndices {
  // 왼쪽 눈 랜드마크 (MediaPipe 478-point model)
  static const List<int> leftEyeOutline = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246];
  static const List<int> leftEyeUpper = [159, 158, 157, 173, 133, 155, 154, 153];
  static const List<int> leftEyeLower = [33, 7, 163, 144, 145, 153, 154, 155];
  static const int leftEyeInnerCorner = 133;
  static const int leftEyeOuterCorner = 33;
  static const int leftEyeTopCenter = 159;
  static const int leftEyeBottomCenter = 145;
  
  // 오른쪽 눈 랜드마크 (MediaPipe 478-point model)
  static const List<int> rightEyeOutline = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398];
  static const List<int> rightEyeUpper = [386, 387, 388, 466, 263, 249, 390, 373];
  static const List<int> rightEyeLower = [362, 382, 381, 380, 374, 373, 390, 249];
  static const int rightEyeInnerCorner = 362;
  static const int rightEyeOuterCorner = 263;
  static const int rightEyeTopCenter = 386;
  static const int rightEyeBottomCenter = 374;
  
  // 눈동자 추정을 위한 중심점들
  static const int leftPupilEstimate = 468; // 왼쪽 눈 중심 추정점
  static const int rightPupilEstimate = 473; // 오른쪽 눈 중심 추정점
  
  // 눈꺼풀 높이 계산을 위한 포인트들
  static const List<int> leftEyelidTop = [159, 158, 157, 173];
  static const List<int> leftEyelidBottom = [144, 145, 153, 154];
  static const List<int> rightEyelidTop = [386, 387, 388, 466];
  static const List<int> rightEyelidBottom = [380, 374, 373, 390];
}

// 눈 측정 데이터 클래스 (통합됨)
class EyeMetrics {
  final double eyelidOpenness; // 눈꺼풀 개폐도 (0.0 ~ 1.0)
  final Offset gazeDirection; // 시선 방향 (-1 ~ 1)
  final double confidence; // 신뢰도
  final DateTime timestamp;

  EyeMetrics({
    required this.eyelidOpenness,
    required this.gazeDirection,
    required this.confidence,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'EyeMetrics(openness: ${eyelidOpenness.toStringAsFixed(2)}, '
           'gaze: (${gazeDirection.dx.toStringAsFixed(2)}, ${gazeDirection.dy.toStringAsFixed(2)}), '
           'confidence: ${confidence.toStringAsFixed(2)})';
  }
}

// PSP 분석 결과 클래스 (통합됨)
class PSPAnalysis {
  final double verticalRange; // 수직 시선 범위
  final double stability; // 시선 안정성
  final double pspRiskScore; // PSP 위험도 점수 (0.0 ~ 1.0)
  final Map<String, dynamic> details; // 상세 분석 정보

  PSPAnalysis({
    required this.verticalRange,
    required this.stability,
    required this.pspRiskScore,
    required this.details,
  });

  @override
  String toString() {
    return 'PSPAnalysis(verticalRange: ${verticalRange.toStringAsFixed(3)}, '
           'stability: ${stability.toStringAsFixed(3)}, '
           'pspRiskScore: ${pspRiskScore.toStringAsFixed(3)})';
  }
}

class MediaPipeEyePoint {
  final double x;
  final double y;
  final double confidence;

  MediaPipeEyePoint({
    required this.x,
    required this.y,
    required this.confidence,
  });
}

class MediaPipeGazeResult {
  final MediaPipeEyePoint leftEye;
  final MediaPipeEyePoint rightEye;
  final Offset gazeDirection;
  final double confidence;
  final DateTime timestamp;

  MediaPipeGazeResult({
    required this.leftEye,
    required this.rightEye,
    required this.gazeDirection,
    required this.confidence,
    required this.timestamp,
  });
}

class MediaPipeService {
  
  final StreamController<MediaPipeGazeResult> _gazeStreamController;
  final IntegratedFaceEyeService _integratedService;
  final FaceMeshIrisService _faceMeshService;
  bool _isInitialized = false;
  bool _needsCalibration = true;
  bool _useFaceMesh = true; // Face Mesh 사용 여부
  
  // PSP 분석을 위한 데이터 저장
  final List<EyeMetrics> _leftEyeUpwardData = [];
  final List<EyeMetrics> _leftEyeDownwardData = [];
  final List<EyeMetrics> _rightEyeUpwardData = [];
  final List<EyeMetrics> _rightEyeDownwardData = [];
  
  Stream<MediaPipeGazeResult> get gazeStream => _gazeStreamController.stream;
  Stream<EyeMetrics> get leftEyeStream => _useFaceMesh ? _faceMeshService.leftEyeStream : _integratedService.leftEyeStream;
  Stream<EyeMetrics> get rightEyeStream => _useFaceMesh ? _faceMeshService.rightEyeStream : _integratedService.rightEyeStream;
  Stream<IrisTrackingResult> get irisStream => _faceMeshService.irisStream;
  Stream<FaceMesh> get faceMeshStream => _faceMeshService.faceMeshStream;
  bool get isInitialized => _isInitialized;
  bool get needsCalibration => _needsCalibration;
  bool get isCalibrated => true; // 기준점 없이 항상 준비됨

  MediaPipeService() 
      : _gazeStreamController = StreamController<MediaPipeGazeResult>.broadcast(),
        _integratedService = IntegratedFaceEyeService(),
        _faceMeshService = FaceMeshIrisService() {
    _initializeStreams();
  }
  
  void _initializeStreams() {
    if (_useFaceMesh) {
      // Face Mesh 홍채 추적 데이터 스트림 구독 - 빠른 인식을 위해 디버그 출력 최소화
      _faceMeshService.irisStream.listen((irisResult) {
        // 성능 향상을 위해 디버그 출력 제거
        // debugPrint('Face Mesh Iris detected');
      });
      
      // Face Mesh 객체 스트림 - 성능 최적화
      _faceMeshService.faceMeshStream.listen((faceMesh) {
        // 빠른 인식을 위해 간소화된 로그
        // debugPrint('Face Mesh: ${faceMesh.points.length} points');
      });
      
      // Face Mesh 왼쪽 눈 데이터 - 성능 최적화
      _faceMeshService.leftEyeStream.listen((eyeMetrics) {
        _processEyeMetrics(eyeMetrics, isLeftEye: true);
        // 디버그 출력 최소화로 성능 향상
      });
      
      // Face Mesh 오른쪽 눈 데이터 - 성능 최적화
      _faceMeshService.rightEyeStream.listen((eyeMetrics) {
        _processEyeMetrics(eyeMetrics, isLeftEye: false);
        // 디버그 출력 최소화로 성능 향상
      });
    } else {
      // 기존 통합 얼굴-눈 데이터 스트림 구독
      _integratedService.faceDataStream.listen((faceData) {
        debugPrint('Integrated Face Data: ${faceData}');
      });
      
      // 왼쪽 눈 데이터 스트림 구독
      _integratedService.leftEyeStream.listen((eyeMetrics) {
        _processEyeMetrics(eyeMetrics, isLeftEye: true);
        debugPrint('Integrated Left Eye: openness=${eyeMetrics.eyelidOpenness.toStringAsFixed(2)}, stability=${eyeMetrics.confidence.toStringAsFixed(2)}');
      });
      
      // 오른쪽 눈 데이터 스트림 구독
      _integratedService.rightEyeStream.listen((eyeMetrics) {
        _processEyeMetrics(eyeMetrics, isLeftEye: false);
        debugPrint('Integrated Right Eye: openness=${eyeMetrics.eyelidOpenness.toStringAsFixed(2)}, stability=${eyeMetrics.confidence.toStringAsFixed(2)}');
      });
    }
  }

  Future<bool> initialize() async {
    try {
      debugPrint('Initializing Integrated Face-Eye Service...');
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Integrated service initialization failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// 얼굴 기준 프레임 캘리브레이션
  Future<bool> calibrateFaceReference(CameraImage image) async {
    if (!_isInitialized) return false;
    
    try {
      final success = await _integratedService.calibrateFaceReference(image);
      if (success) {
        _needsCalibration = false;
        debugPrint('Face reference calibration completed');
      }
      return success;
    } catch (e) {
      debugPrint('Face calibration error: $e');
      return false;
    }
  }

  Future<void> processFrame(CameraImage image) async {
    if (!_isInitialized) return;

    try {
      if (_useFaceMesh) {
        // Face Mesh 478 포인트 기반 정밀 홍채 추적
        await _faceMeshService.processImage(image);
      } else {
        // 기존 통합 얼굴-눈 서비스
        await _integratedService.processFrameWithoutCalibration(image);
      }
    } catch (e) {
      debugPrint('Real-time frame processing error: $e');
    }
  }

  void resetCalibration() {
    _integratedService.resetCalibration();
    _needsCalibration = true;
    debugPrint('Face calibration reset');
  }

  void _processEyeMetrics(EyeMetrics eyeMetrics, {required bool isLeftEye}) {
    // 시선 방향에 따라 상향/하향 데이터로 분류
    final isUpward = eyeMetrics.gazeDirection.dy < -0.2; // 위쪽 시선
    final isDownward = eyeMetrics.gazeDirection.dy > 0.2; // 아래쪽 시선
    
    if (isLeftEye) {
      if (isUpward) _leftEyeUpwardData.add(eyeMetrics);
      if (isDownward) _leftEyeDownwardData.add(eyeMetrics);
    } else {
      if (isUpward) _rightEyeUpwardData.add(eyeMetrics);
      if (isDownward) _rightEyeDownwardData.add(eyeMetrics);
    }
    
    // 데이터 크기 제한 (메모리 관리)
    _limitDataSize();
  }
  
  void _limitDataSize() {
    const maxSize = 300; // 최대 300개 샘플 유지
    
    if (_leftEyeUpwardData.length > maxSize) {
      _leftEyeUpwardData.removeRange(0, _leftEyeUpwardData.length - maxSize);
    }
    if (_leftEyeDownwardData.length > maxSize) {
      _leftEyeDownwardData.removeRange(0, _leftEyeDownwardData.length - maxSize);
    }
    if (_rightEyeUpwardData.length > maxSize) {
      _rightEyeUpwardData.removeRange(0, _rightEyeUpwardData.length - maxSize);
    }
    if (_rightEyeDownwardData.length > maxSize) {
      _rightEyeDownwardData.removeRange(0, _rightEyeDownwardData.length - maxSize);
    }
  }

  List<Offset> calculateGazeTrajectory(List<MediaPipeGazeResult> results, Size screenSize) {
    return results.map((result) {
      final x = (result.gazeDirection.dx + 1) / 2 * screenSize.width;
      final y = (result.gazeDirection.dy + 1) / 2 * screenSize.height;
      return Offset(x, y);
    }).toList();
  }

  double calculateEyeMovementStability(List<MediaPipeGazeResult> results) {
    if (results.length < 2) return 1.0;
    
    double totalVariation = 0.0;
    for (int i = 1; i < results.length; i++) {
      final prev = results[i - 1].gazeDirection;
      final curr = results[i].gazeDirection;
      final distance = math.sqrt(
        math.pow(curr.dx - prev.dx, 2) + math.pow(curr.dy - prev.dy, 2),
      );
      totalVariation += distance;
    }
    
    final averageVariation = totalVariation / (results.length - 1);
    return math.max(0.0, 1.0 - averageVariation);
  }

  PSPAnalysis calculatePSPScore(List<MediaPipeGazeResult> upwardResults, List<MediaPipeGazeResult> downwardResults) {
    // 기존 인터페이스 호환성을 위해 유지하되, 새로운 분석 방법 사용
    return calculateDetailedPSPAnalysis();
  }
  
  PSPAnalysis calculateDetailedPSPAnalysis() {
    // 왼쪽 눈과 오른쪽 눈 데이터를 결합하여 분석
    final combinedUpwardData = [..._leftEyeUpwardData, ..._rightEyeUpwardData];
    final combinedDownwardData = [..._leftEyeDownwardData, ..._rightEyeDownwardData];
    
    // MediaPipe 기반 PSP 분석
    return _analyzeMediaPipePSPSymptoms(combinedUpwardData, combinedDownwardData);
  }
  
  PSPAnalysis _analyzeMediaPipePSPSymptoms(List<EyeMetrics> upwardGazeData, List<EyeMetrics> downwardGazeData) {
    if (upwardGazeData.isEmpty || downwardGazeData.isEmpty) {
      return PSPAnalysis(
        verticalRange: 0.0,
        stability: 0.0,
        pspRiskScore: 1.0,
        details: {'error': 'Insufficient MediaPipe data'},
      );
    }

    // MediaPipe 478-point 기반 더 정확한 분석
    final upwardY = upwardGazeData.map((e) => e.gazeDirection.dy).toList();
    final downwardY = downwardGazeData.map((e) => e.gazeDirection.dy).toList();
    
    final maxUpward = upwardY.reduce(math.min);
    final maxDownward = downwardY.reduce(math.max);
    final verticalRange = (maxDownward - maxUpward).abs();

    // MediaPipe 신뢰도를 고려한 안정성 계산
    final upwardStability = _calculateMediaPipeStability(upwardGazeData);
    final downwardStability = _calculateMediaPipeStability(downwardGazeData);
    final averageStability = (upwardStability + downwardStability) / 2;

    // MediaPipe 기반 PSP 위험도 점수
    double pspRiskScore = 0.0;
    
    if (verticalRange < 0.15) {
      pspRiskScore += 0.6; // MediaPipe의 더 정밀한 측정으로 기준 강화
    } else if (verticalRange < 0.3) {
      pspRiskScore += 0.4;
    }
    
    if (averageStability < 0.6) {
      pspRiskScore += 0.3;
    }

    // MediaPipe 눈꺼풀 분석
    final avgEyelidOpenness = [
      ...upwardGazeData.map((e) => e.eyelidOpenness),
      ...downwardGazeData.map((e) => e.eyelidOpenness)
    ].reduce((a, b) => a + b) / (upwardGazeData.length + downwardGazeData.length);
    
    if (avgEyelidOpenness < 0.4) {
      pspRiskScore += 0.1;
    }

    return PSPAnalysis(
      verticalRange: verticalRange,
      stability: averageStability,
      pspRiskScore: math.min(1.0, pspRiskScore),
      details: {
        'mediapipe_landmarks': true,
        'upward_samples': upwardGazeData.length,
        'downward_samples': downwardGazeData.length,
        'avg_eyelid_openness': avgEyelidOpenness,
        'avg_confidence': (upwardGazeData + downwardGazeData).map((e) => e.confidence).reduce((a, b) => a + b) / (upwardGazeData.length + downwardGazeData.length),
        'vertical_range_category': verticalRange > 0.5 ? 'normal' : 
                                   verticalRange > 0.2 ? 'reduced' : 'severely_limited',
      },
    );
  }

  double _calculateMediaPipeStability(List<EyeMetrics> data) {
    if (data.length < 2) return 1.0;
    
    double totalVariation = 0.0;
    double confidenceWeight = 0.0;
    
    for (int i = 1; i < data.length; i++) {
      final prev = data[i - 1];
      final curr = data[i];
      final distance = math.sqrt(
        math.pow(curr.gazeDirection.dx - prev.gazeDirection.dx, 2) + 
        math.pow(curr.gazeDirection.dy - prev.gazeDirection.dy, 2),
      );
      
      // MediaPipe 신뢰도를 가중치로 사용
      final weight = (prev.confidence + curr.confidence) / 2;
      totalVariation += distance * weight;
      confidenceWeight += weight;
    }
    
    final weightedAverageVariation = confidenceWeight > 0 ? totalVariation / confidenceWeight : totalVariation / (data.length - 1);
    return math.max(0.0, 1.0 - weightedAverageVariation);
  }
  
  // 실시간 눈 상태 정보 제공
  Map<String, dynamic> getCurrentEyeStatus() {
    final leftEyeCount = _leftEyeUpwardData.length + _leftEyeDownwardData.length;
    final rightEyeCount = _rightEyeUpwardData.length + _rightEyeDownwardData.length;
    
    double avgLeftEyelidOpenness = 0.0;
    double avgRightEyelidOpenness = 0.0;
    
    if (_leftEyeUpwardData.isNotEmpty || _leftEyeDownwardData.isNotEmpty) {
      final allLeft = [..._leftEyeUpwardData, ..._leftEyeDownwardData];
      avgLeftEyelidOpenness = allLeft.map((e) => e.eyelidOpenness).reduce((a, b) => a + b) / allLeft.length;
    }
    
    if (_rightEyeUpwardData.isNotEmpty || _rightEyeDownwardData.isNotEmpty) {
      final allRight = [..._rightEyeUpwardData, ..._rightEyeDownwardData];
      avgRightEyelidOpenness = allRight.map((e) => e.eyelidOpenness).reduce((a, b) => a + b) / allRight.length;
    }
    
    return {
      'left_eye_samples': leftEyeCount,
      'right_eye_samples': rightEyeCount,
      'avg_left_eyelid_openness': avgLeftEyelidOpenness,
      'avg_right_eyelid_openness': avgRightEyelidOpenness,
      'upward_data_count': _leftEyeUpwardData.length + _rightEyeUpwardData.length,
      'downward_data_count': _leftEyeDownwardData.length + _rightEyeDownwardData.length,
    };
  }
  
  // 데이터 초기화
  void clearAnalysisData() {
    _leftEyeUpwardData.clear();
    _leftEyeDownwardData.clear();
    _rightEyeUpwardData.clear();
    _rightEyeDownwardData.clear();
  }

  Future<void> dispose() async {
    _isInitialized = false;
    await _gazeStreamController.close();
    _integratedService.dispose();
    await _faceMeshService.dispose();
  }
}