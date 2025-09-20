// lib/core/landmarks/mediapipe_tasks.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// ─────────────────────────────────────────────────────────────────
/// 이벤트 베이스
abstract class MpEvent {}

class MpFaceEvent extends MpEvent {
  final List<List<double>> landmarks; // [ [x,y,z], ... ]
  MpFaceEvent({required this.landmarks});
}

class MpHandEvent extends MpEvent {
  final String handedness; // "Left" | "Right"
  final List<List<double>> landmarks;
  MpHandEvent({required this.handedness, required this.landmarks});
}

/// ─────────────────────────────────────────────────────────────────
/// 브릿지 (플랫폼 채널)
class MpTasksBridge {
  MpTasksBridge._();
  static final MpTasksBridge instance = MpTasksBridge._();

  static const _method = MethodChannel('mp_tasks');
  static const _events = EventChannel('mp_tasks/events');

  Stream<MpEvent>? _stream;

  /// 네이티브 파이프 시작
  /// - useNativeCamera=false: Flutter가 pushFrame으로 보낸 프레임만 사용(권장)
  Future<void> start({
    bool face = true,
    bool hands = false,
    bool useNativeCamera = false, // (Android에서는 의미 없음)
  }) async {
    // ✅ 'start'가 아니라 'init'을 호출
    await _method.invokeMethod('init', {
      'face': face,
      'hands': hands,
      'useNativeCamera': useNativeCamera,
    });
  }

  /// 옵션(신뢰도 임계값 등) — 네이티브 지원 시
  Future<void> configure({
    double minFaceDetection = 0.3,
    double minFacePresence = 0.3,
    double minFaceTracking = 0.3,
    int maxFaces = 1,
  }) async {
    await _method.invokeMethod('configure', {
      'face': {
        'minDetection': minFaceDetection,
        'minPresence': minFacePresence,
        'minTracking': minFaceTracking,
        'maxFaces': maxFaces,
      },
    });
  }

  /// 정지
  Future<void> stop() async {
    await _method.invokeMethod('stop');
  }

  /// Flutter 카메라 프레임 전달
  /// - Android: NV21, iOS: BGRA8888
  Future<void> pushFrame({
    required Uint8List bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    required int timestampMs,
    required String pixelFormat, // 'nv21' | 'bgra8888'
    bool isFrontCamera = true,
  }) async {
    await _method.invokeMethod('pushFrame', {
      'bytes': bytes,
      'width': width,
      'height': height,
      'rotation': rotationDegrees,
      'timestampMs': timestampMs,
      'format': pixelFormat,
      'isFront': isFrontCamera,
    });
  }

  /// Android용: YUV_420_888 평면 + stride 그대로 전달
  /// 네이티브(MethodChannel "mp_tasks")에서 "processYuv420Planes"를 구현해야 함.
  Future<void> processYuv420Planes({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    required int uPixelStride,
    required int vPixelStride,
    required int rotationDeg,  // 0/90/180/270
    required int timestampMs,
  }) async {
    await _method.invokeMethod('processYuv420Planes', {
      'y': y,
      'u': u,
      'v': v,
      'width': width,
      'height': height,
      'yRowStride': yRowStride,
      'uRowStride': uRowStride,
      'vRowStride': vRowStride,
      'uPixelStride': uPixelStride,
      'vPixelStride': vPixelStride,
      'rotationDeg': rotationDeg,
      'timestampMs': timestampMs,
    });
  }


  /// 이벤트 스트림 (안전 파싱; 구형 SDK 호환)
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
          final lm = raw
              .map<List<double>>((p) =>
              (p as List).map((v) => (v as num).toDouble()).toList())
              .toList();
          return MpFaceEvent(landmarks: lm);
        }

        if (type == 'hand') {
          final raw = (data['landmarks'] as List?) ?? const [];
          final lm = raw
              .map<List<double>>((p) =>
              (p as List).map((v) => (v as num).toDouble()).toList())
              .toList();
          final handed = (data['handedness'] ?? 'Unknown').toString();
          return MpHandEvent(handedness: handed, landmarks: lm);
        }

        debugPrint('[mp] skip unknown event type: $type');
        return null; // 알 수 없는 타입은 무시
      } catch (err) {
        debugPrint('[mp] event parse error: $err');
        return null; // 파싱 실패도 무시
      }
    })
    // ★ 구형 SDK 호환: whereType 대신 null 필터 + non-null 매핑
        .where((e) => e != null)
        .map((e) => e!);
    return _stream!;
  }
}