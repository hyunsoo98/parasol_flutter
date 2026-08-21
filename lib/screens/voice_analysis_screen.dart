import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import '../services/permission_service.dart';
import '../services/api_service.dart';
import '../services/test_flow_service.dart';
import 'final_diagnosis_screen.dart';
import 'voice_analysis_screen_widgets.dart';

class VoiceAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic>? fingerTappingResult;
  final bool isStandaloneTest; // 개별 검사 모드인지 여부
  final TestFlowService? testFlowService;

  const VoiceAnalysisScreen({
    Key? key,
    this.fingerTappingResult,
    this.isStandaloneTest = false,
    this.testFlowService,
  }) : super(key: key);

  @override
  State<VoiceAnalysisScreen> createState() => _VoiceAnalysisScreenState();
}

class _VoiceAnalysisScreenState extends State<VoiceAnalysisScreen> with TickerProviderStateMixin {
  late AudioRecorder _recorder;
  bool _isRecorderInitialized = false;
  
  // 녹음 상태
  bool _isRecording = false;
  bool _recordingCompleted = false;
  String? _recordedFilePath;
  
  // 테스트 상태
  int _currentStep = 0; // 0: 준비, 1: 녹음 중, 2: 분석 중, 3: 결과
  final int _recordingDuration = 15; // 15초
  Timer? _recordingTimer;
  
  // 분석 결과
  Map<String, dynamic>? _analysisResult;
  Map<String, double>? _diseaseScores; // HC, PD, PSP, MSA 점수
  String _finalDiagnosis = '';
  
  // UI 컨트롤러
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;
  CountDownController _countDownController = CountDownController();
  
