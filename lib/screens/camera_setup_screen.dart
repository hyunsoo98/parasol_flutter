import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import '../services/permission_service.dart';
import '../services/mediapipe_api_service.dart';
import 'structured_eye_test_screen.dart'; // API 연결 활성화
import 'final_diagnosis_screen.dart';
import 'camera_setup_screen_widgets.dart';

class CameraSetupScreen extends StatefulWidget {
  const CameraSetupScreen({Key? key}) : super(key: key);

  @override
  State<CameraSetupScreen> createState() => _CameraSetupScreenState();
}

class _CameraSetupScreenState extends State<CameraSetupScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool _isInitialized = false;

  // 녹화 상태
  bool _isRecording = false;
  bool _stopping = false;
  bool _isDisposing = false; // 안전 해제 플래그
  DateTime _minEndAt = DateTime.now();

  // 테스트(안내 전용)
  bool _testStarted = false;
  bool _isTestActive = false;
  int _currentTestCycle = 0;
  final int _maxTestCycles = 6;
  String _currentDirection = ''; // '위' / '아래'
  Color _feedbackColor = Colors.white;
  Timer? _testTimer;

  // 준비 카운트다운(버튼 활성화 지연)
  int _readyCountdown = 2;
  Timer? _readyTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _statusMessage = '카메라를 초기화하는 중...';
  Color _statusColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  Future<void> _initializeCamera() async {
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _statusMessage = '카메라 권한이 필요합니다';
          _statusColor = Colors.red;
        });
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final frontCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras![0],
        );

        _controller = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false, // 오디오 경합 방지
        );
        await _controller!.initialize();

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _statusMessage = '얼굴을 화면 중앙의 타원 안에 맞춰주세요';
            _statusColor = const Color(0xFF2F3DA3);
          });
        }

        // 간단 준비 카운트다운 후 버튼 활성화
        _readyTimer =
            Timer.periodic(const Duration(seconds: 1), (Timer t) {
          if (_readyCountdown <= 1) {
            t.cancel();
            if (!mounted) return;
            setState(() {
              _readyCountdown = 0;
              _statusMessage = '준비 완료! "검사 시작"을 누르세요';
              _statusColor = Colors.green;
            });
          } else {
            setState(() => _readyCountdown -= 1);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '카메라 초기화 실패: $e';
          _statusColor = Colors.red;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _readyCountdown == 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('카메라 설정', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // 녹화/정지 중 이탈 금지
            if (_isRecording || _stopping) return;
            _releaseCameraController();
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: _isInitialized
          ? Stack(
              children: [
                Positioned.fill(child: CameraPreview(_controller!)),
                Positioned.fill(child: _buildGuideOverlay()),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: _buildStatusPanel(canStart),
                ),
                if (_isTestActive) _buildDirectionIndicator(),
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: _buildBottomButton(canStart),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildGuideOverlay() {
    return CameraGuideOverlay(pulseAnimation: _pulseAnimation);
  }

  Widget _buildStatusPanel(bool canStart) {
    return CameraStatusPanel(
      canStart: canStart,
      statusMessage: _statusMessage,
      statusColor: _statusColor,
    );
  }

  Widget _buildBottomButton(bool canStart) {
    return CameraBottomButton(
      canStart: canStart,
      testStarted: _testStarted,
      onPressed: _proceedToNextStep,
    );
  }

  Widget _buildDirectionIndicator() {
    return CameraDirectionIndicator(
      currentDirection: _currentDirection,
      feedbackColor: _feedbackColor,
    );
  }

  void _proceedToNextStep() async {
    if (!_testStarted) {
      await _startEyeTrackingTest();
    } else {
      await _completeTest();
    }
  }

  Future<void> _startEyeTrackingTest() async {
    setState(() {
      _testStarted = true;
      _currentTestCycle = 0;
      _statusMessage = '검사를 시작합니다.';
      _statusColor = Colors.blue;
    });

    // 녹화 준비 & 시작
    await _prepareAndStartRecording();

    // 짧게 대기 후 첫 사이클 시작(녹화 안정화)
    await Future.delayed(const Duration(milliseconds: 300));
    _runTestCycle();
  }

  Future<void> _runTestCycle() async {
    if (_currentTestCycle >= _maxTestCycles) {
      await _completeTest();
      return;
    }

    setState(() {
      _currentDirection = _currentTestCycle % 2 == 0 ? '위' : '아래';
      _isTestActive = true;
      _feedbackColor = Colors.yellow;
      _statusMessage =
          '${_currentTestCycle + 1}/$_maxTestCycles 단계 - $_currentDirection 쪽을 보세요';
    });

    // 3초 대기 후 다음 단계
    _testTimer?.cancel();
    _testTimer = Timer(const Duration(seconds: 3), () {
      _currentTestCycle++;
      _runTestCycle();
    });
  }

  Future<void> _completeTest() async {
    setState(() {
      _isTestActive = false;
      _statusMessage = '검사가 완료되었습니다';
      _statusColor = Colors.green;
      _feedbackColor = Colors.green;
    });

    // 잠깐 대기 후 녹화 종료 및 파일 확보
    await Future.delayed(const Duration(milliseconds: 200));

    File? stableFile;
    try {
      stableFile = await _stopAndFinalizeRecording();

      // API 업로드 연결 활성화
      if (stableFile != null) {
        setState(() {
          _statusMessage = '비디오 파일 준비 중...';
          _statusColor = Colors.blue;
        });

        // 파일 크기 확인 및 압축
        final fileSize = await stableFile.length();
        debugPrint('원본 비디오 크기: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

        File finalVideoFile = stableFile;
        const maxSize = 6 * 1024 * 1024; // 6MB

        if (fileSize > maxSize) {
          setState(() {
            _statusMessage = '비디오 압축 중...';
          });

          try {
            final compressedInfo = await VideoCompress.compressVideo(
              stableFile.path,
              quality: VideoQuality.LowQuality,
              deleteOrigin: false,
              includeAudio: false,
              frameRate: 15,
            );

            if (compressedInfo?.file != null) {
              finalVideoFile = compressedInfo!.file!;
              final compressedSize = await finalVideoFile.length();
              debugPrint('압축된 비디오 크기: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');

              // 여전히 크면 더 낮은 품질로 재압축
              if (compressedSize > maxSize) {
                setState(() {
                  _statusMessage = '추가 압축 중...';
                });

                final secondCompressed = await VideoCompress.compressVideo(
                  finalVideoFile.path,
                  quality: VideoQuality.LowQuality,
                  deleteOrigin: true,
                  includeAudio: false,
                  frameRate: 10,
                );

                if (secondCompressed?.file != null) {
                  finalVideoFile = secondCompressed!.file!;
                  final finalSize = await finalVideoFile.length();
                  debugPrint('최종 압축 크기: ${(finalSize / 1024 / 1024).toStringAsFixed(2)} MB');
                }
              }
            }
          } catch (e) {
            debugPrint('압축 실패, 원본 사용: $e');
          }
        }

        setState(() {
          _statusMessage = 'MediaPipe로 분석 중...';
          _statusColor = Colors.blue;
        });

        try {
          // 기존 서버 분석 방식은 더 이상 지원되지 않습니다.
          // StructuredEyeTestScreen을 사용하여 실시간 클라이언트 분석을 진행하세요.
          setState(() {
            _statusMessage = '시선추적 분석이 실시간 방식으로 변경되었습니다.\nStructuredEyeTest를 이용해주세요.';
            _statusColor = Colors.orange;
          });

          // 새로운 실시간 테스트 화면으로 이동
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => StructuredEyeTestScreen(
                userId: 'guest_${DateTime.now().millisecondsSinceEpoch}',
              ),
            ),
          );
          return;

          // 이 코드는 더 이상 실행되지 않습니다 (위에서 return되므로)
          // 기존 서버 분석 방식 제거로 인해 주석 처리됨
          /*
          // 결과 화면으로 이동
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => FinalDiagnosisScreen(
                  eyeTrackingResult: result.toJson(),
                  videoPath: stableFile!.path,
                ),
              ),
            );
          }
          return; // 성공 시 여기서 종료
          */
        } catch (e) {
          debugPrint('API 분석 실패: $e');
          setState(() {
            _statusMessage = '분석 중 오류: $e';
            _statusColor = Colors.orange;
          });
        }
      }
    } catch (e) {
      debugPrint('녹화 종료/파일 확보 실패: $e');
    }

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const FinalDiagnosisScreen()),
    );
  }

  // ────────────── 녹화 관련 유틸 ──────────────

  Future<void> _prepareAndStartRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    _minEndAt = DateTime.now().add(const Duration(seconds: 1)); // 최소 녹화 시간

    try {
      await _controller!.prepareForVideoRecording();
    } catch (_) {
      // 일부 단말 미구현 → 무시
    }

    // 살짝 쉰 뒤 시작(경합 완화)
    await Future.delayed(const Duration(milliseconds: 100));
    await _controller!.startVideoRecording();
    _isRecording = true;
  }

  Future<File?> _stopAndFinalizeRecording() async {
    if (_controller == null) return null;
    if (_stopping) return null;
    if (!_controller!.value.isRecordingVideo) return null;

    _stopping = true;
    try {
      final now = DateTime.now();
      if (now.isBefore(_minEndAt)) {
        await Future.delayed(_minEndAt.difference(now));
      }

      // 경합 완화
      await Future.delayed(const Duration(milliseconds: 100));

      final x = await _controller!.stopVideoRecording();
      _isRecording = false;

      final stable = await _finalizeRecordedVideoFromXFile(x);
      return stable;
    } finally {
      _stopping = false;
    }
  }

  Future<File> _finalizeRecordedVideoFromXFile(XFile x) async {
    // stop 반환 후 파일 늦게 생기는 단말 커버(최대 5초)
    final tmp = File(x.path);
    const tries = 25;
    for (int i = 0; i < tries; i++) {
      if (await tmp.exists()) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    File source;
    if (await tmp.exists()) {
      source = tmp;
    } else {
      // 같은 캐시 폴더에서 최신 mp4 스캔
      final dir = Directory(p.dirname(x.path));
      final candidates = <File>[];
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File && e.path.toLowerCase().endsWith('.mp4')) {
            candidates.add(e);
          }
        }
      }
      candidates.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (candidates.isEmpty) {
        throw Exception('녹화 파일 생성 실패: ${x.path}');
      }
      source = candidates.first;
    }

    final docs = await getApplicationDocumentsDirectory();
    final outPath = p.join(
      docs.path,
      'eye_tracking_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    return await source.copy(outPath);
  }

  // ────────────── 안전 해제 ──────────────
  void _releaseCameraController() {
    if (_isDisposing) return;
    _isDisposing = true;
    try {
      final controller = _controller;
      if (controller == null) return;

      // 외부 접근 끊기
      _controller = null;

      // orientation lock/unlock 제거 - 문제 발생 요소

      try {
        controller.dispose();
      } catch (_) {}
    } finally {
      _isDisposing = false;
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _testTimer?.cancel();

    _releaseCameraController();

    _pulseController.dispose();
    super.dispose();
  }
}
