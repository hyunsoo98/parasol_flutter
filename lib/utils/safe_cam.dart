// lib/utils/safe_cam.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

class SafeCam {
  SafeCam(this.controller);
  final CameraController controller;

  bool _isRecording = false;
  bool _isTakingPicture = false;

  Future<void> ensureInitialized() async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
    }
  }

  Future<void> _prepareExclusive() async {
    await ensureInitialized();

    // 이미지 스트림이 켜져 있으면 반드시 중단
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // 사진 촬영 중이면 끝날 때까지 기다림
    while (controller.value.isTakingPicture) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 사진을 한 장만 안전하게 촬영 (녹화/스트림과 절대 겹치지 않게)
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
  Future<String?> recordFor(Duration duration) async {
    if (_isRecording || _isTakingPicture) return null;
    await _prepareExclusive();
    _isRecording = true;
    try {
      await controller.startVideoRecording();
      await Future.delayed(duration);
      final XFile x = await controller.stopVideoRecording(); // 반드시 await

      // ---- 확실한 mp4로 보관 ----
      final tmp = await getTemporaryDirectory();
      final out = '${tmp.path}/eye_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 드물게 .jpg 경로가 반환되는 기기 이슈 방지
      final lower = x.path.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        final fallback = await _findRecentVideoFile(tmp, const Duration(seconds: 8));
        if (fallback != null) return fallback.path;
        throw Exception('stopVideoRecording()가 사진 경로를 반환: ${x.path}');
      }

      final src = File(x.path);
      if (!await src.exists()) throw Exception('비디오 원본이 없습니다: ${x.path}');
      await src.copy(out);

      final dst = File(out);
      if (!await dst.exists() || await dst.length() == 0) {
        throw Exception('비디오 파일이 비어있습니다: $out');
      }
      return out;
    } finally {
      _isRecording = false;
    }
  }

  /// 같은 캐시 디렉토리에서 최근 mp4를 찾아 폴백
  Future<File?> _findRecentVideoFile(Directory base, Duration within) async {
    final now = DateTime.now();
    File? best;
    DateTime? bestTime;

    await for (final e in base.list(recursive: false, followLinks: false)) {
      if (e is! File) continue;
      final p = e.path.toLowerCase();
      if (!(p.endsWith('.mp4') || p.endsWith('.3gp') || p.endsWith('.mkv'))) continue;

      final stat = await e.stat();
      final age = now.difference(stat.modified);
      if (age <= within) {
        if (best == null || stat.modified.isAfter(bestTime!)) {
          best = e;
          bestTime = stat.modified;
        }
      }
    }
    return best;
  }
}
