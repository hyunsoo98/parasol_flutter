import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'mediapipe_service.dart';

/// 통합 얼굴-눈동자 매핑 서비스
/// 얼굴을 기준점으로 고정하고, 그에 대한 상대적 눈 위치 및 시선을 계산
class IntegratedFaceEyeService {
  final FaceDetector _faceDetector;
  final StreamController<IntegratedFaceData> _faceDataController = 
      StreamController<IntegratedFaceData>.broadcast();
  final StreamController<EyeMetrics> _leftEyeController = 
      StreamController<EyeMetrics>.broadcast();
  final StreamController<EyeMetrics> _rightEyeController = 
      StreamController<EyeMetrics>.broadcast();
  
  bool _isProcessing = false;
  bool _isCalibrated = false;
  
  // 캘리브레이션 기준 데이터
  FaceReferenceFrame? _referenceFrame;
  
  Stream<IntegratedFaceData> get faceDataStream => _faceDataController.stream;
  Stream<EyeMetrics> get leftEyeStream => _leftEyeController.stream;
  Stream<EyeMetrics> get rightEyeStream => _rightEyeController.stream;
  bool get isCalibrated => _isCalibrated;

  IntegratedFaceEyeService() 
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: true,
            enableClassification: false,
            enableTracking: true,
            minFaceSize: 0.15,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  /// 얼굴 기준 프레임 캘리브레이션
  Future<bool> calibrateFaceReference(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isNotEmpty) {
        final face = faces.first;
        
        // 안정적인 얼굴인지 확인 (크기, 각도 등)
        if (_isStableFace(face)) {
          _referenceFrame = FaceReferenceFrame.fromFace(face, Size(image.width.toDouble(), image.height.toDouble()));
          _isCalibrated = true;
          
          debugPrint('Face reference calibrated: ${_referenceFrame}');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Face calibration error: $e');
      return false;
    }
  }

