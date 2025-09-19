import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/test_flow_service.dart';
import '../services/api_service.dart';
import 'finger_tapping_screen.dart';

/// 구조화된 시선추적 테스트 화면 - TTS 가이드와 실시간 ML Kit 분석
class StructuredEyeTestScreen extends StatefulWidget {
  final String userId;

  const StructuredEyeTestScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<StructuredEyeTestScreen> createState() => _StructuredEyeTestScreenState();
}

class _StructuredEyeTestScreenState extends State<StructuredEyeTestScreen> {
  // 카메라 관련
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // ML Kit 관련
  final FaceDetector _faceDetector = GoogleVision.instance.faceDetector(
    FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
    ),
  );

  // TTS 관련
  late FlutterTts _flutterTts;

  // 테스트 상태
  TestPhase _currentPhase = TestPhase.introduction;
  int _currentSet = 0;
  int _currentStep = 0; // 0: center, 1: up, 2: center, 3: down, 4: center
  final int _totalSets = 5;

  // 타이머
  Timer? _phaseTimer;
  Timer? _analysisTimer;
  DateTime? _testStartTime;

  // 분석 데이터
  final List<Map<String, dynamic>> _frameAnalyses = [];
  bool _faceDetected = false;
  bool _eyesOpen = true;
  double _irisX = 0.5;
  double _irisY = 0.5;
  double _confidence = 0.0;

  // 테스트 플로우 서비스
  late TestFlowService _testFlowService;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeCamera();
    _initializeTTS();
  }

  void _initializeServices() {
    _testFlowService = TestFlowService(apiService: ApiService());
    _sessionId = _testFlowService.startNewTestSession(widget.userId);
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
      );

      try {
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          _startCameraStream();
        }
      } catch (e) {
        print('카메라 초기화 실패: $e');
      }
    }
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);
  }

  void _startCameraStream() {
    _cameraController!.startImageStream((CameraImage image) {
      if (_currentPhase == TestPhase.gazeTest) {
        _processFrame(image);
      }
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        _analyzeFaceData(face);
      } else {
        _recordNoFaceDetected();
      }
    } catch (e) {
      print('프레임 처리 오류: $e');
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotationValue.fromRawValue(
        _cameraController!.description.sensorOrientation,
      );

      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);

      final inputImageData = InputImageData(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        imageRotation: imageRotation ?? InputImageRotation.rotation0deg,
        inputImageFormat: inputImageFormat ?? InputImageFormat.nv21,
        planeData: image.planes.map((plane) => InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        )).toList(),
      );

      return InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
    } catch (e) {
      print('이미지 변환 오류: $e');
      return null;
    }
  }

  void _analyzeFaceData(Face face) {
    // 눈 위치 및 상태 분석
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye != null && rightEye != null) {
      _irisX = (leftEye.position.dx + rightEye.position.dx) / 2 / _cameraController!.value.previewSize!.width;
      _irisY = (leftEye.position.dy + rightEye.position.dy) / 2 / _cameraController!.value.previewSize!.height;
    }

    _faceDetected = true;
    _eyesOpen = (face.leftEyeOpenProbability ?? 0.5) > 0.5 &&
               (face.rightEyeOpenProbability ?? 0.5) > 0.5;
    _confidence = face.trackingId != null ? 0.9 : 0.7;

    _recordFrameAnalysis();
  }

  void _recordNoFaceDetected() {
    _faceDetected = false;
    _confidence = 0.0;
    _recordFrameAnalysis();
  }

  void _recordFrameAnalysis() {
    if (_currentPhase != TestPhase.gazeTest) return;

    final analysisData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'iris_x': _irisX,
      'iris_y': _irisY,
      'eye_open': _eyesOpen,
      'face_detected': _faceDetected,
      'confidence': _confidence,
      'phase': _getCurrentGazePhase(),
      'set': _currentSet,
      'step': _currentStep,
    };

    _frameAnalyses.add(analysisData);
  }

  String _getCurrentGazePhase() {
    switch (_currentStep) {
      case 0:
      case 2:
      case 4:
        return 'center';
      case 1:
        return 'up';
      case 3:
        return 'down';
      default:
        return 'unknown';
    }
  }

  // TTS 음성 안내
  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  // 테스트 단계 진행
  void _startTest() async {
    setState(() {
      _currentPhase = TestPhase.introduction;
    });

    await _speak('시선추적 검사를 시작합니다. 화면의 안내를 따라 시선을 움직여 주세요.');
    await Future.delayed(const Duration(seconds: 3));

    _proceedToFaceAlignment();
  }

  void _proceedToFaceAlignment() async {
    setState(() {
      _currentPhase = TestPhase.faceAlignment;
    });

    await _speak('얼굴을 화면 중앙에 맞춰 주세요. 얼굴이 인식되면 자동으로 다음 단계로 진행됩니다.');

    _phaseTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_faceDetected && _confidence > 0.7) {
        timer.cancel();
        _proceedToGazeTest();
      }
    });

    // 30초 후 타임아웃
    Timer(const Duration(seconds: 30), () {
      if (_currentPhase == TestPhase.faceAlignment) {
        _phaseTimer?.cancel();
        _proceedToGazeTest(); // 강제 진행
      }
    });
  }

  void _proceedToGazeTest() async {
    setState(() {
      _currentPhase = TestPhase.gazeTest;
      _currentSet = 0;
      _currentStep = 0;
    });

    _testStartTime = DateTime.now();
    await _speak('이제 시선을 위아래로 움직이는 테스트를 시작합니다. 총 5세트를 진행합니다.');
    await Future.delayed(const Duration(seconds: 2));

    _startGazeSet();
  }

  void _startGazeSet() async {
    await _speak('${_currentSet + 1}번째 세트를 시작합니다.');
    await Future.delayed(const Duration(seconds: 1));

    _executeGazeSequence();
  }

  void _executeGazeSequence() async {
    // 5단계: center(1s) -> up(3s) -> center(1s) -> down(3s) -> center(1s)
    final sequences = [
      {'phase': 'center', 'duration': 1, 'instruction': '화면 중앙을 보세요'},
      {'phase': 'up', 'duration': 3, 'instruction': '위를 보세요'},
      {'phase': 'center', 'duration': 1, 'instruction': '다시 중앙을 보세요'},
      {'phase': 'down', 'duration': 3, 'instruction': '아래를 보세요'},
      {'phase': 'center', 'duration': 1, 'instruction': '중앙으로 돌아와 주세요'},
    ];

    for (int step = 0; step < sequences.length; step++) {
      setState(() {
        _currentStep = step;
      });

      final sequence = sequences[step];
      await _speak(sequence['instruction'] as String);

      // 지정된 시간만큼 대기하며 분석
      await Future.delayed(Duration(seconds: sequence['duration'] as int));
    }

    _currentSet++;
    if (_currentSet < _totalSets) {
      _startGazeSet();
    } else {
      _completeTest();
    }
  }

  void _completeTest() async {
    setState(() {
      _currentPhase = TestPhase.completed;
    });

    await _speak('시선추적 검사가 완료되었습니다. 결과를 분석 중입니다.');

    final testDuration = DateTime.now().difference(_testStartTime!).inMilliseconds / 1000.0;

    // 서버로 결과 전송
    final result = await _testFlowService.completeEyeTest(
      frameAnalyses: _frameAnalyses,
      testDuration: testDuration,
      totalFrames: _frameAnalyses.length,
      processingFps: _frameAnalyses.length / testDuration,
      additionalMetadata: {
        'total_sets': _totalSets,
        'platform': 'flutter',
        'tts_guided': true,
      },
    );

    if (result['success'] == true) {
      await _speak('분석이 완료되었습니다. 다음 검사로 이동하겠습니다.');
      _proceedToFingerTapping();
    } else {
      await _speak('분석 중 오류가 발생했습니다. 다시 시도해 주세요.');
    }
  }

  void _proceedToFingerTapping() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => FingerTappingScreen(
          testFlowService: _testFlowService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 카메라 미리보기
          if (_isCameraInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),

          // 오버레이 UI
          Positioned.fill(
            child: _buildPhaseOverlay(),
          ),

          // 상태 정보 표시
          Positioned(
            top: 50,
            left: 20,
            child: _buildStatusInfo(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseOverlay() {
    switch (_currentPhase) {
      case TestPhase.introduction:
        return _buildIntroductionOverlay();
      case TestPhase.faceAlignment:
        return _buildFaceAlignmentOverlay();
      case TestPhase.gazeTest:
        return _buildGazeTestOverlay();
      case TestPhase.completed:
        return _buildCompletedOverlay();
    }
  }

  Widget _buildIntroductionOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.visibility,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 30),
            const Text(
              '시선추적 검사',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '음성 안내에 따라 시선을 움직여 주세요',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F3DA3),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                '검사 시작',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceAlignmentOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _faceDetected ? Colors.green : Colors.red,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Icon(
                Icons.face,
                size: 100,
                color: _faceDetected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _faceDetected ? '얼굴이 인식되었습니다' : '얼굴을 화면에 맞춰 주세요',
              style: TextStyle(
                fontSize: 20,
                color: _faceDetected ? Colors.green : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGazeTestOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '세트 ${_currentSet + 1}/$_totalSets',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
          _buildGazeIndicator(),
          const SizedBox(height: 50),
          Text(
            _getStepInstruction(),
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGazeIndicator() {
    final isCenter = _currentStep == 0 || _currentStep == 2 || _currentStep == 4;
    final isUp = _currentStep == 1;
    final isDown = _currentStep == 3;

    return SizedBox(
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 위 방향 표시
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isUp ? Colors.blue : Colors.grey.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 30),
          ),

          // 중앙 표시
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isCenter ? Colors.green : Colors.grey.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.circle, color: Colors.white, size: 20),
          ),

          // 아래 방향 표시
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isDown ? Colors.red : Colors.grey.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  String _getStepInstruction() {
    switch (_currentStep) {
      case 0:
      case 2:
      case 4:
        return '화면 중앙을 보세요';
      case 1:
        return '위를 보세요';
      case 3:
        return '아래를 보세요';
      default:
        return '';
    }
  }

  Widget _buildCompletedOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 100,
              color: Colors.green,
            ),
            SizedBox(height: 30),
            Text(
              '검사 완료',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20),
            Text(
              '결과를 분석하고 있습니다...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
            SizedBox(height: 30),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2F3DA3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusInfo() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session: ${_sessionId?.substring(0, 8)}...',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            'Face: ${_faceDetected ? 'Detected' : 'Not Found'}',
            style: TextStyle(
              color: _faceDetected ? Colors.green : Colors.red,
              fontSize: 12,
            ),
          ),
          Text(
            'Frames: ${_frameAnalyses.length}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _analysisTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector.close();
    _flutterTts.stop();
    super.dispose();
  }
}

enum TestPhase {
  introduction,
  faceAlignment,
  gazeTest,
  completed,
}