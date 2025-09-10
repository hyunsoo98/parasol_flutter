import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'mediapipe_service.dart';

// Define Point3D class since Point might not be available
class Point3D {
  final double x;
  final double y;
  final double z;

  const Point3D({
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  String toString() => 'Point3D(x: $x, y: $y, z: $z)';
}

/// Face Mesh 478 랜드마크를 활용한 정밀 홍채 추적 서비스
class FaceMeshIrisService {
  final FaceMeshDetector _faceMeshDetector;
  final StreamController<IrisTrackingResult> _irisResultController = 
      StreamController<IrisTrackingResult>.broadcast();
  final StreamController<EyeMetrics> _leftEyeController = 
      StreamController<EyeMetrics>.broadcast();
  final StreamController<EyeMetrics> _rightEyeController = 
      StreamController<EyeMetrics>.broadcast();
  final StreamController<FaceMesh> _faceMeshController = 
      StreamController<FaceMesh>.broadcast();
  
  bool _isProcessing = false;
  int _frameCount = 0;
  
  // Face Mesh 478 랜드마크 중 홍채 관련 인덱스
  static const List<int> leftIris = [474, 475, 476, 477]; // 왼쪽 홍채
  static const List<int> rightIris = [469, 470, 471, 472]; // 오른쪽 홍채
  
  // 눈 윤곽 랜드마크 인덱스 (더 정확한 눈꺼풀 측정)
  static const List<int> leftEyeOutline = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246];
  static const List<int> rightEyeOutline = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398];
  
  Stream<IrisTrackingResult> get irisStream => _irisResultController.stream;
  Stream<EyeMetrics> get leftEyeStream => _leftEyeController.stream;
  Stream<EyeMetrics> get rightEyeStream => _rightEyeController.stream;
  Stream<FaceMesh> get faceMeshStream => _faceMeshController.stream;

  /// Face Mesh 검출기 초기화 - 빠른 인식을 위한 최적화
  FaceMeshIrisService() 
      : _faceMeshDetector = FaceMeshDetector(
          option: FaceMeshDetectorOptions.faceMesh, // Face Mesh 모드로 478개 랜드마크 사용
        );

  Future<void> processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _frameCount++;

    try {
      // 성능 ㅂ  적화: 매 2프레임마다 처리 (15fps로 안정화)
      if (_frameCount % 2 != 0) {
        _isProcessing = false;
        return;
      }
      
      final inputImage = _convertCameraImage(image);
      final faceMeshes = await _faceMeshDetector.processImage(inputImage);
      
      if (faceMeshes.isNotEmpty) {
        final mesh = faceMeshes.first;
        _faceMeshController.add(mesh); // FaceMesh 객체 전송
        await _processFaceMesh(mesh, Size(image.width.toDouble(), image.height.toDouble()));
      }
    } catch (e) {
      debugPrint('Face Mesh Iris processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processFaceMesh(FaceMesh mesh, Size imageSize) async {
    try {
      // Convert from MLKit points to our Point3D objects
      final points = mesh.points.map((p) => Point3D(
        x: p.x, 
        y: p.y, 
        z: p.z,
      )).toList();
      
      // 홍채 중심점 계산
      final leftIrisCenter = _calculateIrisCenter(points, leftIris);
      final rightIrisCenter = _calculateIrisCenter(points, rightIris);
      
      // 눈 영역 계산
      final leftEyeBounds = _calculateEyeBounds(points, leftEyeOutline);
      final rightEyeBounds = _calculateEyeBounds(points, rightEyeOutline);
      
      if (leftIrisCenter != null && rightIrisCenter != null && 
          leftEyeBounds != null && rightEyeBounds != null) {
        
        // 홍채 추적 결과 생성
        final irisResult = IrisTrackingResult(
          leftIrisCenter: leftIrisCenter,
          rightIrisCenter: rightIrisCenter,
          leftEyeBounds: leftEyeBounds,
          rightEyeBounds: rightEyeBounds,
          confidence: 0.95, // Face Mesh는 높은 신뢰도
          timestamp: DateTime.now(),
        );
        
        _irisResultController.add(irisResult);
        
        // EyeMetrics로 변환
        final leftEyeMetrics = _calculateEyeMetricsFromIris(
          leftIrisCenter, leftEyeBounds, points, leftEyeOutline, true
        );
        final rightEyeMetrics = _calculateEyeMetricsFromIris(
          rightIrisCenter, rightEyeBounds, points, rightEyeOutline, false
        );
        
        if (leftEyeMetrics != null) {
          _leftEyeController.add(leftEyeMetrics);
        }
        if (rightEyeMetrics != null) {
          _rightEyeController.add(rightEyeMetrics);
        }
      }
      
    } catch (e) {
      // 성능 최적화를 위해 에러 로그 최소화
      if (kDebugMode) debugPrint('Face mesh error: ${e.toString().substring(0, math.min(50, e.toString().length))}');
    }
  }

  /// 홍채 중심점 계산 (4개 랜드마크의 평균)
  Point3D? _calculateIrisCenter(List<Point3D> points, List<int> irisIndices) {
    if (irisIndices.any((i) => i >= points.length)) return null;
    
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final index in irisIndices) {
      final point = points[index];
      sumX += point.x;
      sumY += point.y;
      sumZ += point.z;
    }
    
    return Point3D(
      x: sumX / irisIndices.length,
      y: sumY / irisIndices.length,
      z: sumZ / irisIndices.length,
    );
  }