  /// 통합 얼굴-눈 데이터 처리
  Future<void> processFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isNotEmpty && _isCalibrated) {
        final face = faces.first;
        final faceData = await _processIntegratedFaceData(face, Size(image.width.toDouble(), image.height.toDouble()));
        
        if (faceData != null) {
          _faceDataController.add(faceData);
          
          // 얼굴 기준 상대적 눈 위치로 EyeMetrics 계산
          final leftEyeMetrics = _calculateRelativeEyeMetrics(faceData, isLeftEye: true);
          final rightEyeMetrics = _calculateRelativeEyeMetrics(faceData, isLeftEye: false);
          
          if (leftEyeMetrics != null) {
            _leftEyeController.add(leftEyeMetrics);
          }
          
          if (rightEyeMetrics != null) {
            _rightEyeController.add(rightEyeMetrics);
          }
        }
      }
    } catch (e) {
      debugPrint('Integrated face-eye processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }
  
  /// 기준점 없이 실시간 처리 (핸드폰 거치 기준)
  Future<void> processFrameWithoutCalibration(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isNotEmpty) {
        final face = faces.first;
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());
        
        // 기준점 없이 바로 실시간 눈 메트릭스 계산
        final leftEyeMetrics = _calculateDirectEyeMetrics(face, imageSize, isLeftEye: true);
        final rightEyeMetrics = _calculateDirectEyeMetrics(face, imageSize, isLeftEye: false);
        
        if (leftEyeMetrics != null) {
          _leftEyeController.add(leftEyeMetrics);
        }
        
        if (rightEyeMetrics != null) {
          _rightEyeController.add(rightEyeMetrics);
        }
        
        // 실시간 얼굴 데이터도 전송 (기준점 없는 버전)
        final simpleFaceData = IntegratedFaceData(
          face: face,
          referenceFrame: FaceReferenceFrame(
            faceBox: face.boundingBox,
            leftEyePosition: _getEyePosition(face, isLeftEye: true),
            rightEyePosition: _getEyePosition(face, isLeftEye: false),
            imageSize: imageSize,
            calibrationTime: DateTime.now(),
          ),
          scaleChange: 1.0,
          positionChange: Offset.zero,
          leftEyePosition: _getEyePosition(face, isLeftEye: true),
          rightEyePosition: _getEyePosition(face, isLeftEye: false),
          leftEyeOpenness: leftEyeMetrics?.eyelidOpenness ?? 0.8,
          rightEyeOpenness: rightEyeMetrics?.eyelidOpenness ?? 0.8,
          faceStability: 1.0,
          timestamp: DateTime.now(),
        );
        
        _faceDataController.add(simpleFaceData);
      }
    } catch (e) {
      debugPrint('Real-time face-eye processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  bool _isStableFace(Face face) {
    final box = face.boundingBox;
    
    // 최소 크기 체크
    if (box.width < 100 || box.height < 120) return false;
    
    // 비율 체크 (너무 옆얼굴이나 기울어진 얼굴 제외)
    final ratio = box.width / box.height;
    if (ratio < 0.6 || ratio > 1.2) return false;
    
    return true;
  }

  Future<IntegratedFaceData?> _processIntegratedFaceData(Face face, Size imageSize) async {
    if (_referenceFrame == null) return null;
    
    try {
      final currentBox = face.boundingBox;
      final referenceBox = _referenceFrame!.faceBox;
      
      // 얼굴 변화 분석 (크기, 위치, 각도)
      final scaleChange = currentBox.width / referenceBox.width;
      final positionChange = Offset(
        (currentBox.center.dx - referenceBox.center.dx) / referenceBox.width,
        (currentBox.center.dy - referenceBox.center.dy) / referenceBox.height,
      );
      
      // 랜드마크 기반 눈 위치 계산
      final leftEyeData = _calculateEyePosition(face, _referenceFrame!, isLeftEye: true);
      final rightEyeData = _calculateEyePosition(face, _referenceFrame!, isLeftEye: false);
      
      return IntegratedFaceData(
        face: face,
        referenceFrame: _referenceFrame!,
        scaleChange: scaleChange,
        positionChange: positionChange,
        leftEyePosition: leftEyeData.position,
        rightEyePosition: rightEyeData.position,
        leftEyeOpenness: leftEyeData.openness,
        rightEyeOpenness: rightEyeData.openness,
        faceStability: _calculateFaceStability(scaleChange, positionChange),
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      debugPrint('Integrated face data processing error: $e');
      return null;
    }
  }

  EyePositionData _calculateEyePosition(Face face, FaceReferenceFrame reference, {required bool isLeftEye}) {
    final landmarks = face.landmarks;
    final currentBox = face.boundingBox;
    final referenceBox = reference.faceBox;
    
    // 얼굴 크기 변화 비율
    final scaleX = currentBox.width / referenceBox.width;
    final scaleY = currentBox.height / referenceBox.height;
    
    // 기본 눈 위치 (얼굴 중심 대비)
    final faceCenter = currentBox.center;
    final eyeOffsetX = isLeftEye ? -currentBox.width * 0.25 : currentBox.width * 0.25;
    final eyeOffsetY = -currentBox.height * 0.15;
    final defaultEyePosition = Offset(faceCenter.dx + eyeOffsetX, faceCenter.dy + eyeOffsetY);
    
    // ML Kit 랜드마크가 있으면 활용
    Offset actualEyePosition = defaultEyePosition;
    double eyeOpenness = 0.8; // 기본값
    
    final eyeType = isLeftEye ? FaceLandmarkType.leftEye : FaceLandmarkType.rightEye;
    if (landmarks.containsKey(eyeType) && landmarks[eyeType] != null) {
      final landmark = landmarks[eyeType]!;
      actualEyePosition = Offset(landmark.position.x.toDouble(), landmark.position.y.toDouble());
      
      // 랜드마크 기반 눈꺼풀 개폐도 추정
      eyeOpenness = _estimateEyelidOpenness(actualEyePosition, currentBox, scaleY);
    }
    
    // 기준 프레임 대비 상대적 위치 계산
    final referenceEyePosition = isLeftEye ? reference.leftEyePosition : reference.rightEyePosition;
    final relativePosition = Offset(
      (actualEyePosition.dx - referenceEyePosition.dx) / referenceBox.width,
      (actualEyePosition.dy - referenceEyePosition.dy) / referenceBox.height,
    );
    
    return EyePositionData(
      position: actualEyePosition,
      relativePosition: relativePosition,
      openness: eyeOpenness,
    );
  }

  double _estimateEyelidOpenness(Offset eyePosition, Rect faceBox, double scaleY) {
    // 얼굴 크기 변화를 고려한 눈꺼풀 개폐도 추정
    // 실제로는 더 정교한 랜드마크 분석이 필요하지만, 기본 추정치 제공
    final baseOpenness = 0.8;
    final scaleVariation = (scaleY - 1.0) * 0.1; // 얼굴이 가까워지면 눈이 더 열려보임
    
    return math.max(0.3, math.min(1.0, baseOpenness + scaleVariation));
  }

  double _calculateFaceStability(double scaleChange, Offset positionChange) {
    // 얼굴 안정성 점수 (0.0 ~ 1.0)
    final scaleStability = 1.0 - math.min(1.0, (scaleChange - 1.0).abs() * 2);
    final positionStability = 1.0 - math.min(1.0, positionChange.distance * 5);
    
    return (scaleStability + positionStability) / 2;
  }

  EyeMetrics? _calculateRelativeEyeMetrics(IntegratedFaceData faceData, {required bool isLeftEye}) {
    try {
      final eyePosition = isLeftEye ? faceData.leftEyePosition : faceData.rightEyePosition;
      final eyeOpenness = isLeftEye ? faceData.leftEyeOpenness : faceData.rightEyeOpenness;
      
      // 얼굴 중심 대비 시선 방향 계산
      final faceCenter = faceData.face.boundingBox.center;
      final gazeDirection = Offset(
        (eyePosition.dx - faceCenter.dx) / (faceData.face.boundingBox.width * 0.5),
        (eyePosition.dy - faceCenter.dy) / (faceData.face.boundingBox.height * 0.3),
      );
      
      // 정규화
      final normalizedGaze = Offset(
        math.max(-1.0, math.min(1.0, gazeDirection.dx)),
        math.max(-1.0, math.min(1.0, gazeDirection.dy)),
      );
      
      return EyeMetrics(
        eyelidOpenness: eyeOpenness,
        gazeDirection: normalizedGaze,
        confidence: faceData.faceStability, // 얼굴 안정성을 신뢰도로 사용
        timestamp: faceData.timestamp,
      );
      
    } catch (e) {
      debugPrint('Relative eye metrics calculation error: $e');
      return null;
    }
  }

  void resetCalibration() {
    _isCalibrated = false;
    _referenceFrame = null;
    debugPrint('Face reference calibration reset');
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = _concatenatePlanes(image.planes);
    
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      ),
    );
  }
  
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = <int>[];
    for (final plane in planes) {
      allBytes.addAll(plane.bytes);
    }
    return Uint8List.fromList(allBytes);
  }

  /// 기준점 없이 직접 눈 메트릭스 계산
  EyeMetrics? _calculateDirectEyeMetrics(Face face, Size imageSize, {required bool isLeftEye}) {
    try {
      final eyePosition = _getEyePosition(face, isLeftEye: isLeftEye);
      final faceCenter = face.boundingBox.center;
      
      // 얼굴 중심 대비 시선 방향 계산 (핸드폰 거치 기준)
      final gazeDirection = Offset(
        (eyePosition.dx - faceCenter.dx) / (face.boundingBox.width * 0.5),
        (eyePosition.dy - faceCenter.dy) / (face.boundingBox.height * 0.3),
      );
      
      // 정규화
      final normalizedGaze = Offset(
        math.max(-1.0, math.min(1.0, gazeDirection.dx)),
        math.max(-1.0, math.min(1.0, gazeDirection.dy)),
      );
      
      // 눈꺼풀 개폐도 추정 (얼굴 크기 기반)
      final eyelidOpenness = _estimateEyelidOpenness(
        eyePosition, 
        face.boundingBox, 
        1.0 // 스케일 변화 없음
      );
      
      return EyeMetrics(
        eyelidOpenness: eyelidOpenness,
        gazeDirection: normalizedGaze,
        confidence: 0.9, // 실시간 처리 신뢰도
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      debugPrint('Direct eye metrics calculation error: $e');
      return null;
    }
  }
  
  /// 눈 위치 가져오기 (랜드마크 또는 추정)
  Offset _getEyePosition(Face face, {required bool isLeftEye}) {
    final landmarks = face.landmarks;
    final faceBox = face.boundingBox;
    final faceCenter = faceBox.center;
    
    // ML Kit 랜드마크가 있으면 사용
    final eyeType = isLeftEye ? FaceLandmarkType.leftEye : FaceLandmarkType.rightEye;
    if (landmarks.containsKey(eyeType) && landmarks[eyeType] != null) {
      final landmark = landmarks[eyeType]!;
      return Offset(landmark.position.x.toDouble(), landmark.position.y.toDouble());
    }
    
    // 랜드마크가 없으면 추정 위치 계산
    final eyeOffsetX = isLeftEye ? -faceBox.width * 0.25 : faceBox.width * 0.25;
    final eyeOffsetY = -faceBox.height * 0.15;
    return Offset(faceCenter.dx + eyeOffsetX, faceCenter.dy + eyeOffsetY);
  }

  void dispose() {
    _faceDetector.close();
    _faceDataController.close();
    _leftEyeController.close();
    _rightEyeController.close();
  }
}

