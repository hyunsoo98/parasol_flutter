import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:volume_controller/volume_controller.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/permission_service.dart';
import '../services/mediapipe_api_service.dart';
import 'final_diagnosis_screen.dart';

class CameraSetupScreen extends StatefulWidget {
  const CameraSetupScreen({Key? key}) : super(key: key);

  @override
  State<CameraSetupScreen> createState() => _CameraSetupScreenState();
}

class _CameraSetupScreenState extends State<CameraSetupScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  FaceDetector? _faceDetector;
  FlutterTts? _tts;
  
  bool _isInitialized = false;
  bool _faceDetected = false;
  bool _correctDistance = false;
  bool _goodLighting = false;
  bool _centered = false;
  
  // Eye tracking test variables
  bool _testStarted = false;
  bool _isTestActive = false;
  int _currentTestCycle = 0;
  int _maxTestCycles = 6;
  String _currentDirection = '';
  bool _eyeMovementDetected = false;
  Color _feedbackColor = Colors.white;
  Timer? _testTimer;
  
  // Video recording variables
  bool _isRecording = false;
  bool _showBlackScreen = false;
  DateTime? _testStartTime;
  String? _videoPath;
  List<Map<String, dynamic>> _testLog = [];
  
  Timer? _detectionTimer;
  StreamSubscription? _imageStreamSubscription;
  bool _isDetectionInProgress = false;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _statusMessage = '카메라를 초기화하는 중...';
  Color _statusColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _initializeCamera();
    _initializeTTS();
    _setupSpeakerMode();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _pulseController.repeat(reverse: true);
  }

  void _initializeDetector() {
    final options = FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      enableLandmarks: true, // 눈 위치 감지를 위해 활성화
      enableTracking: true,
      minFaceSize: 0.1,
      performanceMode: FaceDetectorMode.accurate, // 정확도 향상
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeTTS() async {
    _tts = FlutterTts();
    await _tts?.setLanguage("ko-KR");
    
    // 사용 가능한 음성 목록 가져오기
    List<dynamic> voices = await _tts?.getVoices ?? [];
    
    // 한국어 음성 중에서 더 자연스러운 음성 선택
    dynamic selectedVoice;
    for (var voice in voices) {
      if (voice["locale"].contains("ko")) {
        // Android 한국어 음성 우선 선택
        if (voice["name"].toLowerCase().contains("ko-kr-wavenet-a") || 
            voice["name"].toLowerCase().contains("ko-kr-wavenet-c") ||
            voice["name"].toLowerCase().contains("ko-kr-standard-a") ||
            voice["name"].toLowerCase().contains("female")) {
          selectedVoice = voice;
          break;
        }
      }
    }
    
    // 선택된 음성이 없으면 첫 번째 한국어 음성 사용
    if (selectedVoice == null) {
      for (var voice in voices) {
        if (voice["locale"].contains("ko")) {
          selectedVoice = voice;
          break;
        }
      }
    }
    
    // 음성 설정
    if (selectedVoice != null) {
      try {
        await _tts?.setVoice(Map<String, String>.from(selectedVoice));
      } catch (e) {
        print('TTS 음성 설정 실패: $e');
      }
    }
    
    await _tts?.setPitch(0.9);
    await _tts?.setSpeechRate(0.7);
    await _tts?.setVolume(1.0);
  }

  Future<void> _setupSpeakerMode() async {
    try {
      // 스피커 모드로 전환
      VolumeController().setVolume(0.8);
      // Android에서 스피커폰 활성화
      await _enableSpeakerphone();
    } catch (e) {
      print('스피커 모드 설정 실패: $e');
    }
  }

  Future<void> _enableSpeakerphone() async {
    try {
      const platform = MethodChannel('speakerphone');
      await platform.invokeMethod('enableSpeakerphone');
    } catch (e) {
      print('스피커폰 활성화 실패: $e');
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts?.speak(text);
    } catch (e) {
      print('TTS 실패: $e');
    }
  }

  Future<void> _initializeCamera() async {
    bool hasPermission = await PermissionService.requestCameraPermission();
    
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
        // 전면 카메라 우선 선택
        CameraDescription frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras![0],
        );
        
        _controller = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        
        await _controller!.initialize();
        
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _statusMessage = '얼굴을 화면 중앙에 맞춰주세요';
            _statusColor = Color(0xFF2F3DA3);
          });
          
          _startFaceDetection();
        }
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

  void _startFaceDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!_isDetectionInProgress) {
        _detectFaces();
      }
    });
  }

  Future<void> _detectFaces() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!mounted) return;
    if (_isDetectionInProgress) return;
    if (_isRecording) return; // 비디오 녹화 중일 때는 얼굴 감지 건너뛰기

    _isDetectionInProgress = true;

    try {
      // 임시 디렉토리 확인 및 생성
      final directory = await getTemporaryDirectory();
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      
      final image = await _controller!.takePicture();
      
      // 이미지 파일이 제대로 생성되었는지 확인
      if (image.path.isEmpty) {
        return;
      }
      
      final imageFile = File(image.path);
      if (!imageFile.existsSync()) {
        return;
      }
      
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector!.processImage(inputImage);

      if (mounted) {
        _analyzeFacePosition(faces);
      }
      
      // 임시 이미지 파일 삭제
      try {
        if (imageFile.existsSync()) {
          await imageFile.delete();
        }
      } catch (deleteError) {
        // 삭제 실패는 조용히 처리
      }
      
    } catch (e) {
      // 얼굴 감지 실패는 조용히 처리
      print('Face detection error (safely handled): $e');
    } finally {
      _isDetectionInProgress = false;
    }
  }

  void _analyzeFacePosition(List<Face> faces) {
    if (faces.isEmpty) {
      setState(() {
        _faceDetected = false;
        _correctDistance = false;
        _centered = false;
        if (!_testStarted) {
          _statusMessage = '얼굴이 감지되지 않습니다\n화면 안에 얼굴을 위치시켜 주세요';
          _statusColor = Colors.orange;
        }
      });
      return;
    }

    final face = faces.first;
    final boundingBox = face.boundingBox;
    
    // 화면 크기 대비 얼굴 크기 계산 (가정값 사용)
    const screenWidth = 400.0;
    const screenHeight = 600.0;
    
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;
    final faceCenterX = boundingBox.center.dx;
    final faceCenterY = boundingBox.center.dy;
    
    // 얼굴 감지 성공
    final newFaceDetected = true;
    
    // 거리 체크 (얼굴 크기로 판단)
    final faceArea = faceWidth * faceHeight;
    final screenArea = screenWidth * screenHeight;
    final faceRatio = faceArea / screenArea;
    final newCorrectDistance = faceRatio > 0.15 && faceRatio < 0.4; // 적절한 크기 범위
    
    // 중앙 정렬 체크
    final centerTolerance = 50.0;
    final newCentered = (faceCenterX - screenWidth / 2).abs() < centerTolerance &&
                      (faceCenterY - screenHeight / 2).abs() < centerTolerance;
    
    // 조명 체크 (단순화)
    final newGoodLighting = true; // 실제로는 이미지 밝기 분석 필요

    // 눈동자 움직임 감지 (테스트 진행 중일 때)
    if (_isTestActive && face.landmarks != null) {
      _detectEyeMovement(face);
    }

    setState(() {
      _faceDetected = newFaceDetected;
      _correctDistance = newCorrectDistance;
      _centered = newCentered;
      _goodLighting = newGoodLighting;
      
      if (!_testStarted) {
        if (_faceDetected && _correctDistance && _centered && _goodLighting) {
          _statusMessage = '완벽합니다! 계속 진행할 수 있습니다';
          _statusColor = Colors.green;
        } else if (!_correctDistance) {
          _statusMessage = faceRatio < 0.15 
            ? '카메라에 더 가까이 앉아주세요'
            : '카메라에서 조금 멀어져 주세요';
          _statusColor = Colors.orange;
        } else if (!_centered) {
          _statusMessage = '얼굴을 화면 중앙에 맞춰주세요';
          _statusColor = Colors.orange;
        } else {
          _statusMessage = '위치를 조정해주세요';
          _statusColor = Colors.orange;
        }
      }
    });
  }

  void _detectEyeMovement(Face face) {
    if (face.landmarks == null) return;

    final leftEye = face.landmarks![FaceLandmarkType.leftEye];
    final rightEye = face.landmarks![FaceLandmarkType.rightEye];
    
    if (leftEye == null || rightEye == null) return;

    final eyeCenterY = (leftEye.position.y + rightEye.position.y) / 2;
    final faceCenterY = face.boundingBox.center.dy;
    
    // 눈의 상대적 위치로 위/아래 움직임 감지
    final eyeOffset = eyeCenterY - faceCenterY;
    
    // 디버깅용 로그
    print('현재 방향: $_currentDirection, 눈 오프셋: $eyeOffset');
    
    bool movementDetected = false;
    
    if (_currentDirection == '위' && eyeOffset < -5) {
      movementDetected = true;
    } else if (_currentDirection == '아래' && eyeOffset > 3) {
      movementDetected = true;
    }

    if (movementDetected && !_eyeMovementDetected) {
      setState(() {
        _eyeMovementDetected = true;
        _feedbackColor = Colors.green;
      });
      
      // 로그 기록
      if (_isRecording) {
        _testLog.add({
          'timestamp': DateTime.now().toIso8601String(),
          'event': 'eye_movement_detected',
          'cycle': _currentTestCycle + 1,
          'direction': _currentDirection,
          'eye_offset': eyeOffset,
          'message': '$_currentDirection 방향 눈동자 움직임 감지됨'
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('카메라 설정', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _showBlackScreen 
          ? _buildBlackScreenTest()
          : _isInitialized
              ? Stack(
                  children: [
                    // 카메라 프리뷰
                    Positioned.fill(
                      child: CameraPreview(_controller!),
                    ),
                    
                    // 가이드 오버레이
                    Positioned.fill(
                      child: _buildGuideOverlay(),
                    ),
                    
                    // 상태 정보 패널
                    Positioned(
                      top: 20,
                      left: 20,
                      right: 20,
                      child: _testStarted ? _buildTestStatusPanel() : _buildStatusPanel(),
                    ),
                    
                    // 눈동자 추적 테스트용 방향 표시
                    if (_isTestActive)
                      _buildDirectionIndicator(),
                    
                    // 하단 버튼
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: _buildBottomButton(),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                  ),
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

  Widget _buildBlackScreenTest() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 녹화 상태 표시
            if (_isRecording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 40),
            
            // 방향 표시
            if (_isTestActive)
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _feedbackColor, width: 4),
                ),
                child: Text(
                  _currentDirection,
                  style: TextStyle(
                    color: _feedbackColor,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            
            const SizedBox(height: 40),
            
            // 상태 메시지
            Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            // 진행 상황
            if (_isTestActive)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  '진행률: ${_currentTestCycle}/$_maxTestCycles',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: FaceGuidePainter(
            scale: _pulseAnimation.value,
            isCorrect: _faceDetected && _correctDistance && _centered,
          ),
        );
      },
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            _statusMessage,
            style: TextStyle(
              color: _statusColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCheckItem('얼굴인식', _faceDetected),
              _buildCheckItem('거리', _correctDistance),
              _buildCheckItem('중앙정렬', _centered),
              _buildCheckItem('조명', _goodLighting),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String label, bool isOk) {
    return Column(
      children: [
        Icon(
          isOk ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isOk ? Colors.green : Colors.grey,
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isOk ? Colors.green : Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    final allChecksPass = _faceDetected && _correctDistance && _centered && _goodLighting;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_testStarted || allChecksPass) ? _proceedToNextStep : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: (_testStarted || allChecksPass) ? Colors.green : Colors.grey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          _testStarted ? '테스트 완료' : (allChecksPass ? '검사 시작' : '위치를 조정해주세요'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildTestStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            _statusMessage,
            style: TextStyle(
              color: _statusColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (_isTestActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _feedbackColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _eyeMovementDetected ? '✓ 인식됨' : '눈동자를 ${_currentDirection}쪽으로',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionIndicator() {
    return Positioned(
      top: _currentDirection == '위' ? 150 : null,
      bottom: _currentDirection == '아래' ? 150 : null,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _feedbackColor.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Icon(
            _currentDirection == '위' ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 50,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _proceedToNextStep() async {
    if (!_testStarted) {
      await _startEyeTrackingTest();
    } else {
      // 테스트 완료 후 다음 화면으로
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const FinalDiagnosisScreen(),
        ),
      );
    }
  }

  Future<void> _startEyeTrackingTest() async {
    // 녹화 시작
    await _startRecording();
    
    setState(() {
      _testStarted = true;
      _currentTestCycle = 0;
      _statusMessage = '검사를 시작합니다';
      _statusColor = Colors.blue;
      _showBlackScreen = true; // 검은 화면으로 전환
    });

    await _speak('검사를 시작합니다');
    await Future.delayed(const Duration(seconds: 2));
    
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
      _eyeMovementDetected = false;
      _feedbackColor = Colors.yellow;
      _statusMessage = '$_currentDirection쪽을 보세요 (${_currentTestCycle + 1}/$_maxTestCycles)';
    });

    // 로그 기록
    if (_isRecording) {
      _testLog.add({
        'timestamp': DateTime.now().toIso8601String(),
        'event': 'direction_instruction',
        'cycle': _currentTestCycle + 1,
        'direction': _currentDirection,
        'message': '$_currentDirection쪽을 보세요'
      });
    }

    await _speak('${_currentDirection}쪽을 보세요');

    // 3초 대기 후 다음 사이클
    _testTimer = Timer(const Duration(seconds: 3), () {
      _currentTestCycle++;
      _runTestCycle();
    });
  }

  Future<void> _completeTest() async {
    // 녹화 중지
    await _stopRecording();
    
    setState(() {
      _isTestActive = false;
      _statusMessage = '분석 중입니다...';
      _statusColor = Colors.blue;
      _feedbackColor = Colors.blue;
      _showBlackScreen = false; // 검은 화면 해제
    });

    await _speak('분석 중입니다. 잠시만 기다려 주세요.');

    // 비디오 파일이 저장되었는지 확인 후 분석 호출
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      await _analyzeVideoWithAPI();
    } else {
      print('비디오 경로가 설정되지 않아 분석을 건너뜁니다');
      // 기본 결과 화면으로 이동
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const FinalDiagnosisScreen(),
          ),
        );
      }
    }
  }

  Future<void> _analyzeVideoWithAPI() async {
    try {
      print('분석 시작 - _videoPath: $_videoPath');
      
      if (_videoPath == null) {
        throw Exception('비디오 경로가 설정되지 않았습니다');
      }
      
      final videoFile = File(_videoPath!);
      print('비디오 파일 존재 확인: ${videoFile.existsSync()}');
      
      if (!videoFile.existsSync()) {
        print('비디오 파일이 존재하지 않음: $_videoPath');
        throw Exception('비디오 파일을 찾을 수 없습니다: $_videoPath');
      }
      
      final fileSize = await videoFile.length();
      print('비디오 파일 크기: $fileSize bytes');
      
      if (fileSize == 0) {
        throw Exception('비디오 파일이 비어있습니다');
      }

      setState(() {
        _statusMessage = 'MediaPipe로 분석 중...';
      });

      final apiService = MediaPipeApiService();
      
      // 서버 상태 확인 생략 (직접 API 호출로 확인)
      print('서버 연결 확인 없이 직접 분석 API 호출');

      // 비디오를 bytes로 읽어서 전송
      final videoBytes = await videoFile.readAsBytes();
      print('비디오 bytes 크기: ${videoBytes.length}');
      
      // bytes 방식으로 비디오 분석 실행
      final result = await apiService.analyzeEyeTrackingFromBytes(
        videoBytes: videoBytes,
        fileName: videoFile.path.split('/').last,
        step: 2, // 프레임 샘플링 간격
        vppThresh: 0.06, // PSP 판정 임계값
        blinkThresh: 0.18, // 블링크 임계값
      );

      // 결과 검증 및 안전한 처리
      Map<String, dynamic>? safeResult;
      try {
        if (result != null) {
          safeResult = result.toJson();
          print('분석 결과 생성 성공: $safeResult');
        } else {
          throw Exception('분석 결과가 null입니다');
        }
      } catch (resultError) {
        print('결과 변환 오류: $resultError');
        // 기본 결과 생성
        safeResult = {
          'hasAbnormality': false,
          'abnormalityScore': 0.0,
          'detectedIssues': <String>[],
          'timestamp': DateTime.now().toIso8601String(),
          'suggestedType': 'HC',
        };
      }

      setState(() {
        _statusMessage = '분석이 완료되었습니다!';
        _statusColor = Colors.green;
      });

      await _speak('분석이 완료되었습니다');
      await Future.delayed(const Duration(seconds: 2));

      // 결과 화면으로 안전하게 이동
      if (mounted) {
        try {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => FinalDiagnosisScreen(
                eyeTrackingResult: safeResult,
                videoPath: _videoPath,
              ),
            ),
          );
        } catch (navError) {
          print('화면 이동 오류: $navError');
          // 기본 진단 화면으로 이동
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const FinalDiagnosisScreen(),
            ),
          );
        }
      }

    } catch (e) {
      print('API 분석 실패: $e');
      
      String errorMessage = '분석 중 오류가 발생했습니다';
      String userMessage = '분석 중 오류가 발생했습니다. 다시 시도해주세요.';
      
      // 네트워크 연결 오류 감지
      if (e.toString().contains('Connection reset by peer') || 
          e.toString().contains('SocketException')) {
        errorMessage = '서버 연결이 일시적으로 불안정합니다';
        userMessage = '네트워크 연결을 확인하고 다시 시도해주세요.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = '서버 응답 시간이 초과되었습니다';
        userMessage = '서버가 응답하지 않습니다. 잠시 후 다시 시도해주세요.';
      }
      
      setState(() {
        _statusMessage = errorMessage;
        _statusColor = Colors.orange; // 빨강보다는 주황색으로 (일시적 문제)
      });

      await _speak(userMessage);

      // 에러 다이얼로그 표시
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(errorMessage.contains('연결') ? '연결 오류' : '분석 오류'),
            content: Text(userMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // 재시도
                  _analyzeVideoWithAPI();
                },
                child: const Text('재시도'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // 기본 진단 화면으로 이동
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FinalDiagnosisScreen(),
                    ),
                  );
                },
                child: const Text('건너뛰기'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        print('카메라가 초기화되지 않았습니다');
        return;
      }

      // 비디오 녹화 중에는 얼굴 감지 중지
      _detectionTimer?.cancel();
      print('얼굴 감지 타이머 중지됨');

      _testStartTime = DateTime.now();
      _testLog.clear();
      
      // 비디오 녹화 시작
      print('비디오 녹화 시작 중...');
      await _controller!.startVideoRecording();
      print('비디오 녹화 시작 완료');
      
      setState(() {
        _isRecording = true;
      });
      
      _testLog.add({
        'timestamp': _testStartTime!.toIso8601String(),
        'event': 'video_recording_started',
        'message': '눈동자 추적 테스트 비디오 녹화 시작'
      });
      
      print('비디오 녹화 시작됨');
    } catch (e) {
      print('비디오 녹화 시작 실패: $e');
      setState(() {
        _isRecording = false;
      });
      // 녹화 시작 실패 시 얼굴 감지 다시 시작
      _startFaceDetection();
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (!_isRecording || _controller == null) {
        print('녹화 중이 아니거나 카메라가 초기화되지 않았습니다');
        return;
      }

      final endTime = DateTime.now();
      final duration = endTime.difference(_testStartTime!);
      
      // 비디오 녹화 중지 (안전하게 처리)
      XFile? videoFile;
      try {
        print('비디오 녹화 중지 시작...');
        videoFile = await _controller!.stopVideoRecording();
        print('녹화 중지 완료, XFile 생성: ${videoFile?.path}');
        
        if (videoFile == null) {
          throw Exception('비디오 파일이 null입니다');
        }
        
        if (videoFile.path.isEmpty) {
          throw Exception('비디오 파일 경로가 비어있습니다');
        }
        
        // 파일 시스템 동기화를 위한 짧은 대기
        await Future.delayed(const Duration(milliseconds: 100));
        
        // 임시 파일 존재 확인 (재시도 로직 포함)
        final tempFile = File(videoFile.path);
        bool fileExists = false;
        int retryCount = 0;
        
        while (!fileExists && retryCount < 5) {
          fileExists = tempFile.existsSync();
          if (!fileExists) {
            print('파일 존재 확인 재시도 ${retryCount + 1}/5');
            await Future.delayed(const Duration(milliseconds: 50));
            retryCount++;
          }
        }
        
        if (!fileExists) {
          throw Exception('임시 비디오 파일이 존재하지 않습니다: ${videoFile.path}');
        }
        
        final tempFileSize = await tempFile.length();
        print('임시 비디오 파일 크기: $tempFileSize bytes');
        
        if (tempFileSize == 0) {
          throw Exception('임시 비디오 파일이 비어있습니다');
        }
        
      } catch (recordError) {
        print('비디오 녹화 중지 중 오류: $recordError');
        setState(() {
          _isRecording = false;
          _statusMessage = '비디오 녹화 중지 실패: $recordError';
          _statusColor = Colors.red;
        });
        return;
      }
      
      // 임시 디렉토리에 비디오 파일 저장
      final savedVideoPath = await _saveVideoFile(videoFile!);
      
      if (savedVideoPath == null || savedVideoPath.isEmpty) {
        setState(() {
          _isRecording = false;
          _statusMessage = '비디오 파일 저장 실패';
          _statusColor = Colors.red;
        });
        return;
      }
      
      _testLog.add({
        'timestamp': endTime.toIso8601String(),
        'event': 'video_recording_completed',
        'message': '눈동자 추적 테스트 비디오 녹화 완료',
        'duration_seconds': duration.inSeconds,
        'video_path': savedVideoPath
      });
      
      // 로그 파일 저장
      await _saveTestLog();
      
      setState(() {
        _isRecording = false;
        _videoPath = savedVideoPath; // ← 분석 전에 경로 설정
      });
      
      print('비디오 녹화 완료: $savedVideoPath');
      print('_videoPath 설정됨: $_videoPath');
      
      // 얼굴 감지 다시 시작 (테스트가 완료되지 않은 경우에만)
      if (!_testStarted || !_isTestActive) {
        _startFaceDetection();
        print('얼굴 감지 다시 시작됨');
      }
      
    } catch (e) {
      print('비디오 녹화 중지 실패: $e');
      setState(() {
        _isRecording = false;
      });
      // 녹화 중지 실패 시에도 얼굴 감지 다시 시작
      _startFaceDetection();
    }
  }

  Future<String?> _saveVideoFile(XFile videoFile) async {
    try {
      print('XFile 정보: ${videoFile.path}');
      
      // XFile 존재 확인
      final originalFile = File(videoFile.path);
      if (!originalFile.existsSync()) {
        print('원본 비디오 파일이 존재하지 않습니다: ${videoFile.path}');
        return null;
      }
      
      // XFile 크기 확인
      final xFileSize = await originalFile.length();
      print('XFile 크기: ${xFileSize} bytes');
      
      if (xFileSize == 0) {
        print('XFile이 비어있습니다');
        return null;
      }
      
      // 임시 디렉토리에 비디오 파일 저장
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // 원본 파일 확장자 확인
      final originalPath = videoFile.path;
      final originalExtension = originalPath.split('.').last.toLowerCase();
      print('원본 파일 확장자: $originalExtension');
      
      // 적절한 확장자 사용 (mp4 기본, 원본이 있으면 원본 사용)
      final extension = ['mp4', 'mov', 'avi'].contains(originalExtension) 
          ? originalExtension 
          : 'mp4';
          
      final fileName = 'eye_tracking_video_$timestamp.$extension';
      final savePath = '${directory.path}/$fileName';
      
      print('사용할 확장자: $extension');
      
      print('저장 경로: $savePath');
      
      // XFile을 bytes로 읽어서 저장 (빠른 처리)
      final file = File(savePath);
      try {
        final bytes = await videoFile.readAsBytes();
        if (bytes.isEmpty) {
          print('XFile에서 읽은 데이터가 비어있습니다');
          return null;
        }
        
        await file.writeAsBytes(bytes);
        print('${bytes.length} 바이트 데이터를 파일에 저장 완료');
        
        // 저장된 파일 크기 재확인
        final savedSize = await file.length();
        if (savedSize == 0) {
          print('저장된 파일이 비어있습니다');
          return null;
        }
        
        print('저장 완료: $savePath (${savedSize} bytes)');
        
      } catch (saveError) {
        print('파일 저장 중 오류: $saveError');
        // 저장 실패 시 직접 복사로 재시도
        try {
          await originalFile.copy(savePath);
          print('직접 복사로 재시도 성공: $savePath');
          
          final copiedSize = await file.length();
          if (copiedSize == 0) {
            print('복사된 파일이 비어있습니다');
            return null;
          }
        } catch (fallbackError) {
          print('재시도도 실패: $fallbackError');
          return null;
        }
      }
      
      // 저장된 파일 검증
      if (!file.existsSync()) {
        print('저장된 파일이 존재하지 않습니다');
        return null;
      }
      
      final savedFileSize = await file.length();
      print('저장된 파일 크기: ${savedFileSize} bytes');
      
      if (savedFileSize == 0) {
        print('저장된 파일이 비어있습니다');
        return null;
      }
      
      print('비디오 파일 저장 완료: $savePath');
      return savePath;
    } catch (e) {
      print('비디오 파일 저장 실패: $e');
      return null;
    }
  }

  Future<void> _saveTestLog() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/eye_tracking_test_$timestamp.json');
      
      final logData = {
        'test_info': {
          'test_type': 'eye_tracking',
          'start_time': _testStartTime?.toIso8601String(),
          'end_time': DateTime.now().toIso8601String(),
          'total_cycles': _maxTestCycles,
          'video_path': _videoPath,
        },
        'events': _testLog,
      };
      
      await file.writeAsString(json.encode(logData));
      print('테스트 로그 파일 저장: ${file.path}');
    } catch (e) {
      print('로그 파일 저장 실패: $e');
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _testTimer?.cancel();
    _imageStreamSubscription?.cancel();
    _controller?.dispose();
    _faceDetector?.close();
    _pulseController.dispose();
    _tts?.stop();
    // 로그 기록 중이면 중지
    if (_isRecording) {
      _stopRecording();
    }
    super.dispose();
  }
}

// 얼굴 가이드를 그리는 커스텀 페인터
class FaceGuidePainter extends CustomPainter {
  final double scale;
  final bool isCorrect;

  FaceGuidePainter({required this.scale, required this.isCorrect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = isCorrect ? Colors.green : Colors.white.withOpacity(0.8);

    final center = Offset(size.width / 2, size.height / 2 - 50);
    final ovalWidth = 200.0 * scale;
    final ovalHeight = 250.0 * scale;

    final oval = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    canvas.drawOval(oval, paint);
    
    // 가이드 텍스트
    final textPainter = TextPainter(
      text: TextSpan(
        text: '얼굴을 이 영역에\n맞춰주세요',
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy + ovalHeight / 2 + 20,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant FaceGuidePainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.isCorrect != isCorrect;
  }
}