// lib/services/mediapipe_eye_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

/// MediaPipe 이벤트 베이스
abstract class MpEvent {}

class MpFaceEvent extends MpEvent {
  final List<List<double>> landmarks; // [[x,y,z], ...] 468개 포인트
  MpFaceEvent({required this.landmarks});
}

/// MediaPipe Tasks 브릿지
class MpTasksBridge {
  MpTasksBridge._();
  static final MpTasksBridge instance = MpTasksBridge._();

  static const _method = MethodChannel('mp_tasks');
  static const _events = EventChannel('mp_tasks/events');

  Stream<MpEvent>? _stream;
  bool _isInitialized = false;

  /// MediaPipe 초기화
  Future<void> start({
    bool face = true,
    bool hands = false,
    bool useNativeCamera = false,
  }) async {
    if (_isInitialized) return;

    try {
      await _method.invokeMethod('init', {
        'face': face,
        'hands': hands,
        'useNativeCamera': useNativeCamera,
      });
      _isInitialized = true;
      debugPrint('MediaPipe Tasks 초기화 완료');
    } catch (e) {
      debugPrint('MediaPipe Tasks 초기화 실패: $e');
      throw Exception('MediaPipe Tasks 초기화 실패: $e');
    }
  }

  /// 눈동자 추적에 최적화된 설정
  Future<void> configureForEyeTracking({
    double minFaceDetection = 0.2,    // 더 민감한 얼굴 감지
    double minFacePresence = 0.2,     // 더 민감한 얼굴 존재 감지
    double minFaceTracking = 0.2,     // 더 민감한 얼굴 추적
    int maxFaces = 1,                 // 한 명만 추적
  }) async {
    try {
      await _method.invokeMethod('configure', {
        'face': {
          'minDetection': minFaceDetection,
          'minPresence': minFacePresence,
          'minTracking': minFaceTracking,
          'maxFaces': maxFaces,
        },
      });
      debugPrint('MediaPipe 눈동자 추적 설정 완료');
    } catch (e) {
      debugPrint('MediaPipe 설정 실패: $e');
    }
  }

  /// 정지
  Future<void> stop() async {
    try {
      await _method.invokeMethod('stop');
      _isInitialized = false;
      debugPrint('MediaPipe Tasks 정지 완료');
    } catch (e) {
      debugPrint('MediaPipe 정지 오류: $e');
    }
  }

  /// Flutter 카메라 프레임 전달
  Future<void> pushCameraFrame(CameraImage image) async {
    if (!_isInitialized) return;

    try {
      // CameraImage를 NV21 포맷으로 변환
      final bytes = _convertCameraImageToNV21(image);
      if (bytes == null) return;

      await _method.invokeMethod('pushFrame', {
        'bytes': bytes,
        'width': image.width,
        'height': image.height,
        'rotation': 270, // Android 기본 회전
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'format': 'nv21',
        'isFront': true,
      });
    } catch (e) {
      debugPrint('프레임 전달 오류: $e');
    }
  }

  /// CameraImage를 NV21로 변환
  Uint8List? _convertCameraImageToNV21(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.nv21) {
        // 이미 NV21 포맷인 경우
        return image.planes[0].bytes;
      }

      if (image.format.group == ImageFormatGroup.yuv420) {
        // YUV420을 NV21로 변환
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        final ySize = yPlane.bytes.length;
        final uvSize = uPlane.bytes.length + vPlane.bytes.length;
        final nv21 = Uint8List(ySize + uvSize);

        // Y 복사
        nv21.setRange(0, ySize, yPlane.bytes);

        // UV 인터리브
        int uvIndex = ySize;
        for (int i = 0; i < uPlane.bytes.length; i++) {
          nv21[uvIndex++] = vPlane.bytes[i];
          nv21[uvIndex++] = uPlane.bytes[i];
        }

        return nv21;
      }

      debugPrint('지원하지 않는 이미지 포맷: ${image.format.group}');
      return null;
    } catch (e) {
      debugPrint('이미지 변환 오류: $e');
      return null;
    }
  }

  /// 실시간 얼굴 랜드마크 스트림
  Stream<MpEvent> get events {
    _stream ??= _events
        .receiveBroadcastStream()
        .map<MpEvent?>((dynamic e) {
      try {
        final Map data = e is String
            ? json.decode(e)
            : Map<String, dynamic>.from(e);
        final type = (data['type'] ?? '').toString();

        if (type == 'face') {
          final raw = (data['landmarks'] as List?) ?? const [];
          final landmarks = raw
              .map<List<double>>((p) =>
              (p as List).map((v) => (v as num).toDouble()).toList())
              .toList();
          return MpFaceEvent(landmarks: landmarks);
        }

        return null;
      } catch (err) {
        debugPrint('[MediaPipe] 이벤트 파싱 오류: $err');
        return null;
      }
    })
        .where((e) => e != null)
        .map((e) => e!);
    return _stream!;
  }
}

