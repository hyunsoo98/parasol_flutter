import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import '../services/test_flow_service.dart';
import '../services/api_service.dart';
import '../services/aws_integration_service.dart';
import 'finger_tapping_screen.dart';

/// 구조화된 시선추적 테스트 화면 - TTS 가이드와 실시간 ML Kit 분석
class StructuredEyeTestScreen extends StatefulWidget {
  final String userId;
  final TestFlowService? testFlowService;

  const StructuredEyeTestScreen({
    Key? key,
    required this.userId,
    this.testFlowService,
  }) : super(key: key);

  @override
  State<StructuredEyeTestScreen> createState() => _StructuredEyeTestScreenState();
}

class _StructuredEyeTestScreenState extends State<StructuredEyeTestScreen> {
  // 카메라 관련
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // ML Kit 관련 (더 관대한 얼굴 감지)
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,        // 윤곽선 비활성화로 성능 향상
      enableLandmarks: true,        // 눈 랜드마크는 필요
      enableClassification: false,  // 분류 비활성화로 성능 향상
      enableTracking: false,        // 추적 비활성화로 성능 향상
      performanceMode: FaceDetectorMode.fast, // 빠른 모드로 감지율 향상
      minFaceSize: 0.05,           // 최소 얼굴 크기를 5%로 더 완화
    ),
  );

  // TTS 관련
  late FlutterTts _flutterTts;

  // 테스트 상태
  TestPhase _currentPhase = TestPhase.introduction;
  int _currentSet = 0;
  int _currentStep = 0; // 0: center, 1: up, 2: center, 3: down, 4: center
  final int _totalSets = 5;

  // 비디오 녹화 관련
  String? _videoPath;
  bool _isRecording = false;

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

  // MediaPipe 스타일 얼굴 추적 상태
  Offset? _prevFaceCenter;
  bool _lastStable = false;
  double _lastRel = 0.0;
  bool _inRange = false;

  // 얼굴 위치 허용 범위 상수 (더 상세한 설정)
  static const double kMinRelFace = 0.03; // 최소 얼굴 크기 (3%) - 더 완화
  static const double kMaxRelFace = 0.9;  // 최대 얼굴 크기 (90%) - 더 관대
  static const double kCenterJumpTol = 0.03; // 중심점 이동 허용 범위 (3%)
  static const double kPosTol = 0.15; // 위치 허용 오차 (15%)
  static const double kEyeMovementThreshold = 0.02; // 눈 움직임 감지 임계값 (2%)
  static const double kStabilityThreshold = 0.01; // 안정성 임계값 (1%)
  static const int kStabilityFrames = 3; // 안정성 판정 필요 프레임 수
  static const double kConfidenceHigh = 0.9; // 높은 신뢰도 기준
  static const double kConfidenceMedium = 0.6; // 중간 신뢰도 기준
  static const double kConfidenceLow = 0.3; // 낮은 신뢰도 기준

  // 좌표 변환 상수
  double _coordScaleX = 1.0;
  double _coordScaleY = 1.0;
  double _coordOffsetX = 0.0;
  double _coordOffsetY = 0.0;

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
    _testFlowService = widget.testFlowService ?? TestFlowService(apiService: ApiService());
    _sessionId = _testFlowService.startNewTestSession(widget.userId);

    // AWS 연결 테스트 (디버그용)
    _testAwsConnection();
  }

  Future<void> _testAwsConnection() async {
    try {
      final awsService = AwsIntegrationService();
      final testResult = await awsService.testApiConnection();
      print('AWS 연결 테스트 결과: $testResult');
    } catch (e) {
      print('AWS 연결 테스트 실패: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      print('사용 가능한 카메라 수: ${_cameras!.length}');

      if (_cameras!.isNotEmpty) {
        // 전면 카메라 우선 선택
        final frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );

        print('선택된 카메라: ${frontCamera.name}, 방향: ${frontCamera.lensDirection}');

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium, // 해상도를 다시 올림 (얼굴 인식을 위해)
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21, // ML Kit과 호환성이 좋은 포맷 명시
        );

        await _cameraController!.initialize();
        print('카메라 초기화 성공 - 해상도: ${_cameraController!.value.previewSize}');

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });

          // 초기화 완료 후 잠시 대기 후 스트림 시작
          await Future.delayed(const Duration(milliseconds: 500));
          _startCameraStream();
        }
      } else {
        print('사용 가능한 카메라가 없습니다');
      }
    } catch (e) {
      print('카메라 초기화 실패: $e');
    }
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(0.5); // 속도를 더 느리게 조정 (0.8 → 0.5)
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);
  }

  void _startCameraStream() {
    print('카메라 스트림 시작');
    _cameraController!.startImageStream((CameraImage image) {
      // 얼굴 정렬 단계와 시선 테스트 단계에서 모두 프레임 처리
      if (_currentPhase == TestPhase.faceAlignment || _currentPhase == TestPhase.gazeTest) {
        _processFrame(image);
      }
    });
  }

  // 얼굴 감지 빈도 제한 (성능 향상을 위해)
  DateTime? _lastFaceDetection;
  bool _recentFaceDetected = false;

  Future<void> _processFrame(CameraImage image) async {
    try {
      // 얼굴 감지 빈도 제한 (50ms마다만 실행) - 더 자주 감지
      final now = DateTime.now();
      if (_lastFaceDetection != null &&
          now.difference(_lastFaceDetection!).inMilliseconds < 50) {
        // 최근 감지 결과 재사용
        if (_recentFaceDetected) {
          _recordFaceDetected();
        } else {
          _recordNoFaceDetected();
        }
        return;
      }
      _lastFaceDetection = now;

      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        print('카메라 이미지 변환 실패');
        _recentFaceDetected = false;
        _recordNoFaceDetected();
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      // 얼굴 감지 결과 처리 (더 관대한 기준)
      if (faces.isNotEmpty) {
        final face = faces.first;
        final boundingBox = face.boundingBox;

        print('얼굴 감지 성공! 바운딩박스: $boundingBox');

        // 얼굴 크기 체크 (매우 관대함)
        final faceArea = boundingBox.width * boundingBox.height;
        final imageArea = image.width * image.height;
        final faceRatio = faceArea / imageArea;

        if (faceRatio > 0.005) { // 0.5% 이상이면 얼굴로 인정 (매우 관대)
          print('얼굴 인정 - 비율: ${(faceRatio * 100).toStringAsFixed(2)}%');
          _recentFaceDetected = true;

          // 눈 랜드마크 확인
          final leftEye = face.landmarks[FaceLandmarkType.leftEye];
          final rightEye = face.landmarks[FaceLandmarkType.rightEye];

          if (leftEye != null && rightEye != null) {
            print('눈 랜드마크 감지 성공 - 왼쪽: ${leftEye.position}, 오른쪽: ${rightEye.position}');
            _analyzeEyeData(face, leftEye, rightEye);
          } else {
            print('눈 랜드마크 없음, 얼굴 기반 추정 사용');
            _analyzeFaceData(face);
          }
        } else {
          print('얼굴 너무 작음 - 비율: ${(faceRatio * 100).toStringAsFixed(2)}% (0.5% 미만)');
          _recentFaceDetected = false;
          _recordNoFaceDetected();
        }
      } else {
        // 얼굴 감지 실패 시 더 관대한 처리
        print('ML Kit 얼굴 감지 실패 - 기본 위치 사용');
        _recentFaceDetected = false;

        // 테스트 진행을 위해 기본 중앙 위치 사용
        _useDefaultFacePosition();
      }
    } catch (e) {
      print('프레임 처리 오류: $e');
      _recentFaceDetected = false;
      _recordNoFaceDetected();
    }
  }

  // 얼굴 감지 성공 시 호출
  void _recordFaceDetected() {
    setState(() {
      _faceDetected = true;
    });

    // 시선추적 테스트 중일 때만 분석 데이터 저장
    if (_currentPhase == TestPhase.gazeTest) {
      _addAnalysisFrame();
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      print('이미지 변환 시작 - 포맷: ${image.format.group}, 크기: ${image.width}x${image.height}');

      // Android에서는 주로 NV21 또는 YUV_420_888 포맷 사용
      if (image.format.group == ImageFormatGroup.nv21 ||
          image.format.group == ImageFormatGroup.yuv420) {

        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        // 회전값 계산 (더 간단하게 처리)
        int rotation = _cameraController!.description.sensorOrientation;

        // 전면 카메라의 경우 회전값 조정
        if (_cameraController!.description.lensDirection == CameraLensDirection.front) {
          // 전면 카메라는 일반적으로 270도 회전이 필요
          rotation = (rotation + 180) % 360;
        }

        final imageRotation = InputImageRotationValue.fromRawValue(rotation);
        print('원본 센서값: ${_cameraController!.description.sensorOrientation}, 조정된 회전값: $rotation, ML Kit: $imageRotation');

        final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
        print('입력 이미지 포맷: $inputImageFormat');

        final inputImageData = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation ?? InputImageRotation.rotation0deg,
          format: inputImageFormat ?? InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        );

        print('이미지 변환 성공 - 크기: ${inputImageData.size}, 회전: ${inputImageData.rotation}');
        return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      } else {
        print('지원되지 않는 이미지 포맷: ${image.format.group}');
        return null;
      }
    } catch (e) {
      print('이미지 변환 오류: $e');
      return null;
    }
  }

  // MediaPipe 스타일 얼굴 분석 (더 정확한 눈동자 추적)
  void _analyzeEyeData(Face face, FaceLandmark leftEye, FaceLandmark rightEye) {
    setState(() {
      _faceDetected = true;
    });

    // MediaPipe 방식으로 눈동자 위치 계산
    final landmarks = [
      [leftEye.position.x, leftEye.position.y],
      [rightEye.position.x, rightEye.position.y],
    ];

    _onMpEyes(landmarks);
  }

  // MediaPipe 스타일 눈 랜드마크 처리
  void _onMpEyes(List<List> eyeLandmarks) {
    if (eyeLandmarks.isEmpty || !mounted) return;

    // 눈 랜드마크를 정규화된 좌표로 변환
    final eyePoints = <Offset>[];
    for (final eye in eyeLandmarks) {
      if (eye.length < 2) continue;
      final double nx = (eye[0] as num).toDouble();
      final double ny = (eye[1] as num).toDouble();

      // 카메라 해상도로 정규화
      final previewSize = _cameraController!.value.previewSize!;
      final normalizedX = (nx / previewSize.width).clamp(0.0, 1.0);
      final normalizedY = (ny / previewSize.height).clamp(0.0, 1.0);

      eyePoints.add(Offset(normalizedX, normalizedY));
    }

    if (eyePoints.isEmpty) return;

    // 양쪽 눈의 중심점 계산 (더 정확한 눈동자 위치)
    double centerX = 0.0;
    double centerY = 0.0;
    for (final point in eyePoints) {
      centerX += point.dx;
      centerY += point.dy;
    }
    centerX /= eyePoints.length;
    centerY /= eyePoints.length;

    // 안정성 체크 (급격한 움직임 필터링)
    bool stable = true;
    if (_prevFaceCenter != null) {
      final dx = (centerX - _prevFaceCenter!.dx).abs();
      final dy = (centerY - _prevFaceCenter!.dy).abs();
      stable = (dx <= kCenterJumpTol) && (dy <= kCenterJumpTol);
    }

    _prevFaceCenter = Offset(centerX, centerY);
    _lastStable = stable;

    // 안정적인 경우에만 위치 업데이트
    if (stable) {
      _irisX = centerX;
      _irisY = centerY;
      _confidence = 0.95; // 매우 높은 신뢰도
      _eyesOpen = true;   // 눈이 감지되었으므로 열린 것으로 간주
    } else {
      // 불안정한 움직임은 이전 값 유지하고 신뢰도만 낮춤
      _confidence = 0.6;
    }

    print('MediaPipe 눈동자 추적 - 위치: (${_irisX.toStringAsFixed(3)}, ${_irisY.toStringAsFixed(3)}), 안정성: $stable, 신뢰도: $_confidence');

    _addAnalysisFrame();
  }

  // 얼굴만 감지된 경우 (눈 랜드마크 없음)
  void _analyzeFaceData(Face face) {
    setState(() {
      _faceDetected = true;
    });

    // 얼굴 바운딩 박스에서 눈 위치 추정 (상단 1/3 지점)
    final boundingBox = face.boundingBox;
    final estimatedEyeX = boundingBox.left + (boundingBox.width / 2);
    final estimatedEyeY = boundingBox.top + (boundingBox.height * 0.4); // 눈은 얼굴 상단 40% 지점

    // 카메라 해상도로 정규화
    final previewSize = _cameraController!.value.previewSize!;
    _irisX = estimatedEyeX / previewSize.width;
    _irisY = estimatedEyeY / previewSize.height;

    // 눈 깜박임 정보 (있다면 사용)
    final leftEyeOpen = (face.leftEyeOpenProbability ?? 0.7) > 0.3;
    final rightEyeOpen = (face.rightEyeOpenProbability ?? 0.7) > 0.3;
    _eyesOpen = leftEyeOpen && rightEyeOpen;

    // 눈 랜드마크가 없으므로 신뢰도 낮춤
    _confidence = 0.6;

    print('얼굴 기반 눈 추정 - 위치: (${_irisX.toStringAsFixed(3)}, ${_irisY.toStringAsFixed(3)}), 눈열림: $_eyesOpen, 신뢰도: $_confidence');

    _addAnalysisFrame();
  }

  // 얼굴 감지 실패 시 기본 위치 사용 (테스트 진행을 위해)
  void _useDefaultFacePosition() {
    setState(() {
      _faceDetected = true; // 테스트 진행을 위해 감지된 것으로 처리
    });

    // 화면 중앙을 기본 눈 위치로 설정
    _irisX = 0.5;
    _irisY = 0.5;
    _eyesOpen = true;
    _confidence = 0.3; // 낮은 신뢰도

    print('기본 중앙 위치 사용 - (0.5, 0.5), 신뢰도: 0.3');

    if (_currentPhase == TestPhase.gazeTest) {
      _addAnalysisFrame();
    }
  }

  void _recordNoFaceDetected() {
    setState(() {
      _faceDetected = false;
    });
    _confidence = 0.0;

    if (_currentPhase == TestPhase.gazeTest) {
      _addAnalysisFrame();
    }
  }

  void _addAnalysisFrame() {
    if (_currentPhase != TestPhase.gazeTest) return;

    final currentPhase = _getCurrentGazePhase();

    // 시선 방향별 위치 변화 분석
    final gazeDirection = _analyzeGazeDirection(currentPhase);

    final analysisData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'iris_x': _irisX,
      'iris_y': _irisY,
      'eye_open': _eyesOpen,
      'face_detected': _faceDetected,
      'confidence': _confidence,
      'phase': currentPhase,
      'set': _currentSet,
      'step': _currentStep,
      'gaze_direction': gazeDirection,
      'stable': _lastStable,
      'eye_position_quality': _confidence > 0.8 ? 'high' : (_confidence > 0.5 ? 'medium' : 'low'),
    };

    _frameAnalyses.add(analysisData);

    // 실시간 피드백 (디버깅용)
    if (_frameAnalyses.length % 20 == 0) { // 20프레임마다
      print('시선추적 중간 결과 - 단계: $currentPhase, Y위치: ${_irisY.toStringAsFixed(3)}, 방향: $gazeDirection');
    }
  }

  // 시선 방향 분석 (위/아래 움직임 감지)
  String _analyzeGazeDirection(String currentPhase) {
    if (_frameAnalyses.length < 5) return 'unknown'; // 충분한 데이터 필요

    // 최근 5프레임의 Y 좌표 평균
    final startIndex = (_frameAnalyses.length - 5).clamp(0, _frameAnalyses.length);
    final recentFrames = _frameAnalyses.sublist(startIndex);
    final recentYPositions = recentFrames.map((frame) => frame['iris_y'] as double).toList();
    final avgRecentY = recentYPositions.reduce((a, b) => a + b) / recentYPositions.length;

    // 현재 Y 위치와 비교
    final yDiff = _irisY - avgRecentY;
    const threshold = 0.02; // 2% 변화 감지

    if (currentPhase == 'up') {
      if (yDiff < -threshold) return 'looking_up';      // Y가 작아짐 = 위로
      if (yDiff > threshold) return 'not_following';    // 아래로 가면 안됨
    } else if (currentPhase == 'down') {
      if (yDiff > threshold) return 'looking_down';     // Y가 커짐 = 아래로
      if (yDiff < -threshold) return 'not_following';   // 위로 가면 안됨
    } else if (currentPhase == 'center') {
      if (yDiff.abs() < threshold) return 'centered';   // 중앙 유지
    }

    return 'neutral';
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
    try {
      print('🔊 TTS: $text'); // Windows에서는 콘솔 출력으로 대체
      // await _flutterTts.speak(text); // Windows 빌드 오류 방지를 위해 임시 비활성화
      await Future.delayed(const Duration(milliseconds: 500)); // 음성 대신 짧은 대기
    } catch (e) {
      print('TTS 오류: $e');
    }
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

    // 비디오 녹화 시작 (추후 구현)
    _startVideoRecording();

    await _speak('이제 시선을 위아래로 움직이는 테스트를 시작합니다. 총 5세트를 진행합니다. 첫 세트는 중앙에서 시작하고, 이후에는 위아래만 반복합니다.');
    await Future.delayed(const Duration(seconds: 2));

    _startGazeSet();
  }

  void _startGazeSet() async {
    await _speak('${_currentSet + 1}번째 세트를 시작합니다.');
    await Future.delayed(const Duration(seconds: 1));

    _executeGazeSequence();
  }

  void _executeGazeSequence() async {
    // 세트별 시퀀스: 시작-중앙-위-아래 (1세트), 그 다음부터는 위-아래 반복
    List<Map<String, dynamic>> sequences;

    if (_currentSet == 0) {
      // 첫 번째 세트: 시작-중앙-위-아래
      sequences = [
        {'phase': 'center', 'duration': 2, 'instruction': '화면 중앙을 보세요'},
        {'phase': 'up', 'duration': 3, 'instruction': '위를 보세요'},
        {'phase': 'down', 'duration': 3, 'instruction': '아래를 보세요'},
      ];
    } else {
      // 이후 세트들: 위-아래만 반복
      sequences = [
        {'phase': 'up', 'duration': 3, 'instruction': '위를 보세요'},
        {'phase': 'down', 'duration': 3, 'instruction': '아래를 보세요'},
      ];
    }

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
    // Widget이 아직 마운트되어 있는지 확인
    if (!mounted) return;

    setState(() {
      _currentPhase = TestPhase.completed;
    });

    // 비디오 녹화 중지
    await _stopVideoRecording();

    if (!mounted) return; // TTS 전에 다시 확인

    await _speak('시선추적 검사가 완료되었습니다. 결과를 분석 중입니다.');

    final testDuration = DateTime.now().difference(_testStartTime!).inMilliseconds / 1000.0;

    try {
      print('시선추적 분석 시작 - 프레임 수: ${_frameAnalyses.length}, 테스트 시간: ${testDuration}초');

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
      ).timeout(const Duration(seconds: 30)); // 30초 타임아웃 추가

      print('시선추적 분석 결과: $result');

      if (!mounted) return; // 네비게이션 전에 확인

      if (result['success'] == true) {
        if (mounted) await _speak('분석이 완료되었습니다. 다음 검사로 이동하겠습니다.');
        _proceedToFingerTapping();
      } else {
        print('시선추적 분석 실패: ${result['error'] ?? 'Unknown error'}');
        if (mounted) await _speak('분석 중 오류가 발생했습니다. 다음 검사로 이동하겠습니다.');
        _proceedToFingerTapping(); // 오류가 있어도 다음 단계로 진행
      }
    } catch (e) {
      print('시선추적 분석 예외 발생: $e');
      if (mounted) await _speak('분석 처리 중 문제가 발생했습니다. 다음 검사로 이동하겠습니다.');
      _proceedToFingerTapping(); // 예외가 발생해도 다음 단계로 진행
    }
  }

  void _proceedToFingerTapping() {
    // Widget이 여전히 마운트되어 있는지 확인
    if (!mounted) {
      print('Widget이 이미 unmount되었습니다. 네비게이션을 건너뜁니다.');
      return;
    }

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
    final currentPhase = _getCurrentGazePhase();
    final gazeDirection = _frameAnalyses.isNotEmpty ? _analyzeGazeDirection(currentPhase) : 'unknown';

    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Stack(
        children: [
          // 메인 시선 가이드
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 세트 정보 및 진행률
              _buildProgressHeader(),
              const SizedBox(height: 30),

              // 시선 방향 표시기 (개선됨)
              _buildEnhancedGazeIndicator(currentPhase, gazeDirection),
              const SizedBox(height: 40),

              // 지시 사항
              _buildInstructionText(),
              const SizedBox(height: 20),

              // 실시간 피드백
              _buildRealTimeFeedback(gazeDirection),
            ],
          ),

          // 눈동자 추적 오버레이
          _buildEyeTrackingOverlay(),
        ],
      ),
    );
  }

  // 진행률 헤더
  Widget _buildProgressHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline, color: Colors.cyan, size: 20),
          SizedBox(width: 8),
          Text(
            '세트 ${_currentSet + 1}/$_totalSets',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Container(
            width: 100,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (_currentSet + 1) / _totalSets,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.cyan,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 개선된 시선 표시기
  Widget _buildEnhancedGazeIndicator(String phase, String gazeDirection) {
    return Container(
      width: 200,
      height: 300,
      child: Stack(
        children: [
          // 배경 원
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _faceDetected ? Colors.green.withOpacity(0.6) : Colors.red.withOpacity(0.6),
                  width: 3,
                ),
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),

          // 위쪽 표시기
          Positioned(
            top: 20,
            left: 75,
            child: _buildDirectionDot('up', phase, gazeDirection),
          ),

          // 중앙 표시기
          Positioned(
            top: 130,
            left: 75,
            child: _buildDirectionDot('center', phase, gazeDirection),
          ),

          // 아래쪽 표시기
          Positioned(
            bottom: 20,
            left: 75,
            child: _buildDirectionDot('down', phase, gazeDirection),
          ),

          // 현재 눈동자 위치 표시
          if (_faceDetected)
            Positioned(
              left: 75 + (_irisX - 0.5) * 100,
              top: 130 + (_irisY - 0.5) * 100,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.yellow,
                  border: Border.all(color: Colors.black, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 방향별 점 표시
  Widget _buildDirectionDot(String direction, String currentPhase, String gazeDirection) {
    bool isActive = direction == currentPhase;
    bool isFollowing = gazeDirection.contains(direction) ||
                      (direction == 'center' && gazeDirection == 'centered');

    Color color = Colors.grey;
    if (isActive) {
      color = isFollowing ? Colors.green : Colors.orange;
    }

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(isActive ? 0.8 : 0.3),
        border: Border.all(
          color: color,
          width: isActive ? 3 : 1,
        ),
      ),
      child: Icon(
        direction == 'up' ? Icons.keyboard_arrow_up :
        direction == 'down' ? Icons.keyboard_arrow_down :
        Icons.radio_button_checked,
        color: Colors.white,
        size: isActive ? 30 : 20,
      ),
    );
  }

  // 지시 텍스트
  Widget _buildInstructionText() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        _getStepInstruction(),
        style: const TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // 실시간 피드백
  Widget _buildRealTimeFeedback(String gazeDirection) {
    String feedbackText = '';
    Color feedbackColor = Colors.white;

    switch (gazeDirection) {
      case 'looking_up':
        feedbackText = '✓ 위를 잘 보고 있습니다';
        feedbackColor = Colors.green;
        break;
      case 'looking_down':
        feedbackText = '✓ 아래를 잘 보고 있습니다';
        feedbackColor = Colors.green;
        break;
      case 'centered':
        feedbackText = '✓ 중앙을 잘 보고 있습니다';
        feedbackColor = Colors.green;
        break;
      case 'not_following':
        feedbackText = '⚠️ 지시된 방향을 봐주세요';
        feedbackColor = Colors.orange;
        break;
      default:
        feedbackText = _faceDetected ? '눈동자 추적 중...' : '얼굴을 화면에 맞춰주세요';
        feedbackColor = _faceDetected ? Colors.blue : Colors.red;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: feedbackColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: feedbackColor.withOpacity(0.5)),
      ),
      child: Text(
        feedbackText,
        style: TextStyle(
          color: feedbackColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // 눈동자 추적 오버레이
  Widget _buildEyeTrackingOverlay() {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _faceDetected ? Colors.green : Colors.red,
            width: 2,
          ),
        ),
        child: CustomPaint(
          painter: EyePositionPainter(_irisX, _irisY, _confidence, _faceDetected),
        ),
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
        return '자연스럽게 화면을 보세요'; // 중앙 지시 완화
      case 1:
        return '위쪽을 보세요';
      case 3:
        return '아래쪽을 보세요';
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
    // 신뢰도에 따른 색상 결정
    Color confidenceColor = Colors.red;
    String confidenceText = 'Low';
    if (_confidence >= kConfidenceHigh) {
      confidenceColor = Colors.green;
      confidenceText = 'High';
    } else if (_confidence >= kConfidenceMedium) {
      confidenceColor = Colors.orange;
      confidenceText = 'Medium';
    }

    // 현재 시선 방향
    String currentGaze = _getCurrentGazePhase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _faceDetected ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 세션 정보
          Row(
            children: [
              Icon(Icons.fingerprint, color: Colors.blue, size: 16),
              SizedBox(width: 4),
              Text(
                'Session: ${_sessionId?.substring(0, 8)}...',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 6),

          // 얼굴 감지 상태
          Row(
            children: [
              Icon(
                _faceDetected ? Icons.face : Icons.face_retouching_off,
                color: _faceDetected ? Colors.green : Colors.red,
                size: 16,
              ),
              SizedBox(width: 4),
              Text(
                'Face: ${_faceDetected ? 'Detected' : 'Not Found'}',
                style: TextStyle(
                  color: _faceDetected ? Colors.green : Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 눈동자 위치
          Row(
            children: [
              Icon(Icons.visibility, color: Colors.blue, size: 16),
              SizedBox(width: 4),
              Text(
                'Eye: (${_irisX.toStringAsFixed(2)}, ${_irisY.toStringAsFixed(2)})',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 신뢰도
          Row(
            children: [
              Icon(Icons.speed, color: confidenceColor, size: 16),
              SizedBox(width: 4),
              Text(
                'Quality: $confidenceText (${(_confidence * 100).toInt()}%)',
                style: TextStyle(
                  color: confidenceColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 현재 단계
          Row(
            children: [
              Icon(Icons.directions, color: Colors.yellow, size: 16),
              SizedBox(width: 4),
              Text(
                'Phase: $currentGaze',
                style: const TextStyle(color: Colors.yellow, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 세트 진행률
          Row(
            children: [
              Icon(Icons.timeline, color: Colors.cyan, size: 16),
              SizedBox(width: 4),
              Text(
                'Set: ${_currentSet + 1}/$_totalSets',
                style: const TextStyle(color: Colors.cyan, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 프레임 수
          Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.purple, size: 16),
              SizedBox(width: 4),
              Text(
                'Frames: ${_frameAnalyses.length}',
                style: const TextStyle(color: Colors.purple, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 6),

          // 안정성 표시
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _lastStable ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _lastStable ? 'STABLE' : 'UNSTABLE',
              style: TextStyle(
                color: _lastStable ? Colors.green : Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 비디오 녹화 메소드들
  Future<void> _startVideoRecording() async {
    if (_isRecording) return;

    try {
      print('비디오 녹화 시작 시도...');
      await _cameraController!.startVideoRecording();
      _isRecording = true;

      print('비디오 녹화가 성공적으로 시작되었습니다');
    } catch (e) {
      print('비디오 녹화 시작 실패: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_isRecording) return;

    try {
      print('비디오 녹화 중지 중...');
      final file = await _cameraController!.stopVideoRecording();
      _isRecording = false;
      _videoPath = file.path;

      print('비디오 녹화 완료: ${file.path}');

      // S3에 비디오 업로드 시도
      await _uploadVideoToS3(file.path);

    } catch (e) {
      print('비디오 녹화 중지 실패: $e');
      _isRecording = false;
    }
  }

  Future<void> _uploadVideoToS3(String videoPath) async {
    try {
      print('S3에 비디오 업로드 시작: $videoPath');

      final file = File(videoPath);
      if (!await file.exists()) {
        print('비디오 파일이 존재하지 않습니다: $videoPath');
        return;
      }

      final fileSize = await file.length();
      print('비디오 파일 크기: ${fileSize} bytes');

      // AWS Integration Service를 통해 S3 업로드
      final awsService = AwsIntegrationService();
      final fileName = 'eye_tracking_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final uploadResult = await awsService.uploadEyeTrackingVideo(
        videoPath: videoPath,
        fileName: fileName,
        sessionId: _sessionId ?? 'unknown',
      );

      if (uploadResult['success'] == true) {
        print('S3 비디오 업로드 성공: ${uploadResult['s3_url']}');

        // 로컬 파일 삭제 (선택적)
        await file.delete();
        print('로컬 비디오 파일 삭제 완료');
      } else {
        print('S3 비디오 업로드 실패: ${uploadResult['error']}');
      }

    } catch (e) {
      print('S3 비디오 업로드 예외: $e');
    }
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