  /// 눈 영역 경계 계산
  Rect? _calculateEyeBounds(List<Point3D> points, List<int> eyeIndices) {
    if (eyeIndices.any((i) => i >= points.length)) return null;
    
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    
    for (final index in eyeIndices) {
      final point = points[index];
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 홍채 위치로부터 EyeMetrics 계산
  EyeMetrics? _calculateEyeMetricsFromIris(
    Point3D irisCenter, 
    Rect eyeBounds, 
    List<Point3D> points, 
    List<int> eyeOutline,
    bool isLeftEye
  ) {
    try {
      // 눈 중심점 계산
      final eyeCenter = Offset(
        eyeBounds.left + eyeBounds.width / 2,
        eyeBounds.top + eyeBounds.height / 2,
      );
      
      // 홍채 중심을 눈 중심 기준 정규화된 시선 방향으로 변환
      final gazeDirection = Offset(
        (irisCenter.x - eyeCenter.dx) / (eyeBounds.width * 0.5),
        (irisCenter.y - eyeCenter.dy) / (eyeBounds.height * 0.5),
      );
      
      // 정규화 (-1.0 ~ 1.0 범위)
      final normalizedGaze = Offset(
        math.max(-1.0, math.min(1.0, gazeDirection.dx)),
        math.max(-1.0, math.min(1.0, gazeDirection.dy)),
      );
      
      // 눈꺼풀 개폐도 계산 (눈 윤곽 랜드마크 활용)
      final eyelidOpenness = _calculateEyelidOpennessFromMesh(points, eyeOutline);
      
      return EyeMetrics(
        eyelidOpenness: eyelidOpenness,
        gazeDirection: normalizedGaze,
        confidence: 0.95, // Face Mesh 기반 높은 신뢰도
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      debugPrint('Eye metrics from iris calculation error: $e');
      return null;
    }
  }

  /// Face Mesh 기반 정밀 눈꺼풀 개폐도 계산
  double _calculateEyelidOpennessFromMesh(List<Point3D> points, List<int> eyeOutline) {
    if (eyeOutline.length < 8) return 0.8; // 기본값
    
    try {
      // 상단과 하단 랜드마크들을 분리
      final upperPoints = eyeOutline.take(eyeOutline.length ~/ 2)
          .map((i) => points[i]).toList();
      final lowerPoints = eyeOutline.skip(eyeOutline.length ~/ 2)
          .map((i) => points[i]).toList();
      
      // 수직 거리들 계산
      double totalVerticalDistance = 0;
      int validPairs = 0;
      
      for (int i = 0; i < math.min(upperPoints.length, lowerPoints.length); i++) {
        final verticalDist = (lowerPoints[i].y - upperPoints[i].y).abs();
        totalVerticalDistance += verticalDist;
        validPairs++;
      }
      
      if (validPairs == 0) return 0.8;
      
      final avgVerticalDistance = totalVerticalDistance / validPairs;
      
      // 눈 전체 너비 계산
      final eyeWidthValues = eyeOutline.map((i) => points[i].x).toList();
      final maxX = eyeWidthValues.reduce((a, b) => math.max(a, b));
      final minX = eyeWidthValues.reduce((a, b) => math.min(a, b));
      final eyeWidth = maxX - minX;
      
      // 개폐도 = 수직거리 / (눈 너비 * 0.3) 
      final openness = avgVerticalDistance / (eyeWidth * 0.3);
      
      // 0.0 ~ 1.0 범위로 클램프
      return math.max(0.0, math.min(1.0, openness));
      
    } catch (e) {
      debugPrint('Eyelid openness calculation error: $e');
      return 0.8;
    }
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = _concatenatePlanes(image.planes);
    
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.yuv420,
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

  Future<void> dispose() async {
    _isProcessing = false;
    await _faceMeshDetector.close();
    await _irisResultController.close();
    await _leftEyeController.close();
    await _rightEyeController.close();
    await _faceMeshController.close();
  }
}

/// 홍채 추적 결과
class IrisTrackingResult {
  final Point3D leftIrisCenter;
  final Point3D rightIrisCenter;
  final Rect leftEyeBounds;
  final Rect rightEyeBounds;
  final double confidence;
  final DateTime timestamp;
  
  const IrisTrackingResult({
    required this.leftIrisCenter,
    required this.rightIrisCenter,
    required this.leftEyeBounds,
    required this.rightEyeBounds,
    required this.confidence,
    required this.timestamp,
  });
}

/// Face Mesh 478 포인트 오버레이 페인터
class FaceMeshOverlayPainter extends CustomPainter {
  final FaceMesh? mesh;
  final Size imageSize;
  final IrisTrackingResult? irisResult;
  
  FaceMeshOverlayPainter({
    required this.mesh, 
    required this.imageSize,
    this.irisResult,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (mesh == null) return;
    
    // Convert from MLKit points to our Point3D objects
    final points = mesh!.points.map((p) => Point3D(
      x: p.x, 
      y: p.y, 
      z: p.z,
    )).toList();
    
    // 홍채 그리기
    _drawIris(canvas, size, points);
    
    // 눈 윤곽 그리기
    _drawEyeOutlines(canvas, size, points);
    
    // 추가 디버깅 정보
    if (irisResult != null) {
      _drawIrisInfo(canvas, size);
    }
  }
  
  void _drawIris(Canvas canvas, Size size, List<Point3D> points) {
    final irisPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.fill;
    
    final irisOutlinePaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // 왼쪽 홍채
    for (final idx in FaceMeshIrisService.leftIris) {
      if (idx < points.length) {
        final p = _scalePoint(points[idx], imageSize, size);
        canvas.drawCircle(p, 4, irisPaint);
        canvas.drawCircle(p, 8, irisOutlinePaint);
      }
    }
    
    // 오른쪽 홍채
    for (final idx in FaceMeshIrisService.rightIris) {
      if (idx < points.length) {
        final p = _scalePoint(points[idx], imageSize, size);
        canvas.drawCircle(p, 4, irisPaint);
        canvas.drawCircle(p, 8, irisOutlinePaint);
      }
    }
  }
  
  void _drawEyeOutlines(Canvas canvas, Size size, List<Point3D> points) {
    final eyePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // 왼쪽 눈 윤곽
    _drawConnectedPoints(canvas, size, points, FaceMeshIrisService.leftEyeOutline, eyePaint);
    
    // 오른쪽 눈 윤곽
    _drawConnectedPoints(canvas, size, points, FaceMeshIrisService.rightEyeOutline, eyePaint);
  }
  
  void _drawConnectedPoints(Canvas canvas, Size size, List<Point3D> points, 
                          List<int> indices, Paint paint) {
    if (indices.length < 2) return;
    
    final path = Path();
    bool firstPoint = true;
    
    for (final idx in indices) {
      if (idx < points.length) {
        final p = _scalePoint(points[idx], imageSize, size);
        if (firstPoint) {
          path.moveTo(p.dx, p.dy);
          firstPoint = false;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
  
  void _drawIrisInfo(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🎯 Face Mesh 478-Point Iris Tracking',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, size.height - 30));
  }
  
  /// 카메라 좌표계를 위젯 좌표계로 변환
  Offset _scalePoint(Point3D point, Size sourceSize, Size targetSize) {
    return Offset(
      (point.x / sourceSize.width) * targetSize.width,
      (point.y / sourceSize.height) * targetSize.height,
    );
  }
  
  @override
  bool shouldRepaint(covariant FaceMeshOverlayPainter oldDelegate) {
    return oldDelegate.mesh != mesh || oldDelegate.irisResult != irisResult;
  }
}