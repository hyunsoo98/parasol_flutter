import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import '../services/permission_service.dart';
import '../services/api_service.dart';
import 'final_diagnosis_screen.dart';

class VoiceAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic>? fingerTappingResult;
  final bool isStandaloneTest; // 개별 검사 모드인지 여부
  
  const VoiceAnalysisScreen({
    Key? key,
    this.fingerTappingResult,
    this.isStandaloneTest = false,
  }) : super(key: key);

  @override
  State<VoiceAnalysisScreen> createState() => _VoiceAnalysisScreenState();
}

class _VoiceAnalysisScreenState extends State<VoiceAnalysisScreen> with TickerProviderStateMixin {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  
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
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    
    await _recorder!.openRecorder();
    await _player!.openPlayer();
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
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, const Color(0xFF2F3DA3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.mic,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 20),
                const Text(
                  '음성 분석 검사',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '"아" 소리를 15초간\n일정하고 안정적으로\n발성해 주세요',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '녹음 시간: ${_recordingDuration}초',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volume_up, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            '조용한 환경에서 진행해주세요',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startRecording,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '녹음 시작',
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

  Widget _buildRecordingUI() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 카운트다운 타이머
          CircularCountDownTimer(
            duration: _recordingDuration,
            initialDuration: 0,
            controller: _countDownController,
            width: MediaQuery.of(context).size.width / 2.5,
            height: MediaQuery.of(context).size.width / 2.5,
            ringColor: Colors.grey[700]!,
            fillColor: Colors.purple,
            backgroundColor: Colors.white,
            strokeWidth: 12.0,
            strokeCap: StrokeCap.round,
            textStyle: const TextStyle(
              fontSize: 48.0,
              color: Colors.purple,
              fontWeight: FontWeight.bold,
            ),
            textFormat: CountdownTextFormat.S,
            isReverse: true,
            isReverseAnimation: true,
            isTimerTextShown: true,
            autoStart: false,
            onComplete: _stopRecording,
          ),
          
          const SizedBox(height: 40),
          
          // 음성 레벨 시각화
          AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return Container(
                height: 100,
                child: _buildWaveform(),
              );
            },
          ),
          
          const SizedBox(height: 40),
          
          // 안내 메시지
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  '"아아아아아..."',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '일정한 음성으로 계속 발성해주세요',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    if (_audioLevels.isEmpty) {
      return Center(
        child: Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(20, (index) {
        final levelIndex = (_audioLevels.length - 20 + index).clamp(0, _audioLevels.length - 1);
        final level = _audioLevels.isNotEmpty ? _audioLevels[levelIndex] : 0.0;
        final height = (level * 80).clamp(4.0, 80.0);
        
        return Container(
          width: 4,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
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
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 주요 결과
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, const Color(0xFF2F3DA3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.analytics,
                          size: 60,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '음성 분석 결과',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _finalDiagnosis,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 질환별 유사도
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '질환별 유사도',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_diseaseScores != null) ..._buildDiseaseScores(),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 상세 분석
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '음성 특성 분석',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_analysisResult != null) ..._buildDetailedAnalysis(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 다음 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _proceedToEyeTracking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '시선 추적 검사로 이동',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDiseaseScores() {
    final diseases = ['HC', 'PD', 'PSP', 'MSA'];
    final colors = [Colors.green, Colors.orange, Colors.red, Colors.purple];
    
    return diseases.asMap().entries.map((entry) {
      final index = entry.key;
      final disease = entry.value;
      final score = _diseaseScores![disease] ?? 0.0;
      final color = colors[index];
      
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getDiseaseFullName(disease),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${(score * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: score,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ],
        ),
      );
    }).toList();
  }

  String _getDiseaseFullName(String code) {
    switch (code) {
      case 'HC':
        return '정상 (Healthy Control)';
      case 'PD':
        return '파킨슨병 (Parkinson\'s Disease)';
      case 'PSP':
        return '진행성핵상마비 (PSP)';
      case 'MSA':
        return '다계통위축증 (MSA)';
      default:
        return code;
    }
  }

  List<Widget> _buildDetailedAnalysis() {
    return [
      _buildAnalysisRow('평균 주파수', '${_analysisResult!['fundamental_frequency'].toStringAsFixed(1)} Hz'),
      _buildAnalysisRow('음성 안정성', '${(_analysisResult!['stability'] * 100).toInt()}%'),
      _buildAnalysisRow('진폭 변화', '${(_analysisResult!['amplitude_variation'] * 100).toInt()}%'),
      _buildAnalysisRow('음성 품질', '${(_analysisResult!['voice_quality'] * 100).toInt()}%'),
    ];
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/voice_recording_${DateTime.now().millisecondsSinceEpoch}.aac';
      
      await _recorder!.startRecorder(
        toFile: filePath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
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
      if (_recorder!.isRecording) {
        try {
          // FlutterSound는 실시간 레벨 측정을 지원하지 않으므로 더미 데이터 사용
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
      await _recorder!.stopRecorder();
      
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

  void _proceedToEyeTracking() {
    // 음성 분석 결과 확인
    final diseaseScores = _diseaseScores ?? {};
    final hcScore = diseaseScores['HC'] ?? 0.0;
    
    // 개별 검사 모드이거나 HC(정상) 점수가 높으면 바로 결과 화면으로
    if (widget.isStandaloneTest || hcScore > 0.6) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FinalDiagnosisScreen(
            fingerTappingResult: widget.fingerTappingResult,
            voiceAnalysisResult: _analysisResult,
            eyeTrackingResult: null,
          ),
        ),
      );
    } else {
      // PSP 의심되면 시선 추적으로 계속 진행
      _showNextStepDialog();
    }
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
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _waveController.dispose();
    super.dispose();
  }
}