// lib/services/eye_capture_kit.dart
//
// 하나로 통합한 "안전 캡처 + 업로드/분석" 키트
// - 사진/이미지스트림/영상 녹화의 동시 호출을 강하게 차단
// - stopVideoRecording 직후 파일 flush 지연 / .jpg 혼입 / 0 bytes 방지
// - EyeCaptureFlow.run(...) 한 번으로 녹화→검증→업로드까지 처리
//
// 사용 예:
// final flow = EyeCaptureFlow(_controller);
// final result = await flow.run(
//   duration: const Duration(seconds: 6),
//   takeCalibrationShot: false,
//   vppThresh: 0.06,
//   blinkThresh: 0.18,
//   maxFrames: 12000,
// );
//
// print(result.videoPath);
// print(result.response);

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

// MediaPipe 업로더를 쓰려면 주석 해제
import 'mediapipe_api_service.dart';

class SafeCam {
  SafeCam(this.controller);
  final CameraController controller;

  bool _isRecording = false;
  bool _isTakingPicture = false;

  Future<void> ensureInitialized() async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
      // (선택) 영상 관련 내부 준비: 기기별 안정성 ↑
      try { await controller.prepareForVideoRecording(); } catch (_) {}
    }
  }

  Future<void> _prepareExclusive() async {
    await ensureInitialized();

    // 어떤 경우에도 동시 캡처 금지
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // 사진 촬영 중이면 종료까지 대기
    while (controller.value.isTakingPicture) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 이전 녹화가 남아 있다면 종료까지 대기
    while (controller.value.isRecordingVideo) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 녹화/스트림과 절대 겹치지 않게 "한 장"만 촬영
  Future<String?> takeOneShot() async {
    if (_isRecording || _isTakingPicture) return null;
    await _prepareExclusive();
    _isTakingPicture = true;
    try {
      final x = await controller.takePicture(); // 반드시 await
      final f = File(x.path);
      if (!await f.exists() || await f.length() == 0) return null;
      return x.path;
    } finally {
      _isTakingPicture = false;
    }
  }

  /// [duration] 동안 영상 녹화 후 mp4 파일 경로 반환
  /// - stopVideoRecording() 직후 파일 flush 지연, .jpg 혼입까지 모두 대비
  Future<String?> recordFor(Duration duration) async {
    if (_isRecording || _isTakingPicture) return null;
    await _prepareExclusive();
    _isRecording = true;
    try {
      // 녹화 시작
      await controller.startVideoRecording();
      if (!controller.value.isRecordingVideo) return null;

      await Future.delayed(duration);

      // 반드시 await로 정지
      XFile x;
      try {
        x = await controller.stopVideoRecording();
      } catch (_) {
        // stop 실패해도 폴백 탐색으로 복구 시도
        x = XFile('');
      }

      // 보존용 출력 경로
      final tmp = await getTemporaryDirectory();
      final out = '${tmp.path}/eye_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 1) saveTo가 가장 신뢰도 높음
      var saved = false;
      try {
        await x.saveTo(out); // Android/iOS 지원 (구형 기기에서 예외 가능)
        saved = true;
      } catch (_) {
        // 무시하고 폴백
      }

      // 2) 원본 경로 복사 폴백
      if (!saved) {
        final srcPath = x.path;
        if (srcPath.isNotEmpty) {
          final src = File(srcPath);
          if (await src.exists()) {
            try {
              await src.copy(out);
              saved = true;
            } catch (_) {}
          }
        }
      }

      // 3) 마지막 폴백: 바이트로 강제 저장
      if (!saved) {
        try {
          final bytes = await x.readAsBytes(); // 경로 비어도 동작할 수 있음
          final dst = File(out);
          await dst.writeAsBytes(bytes, flush: true);
          saved = true;
        } catch (_) {}
      }

      // 4) 저장 확인: 존재 && 크기 > 0 될 때까지 짧게 대기
      final okFile = await _waitForFile(path: out, within: const Duration(seconds: 3));
      if (okFile != null) return okFile.path;

      // 5) 캐시에서 "아주 최근" mp4를 기다리며 탐색 (벤더/OS 플러시 지연 대응)
      final found = await _waitAndFindRecentVideo(
        within: const Duration(seconds: 6),
        poll: const Duration(milliseconds: 200),
      );
      if (found != null && await _isValidFile(found)) {
        // 보존 이름으로 복사
        await found.copy(out);
        final finalOk = await _waitForFile(path: out, within: const Duration(seconds: 2));
        if (finalOk != null) return finalOk.path;
      }

      // 완전 실패
      return null;
    } finally {
      _isRecording = false;
    }
  }

  Future<bool> _isValidFile(File f) async {
    return await f.exists() && (await f.length()) > 0;
  }

  /// 지정한 path가 "존재 && size>0"가 될 때까지 최대 [within] 동안 [poll] 간격으로 대기
  Future<File?> _waitForFile({
    required String path,
    Duration within = const Duration(seconds: 3),
    Duration poll = const Duration(milliseconds: 120),
  }) async {
    final f = File(path);
    final deadline = DateTime.now().add(within);
    while (DateTime.now().isBefore(deadline)) {
      if (await f.exists()) {
        final len = await f.length();
        if (len > 0) return f;
      }
      await Future.delayed(poll);
    }
    return null;
  }

  /// 앱 캐시/외부캐시 등에서 "아주 최근" mp4를 기다리며 탐색
  Future<File?> _waitAndFindRecentVideo({
    required Duration within,
    required Duration poll,
  }) async {
    final deadline = DateTime.now().add(within);
    File? candidate;
    DateTime? bestTime;

    Future<void> scanDir(Directory d) async {
      if (!await d.exists()) return;
      await for (final e in d.list(recursive: false, followLinks: false)) {
        if (e is! File) continue;
        final p = e.path.toLowerCase();
        if (!(p.endsWith('.mp4') || p.endsWith('.3gp') || p.endsWith('.mkv'))) continue;

        final stat = await e.stat();
        if (bestTime == null || stat.modified.isAfter(bestTime!)) {
          bestTime = stat.modified;
          candidate = e;
        }
      }
    }

    final cache = await getTemporaryDirectory();
    final targets = <Directory>[cache];
    try {
      final extCaches = await getExternalCacheDirectories();
      if (extCaches != null) targets.addAll(extCaches);
    } catch (_) {} // iOS 등 미지원은 무시

    while (DateTime.now().isBefore(deadline)) {
      for (final d in targets) {
        await scanDir(d);
      }
      if (candidate != null && await _isValidFile(candidate!)) {
        return candidate;
      }
      await Future.delayed(poll);
    }
    return null;
  }
}

class EyeCaptureFlow {
  EyeCaptureFlow(this.controller) : safeCam = SafeCam(controller);
  final CameraController controller;
  final SafeCam safeCam;

  /// 정렬샷(옵션) → 영상 녹화 → 파일검증 → 업로드/분석
  ///
  /// 반환: ({ response, videoPath })
  Future<({Map<String, dynamic> response, String videoPath})> run({
    Duration duration = const Duration(seconds: 6),
    bool takeCalibrationShot = false,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
    bool returnLandmarks = false,
    bool returnOverlay = false,
  }) async {
    // (선택) 녹화 이전에만 정렬샷 1장
    if (takeCalibrationShot) {
      await safeCam.takeOneShot(); // 실패해도 진행
    }

    // 녹화
    final path = await safeCam.recordFor(duration);
    if (path == null) {
      throw Exception('비디오 녹화 실패: 파일을 찾을 수 없습니다(.jpg 혼입/flush 지연/0 bytes)');
    }

    // 파일 검증
    final f = File(path);
    if (!await f.exists() || await f.length() == 0) {
      throw Exception('비디오 파일이 비어 있습니다(0 bytes)');
    }

    // 업로드/분석 (엔드포인트는 /api/eye/process로 이미 교정되어 있어야 함)
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