  // 오디오 분석
  List<double> _audioLevels = [];
  Timer? _levelTimer;

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
    _setupAnimations();
    _requestPermissions();
  }

  Future<void> _initializeRecorder() async {
    try {
      _recorder = AudioRecorder();
      _isRecorderInitialized = await _recorder.hasPermission();
      if (!_isRecorderInitialized) {
        _isRecorderInitialized = await _recorder.hasPermission();
      }
    } catch (e) {
      print('Failed to initialize recorder: $e');
      _isRecorderInitialized = false;
    }
  }

  void _setupAnimations() {
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _requestPermissions() async {
    await PermissionService.requestMicrophonePermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('음성 분석', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    switch (_currentStep) {
      case 0:
        return _buildPreparationUI();
      case 1:
        return _buildRecordingUI();
      case 2:
        return _buildAnalysisUI();
      case 3:
        return _buildResultsUI();
      default:
        return _buildPreparationUI();
    }
  }

  Widget _buildPreparationUI() {
    return VoiceAnalysisPreparationView(
      recordingDuration: _recordingDuration,
      onStartRecording: _startRecording,
    );
  }

  Widget _buildRecordingUI() {
    return VoiceAnalysisRecordingView(
      recordingDuration: _recordingDuration,
      countDownController: _countDownController,
      onRecordingComplete: _stopRecording,
      waveAnimation: _waveAnimation,
      audioLevels: _audioLevels,
    );
  }

  Widget _buildAnalysisUI() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Colors.purple,
            strokeWidth: 6,
          ),
          const SizedBox(height: 32),
          const Text(
            '음성 분석 중...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '음성 신호를 분석하여\nHC, PD, PSP, MSA 유사도를\n계산하고 있습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsUI() {
    return VoiceAnalysisResultsView(
      finalDiagnosis: _finalDiagnosis,
      diseaseScores: _diseaseScores,
      analysisResult: _analysisResult,
      onProceedToFinalResults: _proceedToFinalResults,
    );
  }

  Future<void> _startRecording() async {
    try {
      if (!_isRecorderInitialized) {
        // 권한 재요청
        bool hasPermission = await PermissionService.requestMicrophonePermission();
        if (!hasPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('마이크 권한이 필요합니다. 설정에서 권한을 허용해주세요.'),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }

        // 권한을 받았으면 다시 초기화
        await _initializeRecorder();
        if (!_isRecorderInitialized) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹음 기능을 사용할 수 없습니다.')),
          );
          return;
        }
      }

      String filePath;
      if (kIsWeb) {
        // 웹에서는 브라우저가 자동으로 처리
        filePath = 'voice_recording_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        final directory = await getTemporaryDirectory();
        filePath = '${directory.path}/voice_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: kIsWeb ? filePath : filePath,  // 웹과 모바일 모두 path 제공
      );

      setState(() {
        _currentStep = 1;
        _isRecording = true;
        _recordedFilePath = filePath;
        _audioLevels.clear();
      });

      _countDownController.start();
      _waveController.repeat();
      _startLevelMonitoring();

      // 15초 후 자동 중지
      _recordingTimer = Timer(Duration(seconds: _recordingDuration), () {
        _stopRecording();
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 시작 실패: $e')),
      );
    }
  }

  void _startLevelMonitoring() {
    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isRecording) {
        try {
          // 웹과 모바일 모두에서 시뮬레이션 데이터 사용
          setState(() {
            _audioLevels.add(0.5 + (math.Random().nextDouble() - 0.5) * 0.4);
            if (_audioLevels.length > 50) {
              _audioLevels.removeAt(0);
            }
          });
        } catch (e) {
          // 진폭 측정 실패는 조용히 처리
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _levelTimer?.cancel();
    _waveController.stop();

    try {
      final path = await _recorder.stop();
      if (path != null) {
        _recordedFilePath = path;
      }

      setState(() {
        _isRecording = false;
        _recordingCompleted = true;
        _currentStep = 2;
      });

      await _analyzeRecording();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('녹음 중지 실패: $e')),
      );
    }
  }

  Future<void> _analyzeRecording() async {
    if (_recordedFilePath == null) return;
    
    // 시뮬레이션된 음성 분석 (실제로는 음성 분석 라이브러리 또는 API 사용)
    await Future.delayed(const Duration(seconds: 3));
    
    // 음성 레벨 기반 간단한 분석
    final avgLevel = _audioLevels.isNotEmpty ? 
      _audioLevels.reduce((a, b) => a + b) / _audioLevels.length : 0.0;
    
    final levelVariation = _calculateVariation(_audioLevels);
    final stability = math.max(0.0, 1.0 - levelVariation);
    
    // 모의 분석 결과
    final analysisResult = {
      'fundamental_frequency': 150.0 + (math.Random().nextDouble() - 0.5) * 50,
      'stability': stability,
      'amplitude_variation': levelVariation,
      'voice_quality': avgLevel * 0.8 + stability * 0.2,
    };
    
    // 질환별 점수 계산 (모의)
    final hcScore = stability * 0.7 + (1.0 - levelVariation) * 0.3;
    final pdScore = levelVariation > 0.3 ? 0.6 : 0.2;
    final pspScore = avgLevel < 0.4 ? 0.4 : 0.1;
    final msaScore = levelVariation > 0.5 ? 0.3 : 0.1;
    
    final diseaseScores = {
      'HC': hcScore.clamp(0.0, 1.0),
      'PD': pdScore.clamp(0.0, 1.0),
      'PSP': pspScore.clamp(0.0, 1.0),
      'MSA': msaScore.clamp(0.0, 1.0),
    };
    
    // 최종 진단
    final maxScore = diseaseScores.values.reduce(math.max);
    final diagnosis = diseaseScores.entries.firstWhere((e) => e.value == maxScore).key;
    
    String finalDiagnosis;
    switch (diagnosis) {
      case 'HC':
        finalDiagnosis = '정상 음성 패턴입니다';
        break;
      case 'PD':
        finalDiagnosis = '파킨슨병 의심 패턴이 감지되었습니다';
        break;
      case 'PSP':
        finalDiagnosis = 'PSP 의심 패턴이 감지되었습니다';
        break;
      case 'MSA':
        finalDiagnosis = 'MSA 의심 패턴이 감지되었습니다';
        break;
      default:
        finalDiagnosis = '추가 검사가 필요합니다';
    }
    
    setState(() {
      _analysisResult = analysisResult;
      _diseaseScores = diseaseScores;
      _finalDiagnosis = finalDiagnosis;
      _currentStep = 3;
    });
    
    // API에 결과 전송
    await _sendResultsToAPI();
  }

  double _calculateVariation(List<double> data) {
    if (data.length < 2) return 0.0;
    
    final mean = data.reduce((a, b) => a + b) / data.length;
    final variance = data.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) / data.length;
    return math.sqrt(variance);
  }

  Future<void> _sendResultsToAPI() async {
    try {
      final apiService = ApiService();
      await apiService.predictSpeech({
        'analysis_result': _analysisResult,
        'disease_scores': _diseaseScores,
        'final_diagnosis': _finalDiagnosis,
        'audio_file_path': _recordedFilePath,
        'finger_tapping_result': widget.fingerTappingResult,
      });
    } catch (e) {
      print('API 전송 실패: $e');
    }
  }

  void _proceedToFinalResults() {
    // 분석 결과에 관계없이 항상 최종 결과 화면으로 이동
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => FinalDiagnosisScreen(
          fingerTappingResult: widget.fingerTappingResult,
          voiceAnalysisResult: _analysisResult,
          eyeTrackingResult: null, // 시선추적은 건너뛰거나 이미 완료된 상태
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
              Icon(Icons.info, color: Colors.purple),
              const SizedBox(width: 8),
              const Text('최종 검사 필요'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '음성 분석에서 추가 확인이 필요한 소견이 발견되었습니다.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '최종 단계:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('• 시선 추적 검사'),
                    const Text('• PSP(진행성핵상마비) 확인'),
                    const SizedBox(height: 8),
                    const Text(
                      '정확한 최종 진단을 위한 마지막 검사입니다.',
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
                    builder: (context) => FinalDiagnosisScreen(
                      fingerTappingResult: widget.fingerTappingResult,
                      voiceAnalysisResult: _analysisResult,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('최종 검사 진행'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _levelTimer?.cancel();
    _recorder.dispose();
    _waveController.dispose();
    super.dispose();
  }
}