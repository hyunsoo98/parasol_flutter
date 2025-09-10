// lib/services/eye_capture_flow.dart
import 'dart:io';
import 'package:camera/camera.dart';
import '../utils/safe_cam.dart';
import 'mediapipe_api_service.dart';

class EyeCaptureFlow {
  EyeCaptureFlow(this.controller) : safeCam = SafeCam(controller);
  final CameraController controller;
  final SafeCam safeCam;

  /// (선택) 캘리브레이션 사진을 먼저 찍고, 이어서 [duration]만큼 촬영 → 서버 분석
  /// return: 서버 응답(Map)과 파일 경로
  Future<({Map<String, dynamic> response, String videoPath})> run({
    Duration duration = const Duration(seconds: 6),
    bool takeCalibrationShot = false,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
    bool returnLandmarks = false,
    bool returnOverlay = false,
  }) async {
    // 0) (선택) 캘리브레이션 샷
    if (takeCalibrationShot) {
      await safeCam.takeOneShot(); // 실패해도 흐름 진행
    }

    // 1) 녹화
    final path = await safeCam.recordFor(duration);
    if (path == null) {
      throw Exception('비디오 녹화 실패(경로 없음)');
    }

    // 2) 파일 검증
    final f = File(path);
    if (!await f.exists() || await f.length() == 0) {
      throw Exception('비디오 파일이 비어 있습니다(0 bytes)');
    }

    // 3) 업로드/분석
    final api = MediaPipeApiService();
    final res = await api.processEyeVideoFile(
      path,
      step: 1,
      vppThresh: vppThresh,
      blinkThresh: blinkThresh,
      maxFrames: maxFrames,
      returnLandmarks: returnLandmarks,
      returnOverlay: returnOverlay,
    );

    return (response: res, videoPath: path);
  }
}