/// 얼굴 기준 프레임 (캘리브레이션 시 저장)
class FaceReferenceFrame {
  final Rect faceBox;
  final Offset leftEyePosition;
  final Offset rightEyePosition;
  final Size imageSize;
  final DateTime calibrationTime;
  
  const FaceReferenceFrame({
    required this.faceBox,
    required this.leftEyePosition,
    required this.rightEyePosition,
    required this.imageSize,
    required this.calibrationTime,
  });
  
  factory FaceReferenceFrame.fromFace(Face face, Size imageSize) {
    final faceBox = face.boundingBox;
    final faceCenter = faceBox.center;
    
    // 기본 눈 위치 계산
    Offset leftEyePos = Offset(faceCenter.dx - faceBox.width * 0.25, faceCenter.dy - faceBox.height * 0.15);
    Offset rightEyePos = Offset(faceCenter.dx + faceBox.width * 0.25, faceCenter.dy - faceBox.height * 0.15);
    
    // 실제 랜드마크가 있으면 사용
    if (face.landmarks.containsKey(FaceLandmarkType.leftEye) && face.landmarks[FaceLandmarkType.leftEye] != null) {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]!;
      leftEyePos = Offset(leftEye.position.x.toDouble(), leftEye.position.y.toDouble());
    }
    
