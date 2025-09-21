import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import '../services/permission_service.dart';
import '../services/api_service.dart';
import '../services/test_flow_service.dart';
import 'voice_analysis_screen.dart';
import 'final_diagnosis_screen.dart';

class FingerTappingScreen extends StatefulWidget {
  final bool isStandaloneTest; // 개별 검사 모드인지 여부
  final TestFlowService? testFlowService; // 시선추적 연계 데이터

  const FingerTappingScreen({
    Key? key,
    this.isStandaloneTest = false,
    this.testFlowService,
  }) : super(key: key);

  @override
  State<FingerTappingScreen> createState() => _FingerTappingScreenState();
}

class _FingerTappingScreenState extends State<FingerTappingScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  
  // 테스트 상태
  bool _testStarted = false;
  bool _testCompleted = false;
  int _currentStep = 0; // 0: 준비, 1: 테스트 진행, 2: 완료
  bool _faceDetected = false; // 손가락/손 감지 상태
  
  // Tapping 데이터
  List<DateTime> _tapTimestamps = [];
  int _tapCount = 0;
  final int _testDuration = 15; // 15초
  Timer? _testTimer;
  
  // 분석 결과
  Map<String, dynamic>? _analysisResult;
  double? _pdProbability;
  String _diagnosis = '';

  // 시선추적 연계 데이터
  Map<String, dynamic>? _eyeTestContext;
  bool _fromEyeTest = false;

  // UI 컨트롤러
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  CountDownController _countDownController = CountDownController();

  @override
  void initState() {
    super.initState();

    // 시선추적 테스트에서 연계된 경우 컨텍스트 로드
    if (widget.testFlowService != null) {
      _eyeTestContext = widget.testFlowService!.getFingerTappingStartData();
      _fromEyeTest = _eyeTestContext != null;
    }
    _initializeCamera();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticOut,
    ));
  }

  Future<void> _initializeCamera() async {
    bool hasPermission = await PermissionService.requestCameraPermission();
    
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카메라 권한이 필요합니다.')),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // 전면 카메라 선택
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
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라 초기화 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('손가락 움직임 검사', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isInitialized
          ? Stack(
              children: [
                // 카메라 프리뷰
                Positioned.fill(
                  child: CameraPreview(_controller!),
                ),
                
                // 메인 컨텐츠
                Positioned.fill(
                  child: _buildMainContent(),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
    );
  }

  Widget _buildMainContent() {
    switch (_currentStep) {
      case 0:
        return _buildPreparationUI();
      case 1:
        return _buildTestingUI();
      case 2:
        return _buildResultsUI();
      default:
        return _buildPreparationUI();
    }
  }

  Widget _buildPreparationUI() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.touch_app,
                  size: 80,
                  color: Color(0xFF2F3DA3),
                ),
                const SizedBox(height: 20),
                const Text(
                  '손가락 움직임 검사',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                // 시선추적 연계 정보 표시
                if (_fromEyeTest && _eyeTestContext != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F3DA3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '이전 시선추적 검사 완료',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2F3DA3),
                          ),
                        ),
                        Text(
                          'PSP 위험도: ${(_eyeTestContext!['psp_risk_from_eye'] ?? false) ? '높음' : '낮음'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  '카메라 앞에서 검지와 엄지를\n빠르고 규칙적으로\n마주쳐 주세요',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFF2F3DA3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color(0xFF2F3DA3).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer, color: Color(0xFF2F3DA3), size: 20),
                          const SizedBox(width: 8),
                          Text('테스트 시간: ${_testDuration}초', 
                               style: TextStyle(fontSize: 16, color: Color(0xFF2F3DA3))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.videocam, color: Color(0xFF2F3DA3), size: 20),
                          const SizedBox(width: 8),
                          const Text('카메라로 손가락 움직임 자동 감지',
                                   style: TextStyle(fontSize: 16, color: Color(0xFF2F3DA3))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2F3DA3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '검사 시작',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestingUI() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // 카메라 프리뷰 (전체 화면)
          if (_isInitialized)
            Positioned.fill(
              child: CameraPreview(_controller!),
            ),

          // 오버레이 UI
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 상단 타이머 및 안내
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 카운트다운 타이머
                        CircularCountDownTimer(
                          duration: _testDuration,
                          initialDuration: 0,
                          controller: _countDownController,
                          width: 100,
                          height: 100,
                          ringColor: Colors.grey[300]!,
                          fillColor: Color(0xFF2F3DA3),
                          backgroundColor: Colors.white,
                          strokeWidth: 8.0,
                          strokeCap: StrokeCap.round,
                          textStyle: const TextStyle(
                            fontSize: 24.0,
                            color: Color(0xFF2F3DA3),
                            fontWeight: FontWeight.bold,
                          ),
                          textFormat: CountdownTextFormat.S,
                          isReverse: true,
                          isReverseAnimation: true,
                          isTimerTextShown: true,
                          autoStart: false,
                          onComplete: _completeTest,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '검지와 엄지 손가락을\n빠르고 규칙적으로 마주쳐 주세요',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 하단 결과 표시
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF2F3DA3),
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$_tapCount',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '감지된 탭핑',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _faceDetected ? Colors.green : Colors.red,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(
                                _faceDetected ? Icons.videocam : Icons.videocam_off,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _faceDetected ? '손가락 인식' : '손가락 찾는 중',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsUI() {
    final isPositive = (_pdProbability ?? 0.0) > 0.6;
    final resultColor = isPositive ? Colors.orange : Colors.green;
    final resultIcon = isPositive ? Icons.warning_amber : Icons.check_circle;
    
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  resultIcon,
                  size: 80,
                  color: resultColor,
                ),
                const SizedBox(height: 20),
                const Text(
                  '검사 결과',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                
                // 결과 요약
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: resultColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: resultColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _diagnosis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: resultColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      if (_pdProbability != null)
                        Text(
                          'PD 확률: ${(_pdProbability! * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 16,
                            color: resultColor,
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 상세 결과
                _buildDetailedResults(),
                
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _proceedToVoiceAnalysis,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2F3DA3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '음성 검사로 이동',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedResults() {
    if (_analysisResult == null) return Container();
    
    return Column(
      children: [
        _buildResultRow('총 탭핑 횟수', '${_analysisResult!['totalTaps']}회'),
        _buildResultRow('평균 간격', '${_analysisResult!['averageInterval'].toStringAsFixed(2)}초'),
        _buildResultRow('리듬 일관성', '${(_analysisResult!['rhythmConsistency'] * 100).toInt()}%'),
        _buildResultRow('속도', '${_analysisResult!['tapsPerSecond'].toStringAsFixed(1)}회/초'),
      ],
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2F3DA3),
            ),
          ),
        ],
      ),
    );
  }

  void _startTest() {
    setState(() {
      _currentStep = 1;
      _testStarted = true;
      _tapTimestamps.clear();
      _tapCount = 0;
    });

    _countDownController.start();

    // 카메라 스트림 시작하여 손가락 움직임 감지
    _startFingerDetection();

    // 15초 후 자동 완료
    _testTimer = Timer(Duration(seconds: _testDuration), () {
      if (mounted && !_testCompleted) {
        _completeTest();
      }
    });
  }

  void _startFingerDetection() {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.startImageStream((CameraImage image) {
        if (_testStarted && !_testCompleted) {
          _processFingerFrame(image);
        }
      });
    }
  }

  // 손가락 프레임 처리 (간단한 모션 감지)
  DateTime? _lastProcessTime;
  double _lastMotionValue = 0.0;
  int _motionThreshold = 50; // 모션 감지 임계값

  Future<void> _processFingerFrame(CameraImage image) async {
    try {
      final now = DateTime.now();

      // 프레임 처리 빈도 제한 (100ms마다)
      if (_lastProcessTime != null &&
          now.difference(_lastProcessTime!).inMilliseconds < 100) {
        return;
      }
      _lastProcessTime = now;

      // 간단한 모션 감지 (실제로는 더 복잡한 손가락 추적 필요)
      final motionValue = _calculateMotion(image);

      // 모션 변화가 임계값을 넘으면 탭핑으로 인식
      if ((motionValue - _lastMotionValue).abs() > _motionThreshold) {
        _recordFingerTap();
      }

      _lastMotionValue = motionValue;

      // 얼굴/손 감지 상태 업데이트 (UI용)
      setState(() {
        _faceDetected = motionValue > 30; // 임의의 기준
      });

    } catch (e) {
      print('손가락 감지 오류: $e');
    }
  }

  double _calculateMotion(CameraImage image) {
    // 간단한 모션 계산 (실제로는 MediaPipe나 ML Kit 사용 권장)
    try {
      final plane = image.planes[0];
      final bytes = plane.bytes;

      // 이미지 밝기 변화로 간단한 모션 감지
      double sum = 0;
      for (int i = 0; i < bytes.length; i += 10) { // 샘플링
        sum += bytes[i];
      }
      return sum / (bytes.length / 10);
    } catch (e) {
      return 0.0;
    }
  }

  void _recordFingerTap() {
    if (!_testStarted || _testCompleted) return;

    setState(() {
      _tapCount++;
      _tapTimestamps.add(DateTime.now());
    });

    // 탭 애니메이션
    _pulseController.forward().then((_) {
      _pulseController.reverse();
    });

    print('손가락 탭핑 감지: $_tapCount');
  }

  void _completeTest() {
    if (_testCompleted) return;

    setState(() {
      _testCompleted = true;
      _currentStep = 2;
    });

    // 카메라 스트림 정지
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }

    _testTimer?.cancel();
    _analyzeResults();
  }

  void _analyzeResults() {
    if (_tapTimestamps.length < 2) {
      setState(() {
        _analysisResult = {
          'totalTaps': _tapCount,
          'averageInterval': 0.0,
          'rhythmConsistency': 0.0,
          'tapsPerSecond': 0.0,
        };
        _pdProbability = 0.8; // 너무 적은 탭은 문제가 있을 수 있음
        _diagnosis = '탭핑 횟수가 부족합니다';
      });
      _submitResultsToServer();
      return;
    }
    
    // 간격 계산
    List<double> intervals = [];
    for (int i = 1; i < _tapTimestamps.length; i++) {
      double interval = _tapTimestamps[i].difference(_tapTimestamps[i-1]).inMilliseconds / 1000.0;
      intervals.add(interval);
    }
    
    double averageInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    double tapsPerSecond = _tapCount / _testDuration;
    
    // 리듬 일관성 계산 (표준편차 기반)
    double variance = intervals.map((x) => math.pow(x - averageInterval, 2)).reduce((a, b) => a + b) / intervals.length;
    double standardDeviation = math.sqrt(variance);
    double rhythmConsistency = math.max(0.0, 1.0 - (standardDeviation / averageInterval));
    
    // PD 확률 계산 (단순화된 모델)
    double pdProbability = 0.0;
    
    // 탭핑 속도가 느린 경우
    if (tapsPerSecond < 1.5) {
      pdProbability += 0.3;
    }
    
    // 리듬이 불규칙한 경우
    if (rhythmConsistency < 0.6) {
      pdProbability += 0.4;
    }
    
    // 총 탭핑 횟수가 적은 경우
    if (_tapCount < 15) {
      pdProbability += 0.2;
    }
    
    String diagnosis;
    if (pdProbability > 0.7) {
      diagnosis = 'PD 위험도 높음';
    } else if (pdProbability > 0.4) {
      diagnosis = 'PD 위험도 보통';
    } else {
      diagnosis = '정상 범위';
    }
    
    setState(() {
      _analysisResult = {
        'totalTaps': _tapCount,
        'averageInterval': averageInterval,
        'rhythmConsistency': rhythmConsistency,
        'tapsPerSecond': tapsPerSecond,
      };
      _pdProbability = math.min(1.0, pdProbability);
      _diagnosis = diagnosis;
    });

    // 서버로 결과 전송
    _submitResultsToServer();
  }

  Future<void> _submitResultsToServer() async {
    try {
      final fingerResults = {
        'tap_count': _tapCount,
        'duration': _testDuration,
        'analysis_result': _analysisResult,
        'pd_probability': _pdProbability,
        'diagnosis': _diagnosis,
        'timestamps': _tapTimestamps.map((t) => t.toIso8601String()).toList(),
        'test_completed_at': DateTime.now().toIso8601String(),
      };

      // 시선추적 연계 테스트인 경우
      if (widget.testFlowService != null && _fromEyeTest) {
        final result = await widget.testFlowService!.completeFingerTapping(
          fingerTappingData: fingerResults,
          additionalMetadata: {
            'platform': 'flutter',
            'test_type': 'finger_tapping_connected',
          },
        );

        if (result['success'] == true) {
          print('연계 테스트 완료: ${result['session_id']}');
          // 통합 분석 결과 요청
          final combinedAnalysis = await widget.testFlowService!.requestCombinedAnalysis();
          print('통합 분석 완료: $combinedAnalysis');
        } else {
          print('연계 테스트 전송 실패: ${result['error']}');
        }
      } else {
        // 독립 finger-tapping 테스트인 경우 - AWS 서버로 전송
        final apiService = ApiService();
        await apiService.predictFinger(fingerResults);
        print('독립 finger-tapping 테스트 완료 (AWS 처리)');
      }
    } catch (e) {
      print('결과 전송 실패: $e');
    }
  }

  void _proceedToVoiceAnalysis() {
    // 분석 결과에 관계없이 항상 음성 분석으로 진행
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VoiceAnalysisScreen(
          fingerTappingResult: _analysisResult,
          testFlowService: widget.testFlowService,
        ),
      ),
    );
  }
  
  void _showNextStepDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('추가 검사 필요'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '손가락 움직임 검사에서 파킨슨병 의심 소견이 발견되었습니다.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFF2F3DA3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '다음 단계:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('• 음성 분석 검사'),
                    const Text('• 시선 추적 검사'),
                    const SizedBox(height: 8),
                    const Text(
                      '정확한 진단을 위해 추가 검사를 진행합니다.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VoiceAnalysisScreen(
                      fingerTappingResult: _analysisResult,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2F3DA3),
                foregroundColor: Colors.white,
              ),
              child: const Text('다음 검사 진행'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    _controller?.dispose();
    _pulseController.dispose();
    super.dispose();
  }
}