/// 눈동자 추적 결과
class EyeTrackingResult {
  final bool faceDetected;
  final double confidence;
  final EyePosition? leftEye;
  final EyePosition? rightEye;
  final EyePosition? gazeCenter;
  final int landmarkCount;

  EyeTrackingResult({
    required this.faceDetected,
    required this.confidence,
    this.leftEye,
    this.rightEye,
    this.gazeCenter,
    required this.landmarkCount,
  });

  /// 정규화된 시선 위치 (0.0 ~ 1.0)
  Map<String, double>? get normalizedGaze {
    if (gazeCenter == null) return null;
    return {
      'x': gazeCenter!.x.clamp(0.0, 1.0),
      'y': gazeCenter!.y.clamp(0.0, 1.0),
    };
  }

  bool get isValid => faceDetected && confidence > 0.2 && gazeCenter != null; // 신뢰도 기준 완화 (0.3→0.2)
}

class EyePosition {
  final double x, y, z;
  EyePosition(this.x, this.y, this.z);
}

/// MediaPipe 기반 눈동자 추적 서비스
class MediaPipeEyeTrackingService {
  static MediaPipeEyeTrackingService? _instance;
  MediaPipeEyeTrackingService._internal();

  factory MediaPipeEyeTrackingService() {
    _instance ??= MediaPipeEyeTrackingService._internal();
    return _instance!;
  }

  final MpTasksBridge _bridge = MpTasksBridge.instance;
  StreamSubscription<MpEvent>? _eventSubscription;
  EyeTrackingResult? _lastResult;

  /// MediaPipe Face Mesh 468 랜드마크 중 눈 관련 인덱스
  static const List<int> _leftEyeIndices = [
    33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246
  ];

  static const List<int> _rightEyeIndices = [
    362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398
  ];

  /// 초기화
  Future<void> initialize() async {
    try {
      await _bridge.start(face: true, hands: false);
      await _bridge.configureForEyeTracking();

      // 이벤트 리스너 설정
      _eventSubscription = _bridge.events.listen(_processLandmarks);

      debugPrint('MediaPipe 눈동자 추적 서비스 초기화 완료');
    } catch (e) {
      debugPrint('MediaPipe 눈동자 추적 초기화 실패: $e');
      throw Exception('MediaPipe 눈동자 추적 초기화 실패: $e');
    }
  }

  /// 카메라 프레임 처리
  Future<void> processFrame(CameraImage image) async {
    await _bridge.pushCameraFrame(image);
  }

  /// 랜드마크 데이터 처리
  void _processLandmarks(MpEvent event) {
    if (event is MpFaceEvent) {
      final landmarks = event.landmarks;

      if (landmarks.length >= 468) {
        // 왼쪽 눈 중심점 계산
        final leftEye = _calculateEyeCenter(landmarks, _leftEyeIndices);

        // 오른쪽 눈 중심점 계산
        final rightEye = _calculateEyeCenter(landmarks, _rightEyeIndices);

        // 시선 중심점 계산 (양 눈의 중점)
        EyePosition? gazeCenter;
        if (leftEye != null && rightEye != null) {
          gazeCenter = EyePosition(
            (leftEye.x + rightEye.x) / 2,
            (leftEye.y + rightEye.y) / 2,
            (leftEye.z + rightEye.z) / 2,
          );
        }

        _lastResult = EyeTrackingResult(
          faceDetected: true,
          confidence: 0.9, // MediaPipe는 높은 신뢰도
          leftEye: leftEye,
          rightEye: rightEye,
          gazeCenter: gazeCenter,
          landmarkCount: landmarks.length,
        );

        debugPrint('MediaPipe 눈동자 추적: 중심(${gazeCenter?.x.toStringAsFixed(3)}, ${gazeCenter?.y.toStringAsFixed(3)})');
      }
    }
  }

  /// 눈 중심점 계산
  EyePosition? _calculateEyeCenter(List<List<double>> landmarks, List<int> eyeIndices) {
    try {
      double totalX = 0, totalY = 0, totalZ = 0;
      int validPoints = 0;

      for (final index in eyeIndices) {
        if (index < landmarks.length) {
          final point = landmarks[index];
          if (point.length >= 3) {
            totalX += point[0];
            totalY += point[1];
            totalZ += point[2];
            validPoints++;
          }
        }
      }

      if (validPoints > 0) {
        return EyePosition(
          totalX / validPoints,
          totalY / validPoints,
          totalZ / validPoints,
        );
      }

      return null;
    } catch (e) {
      debugPrint('눈 중심점 계산 오류: $e');
      return null;
    }
  }

  /// 최신 추적 결과 반환
  EyeTrackingResult? get latestResult => _lastResult;

  /// 정리
  void dispose() {
    _eventSubscription?.cancel();
    _bridge.stop();
    _instance = null;
    debugPrint('MediaPipe 눈동자 추적 서비스 정리 완료');
  }
}