    if (face.landmarks.containsKey(FaceLandmarkType.rightEye) && face.landmarks[FaceLandmarkType.rightEye] != null) {
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]!;
      rightEyePos = Offset(rightEye.position.x.toDouble(), rightEye.position.y.toDouble());
    }
    
    return FaceReferenceFrame(
      faceBox: faceBox,
      leftEyePosition: leftEyePos,
      rightEyePosition: rightEyePos,
      imageSize: imageSize,
      calibrationTime: DateTime.now(),
    );
  }
  
  @override
  String toString() => 'FaceReferenceFrame(box: $faceBox, leftEye: $leftEyePosition, rightEye: $rightEyePosition)';
}

/// 통합 얼굴 데이터
class IntegratedFaceData {
  final Face face;
  final FaceReferenceFrame referenceFrame;
  final double scaleChange; // 기준 대비 크기 변화
  final Offset positionChange; // 기준 대비 위치 변화
  final Offset leftEyePosition;
  final Offset rightEyePosition;
  final double leftEyeOpenness;
  final double rightEyeOpenness;
  final double faceStability; // 0.0 ~ 1.0
  final DateTime timestamp;
  
  const IntegratedFaceData({
    required this.face,
    required this.referenceFrame,
    required this.scaleChange,
    required this.positionChange,
    required this.leftEyePosition,
    required this.rightEyePosition,
    required this.leftEyeOpenness,
    required this.rightEyeOpenness,
    required this.faceStability,
    required this.timestamp,
  });
  
  @override
  String toString() => 'IntegratedFaceData(scale: ${scaleChange.toStringAsFixed(2)}, stability: ${faceStability.toStringAsFixed(2)})';
}

/// 눈 위치 데이터
class EyePositionData {
  final Offset position; // 절대 위치
  final Offset relativePosition; // 기준 프레임 대비 상대 위치
  final double openness; // 눈꺼풀 개폐도
  
  const EyePositionData({
    required this.position,
    required this.relativePosition,
    required this.openness,
  });
}