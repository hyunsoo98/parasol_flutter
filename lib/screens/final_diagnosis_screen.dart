import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'final_diagnosis_screen_widgets.dart';

class FinalDiagnosisScreen extends StatefulWidget {
  final Map<String, dynamic>? fingerTappingResult;
  final Map<String, dynamic>? voiceAnalysisResult;
  final Map<String, dynamic>? eyeTrackingResult;
  final String? videoPath; // 비디오 파일 경로 추가

  const FinalDiagnosisScreen({
    Key? key,
    this.fingerTappingResult,
    this.voiceAnalysisResult,
    this.eyeTrackingResult,
    this.videoPath, // 옵셔널 파라미터로 추가
  }) : super(key: key);

  @override
  State<FinalDiagnosisScreen> createState() => _FinalDiagnosisScreenState();
}

class _FinalDiagnosisScreenState extends State<FinalDiagnosisScreen> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  Map<String, double>? _finalScores;
  String _primaryDiagnosis = '';
  String _diagnosisExplanation = '';
  Color _diagnosisColor = Color(0xFF2F3DA3);
  List<String> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _calculateFinalDiagnosis();
    _sendResultsToAPI();
  }

  void _setupAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    // 애니메이션 시작
    Future.delayed(const Duration(milliseconds: 500), () {
      _slideController.forward();
      _fadeController.forward();
    });
  }

  void _calculateFinalDiagnosis() {
    // 각 테스트별 가중치
    const double fingerTappingWeight = 0.4; // PD 진단에 중요
    const double voiceWeight = 0.3; // 다양한 질환 구분에 유용
    const double eyeTrackingWeight = 0.3; // PSP 구분에 중요

    // 기본 점수 초기화
    double hcScore = 0.0;
    double pdScore = 0.0;
    double pspScore = 0.0;
    double msaScore = 0.0;

    // Finger Tapping 결과 반영
    if (widget.fingerTappingResult != null) {
      final pdProbability = widget.fingerTappingResult!['pd_probability'] ?? 0.0;
      pdScore += pdProbability * fingerTappingWeight;
      hcScore += (1.0 - pdProbability) * fingerTappingWeight;
    }

    // Voice Analysis 결과 반영
    if (widget.voiceAnalysisResult != null) {
      // 음성 분석에서는 질환별 점수를 직접 사용
      final voiceData = widget.voiceAnalysisResult!;
      if (voiceData.containsKey('disease_scores')) {
        final diseaseScores = voiceData['disease_scores'] as Map<String, dynamic>?;
        if (diseaseScores != null) {
          hcScore += (diseaseScores['HC'] ?? 0.0) * voiceWeight;
          pdScore += (diseaseScores['PD'] ?? 0.0) * voiceWeight;
          pspScore += (diseaseScores['PSP'] ?? 0.0) * voiceWeight;
          msaScore += (diseaseScores['MSA'] ?? 0.0) * voiceWeight;
        }
      }
    } else {
      // 음성 분석이 없는 경우 HC에 가중치 부여 (첫 단계에서 정상으로 판단됨)
      hcScore += voiceWeight * 0.8;
    }

    // Eye Tracking 결과 반영 (PSP 특화)
    if (widget.eyeTrackingResult != null) {
      final pspProbability = widget.eyeTrackingResult!['psp_probability'] ?? 0.0;
      pspScore += pspProbability * eyeTrackingWeight;
      
      // PSP가 아닐 경우 다른 질환들에 배분
      final nonPspScore = (1.0 - pspProbability) * eyeTrackingWeight;
      hcScore += nonPspScore * 0.5;
      pdScore += nonPspScore * 0.3;
      msaScore += nonPspScore * 0.2;
    } else {
      // 시선 추적이 없는 경우 (이전 단계에서 정상으로 판단됨)
      hcScore += eyeTrackingWeight * 0.7;
    }

    // 점수 정규화
    final totalScore = hcScore + pdScore + pspScore + msaScore;
    if (totalScore > 0) {
      hcScore = hcScore / totalScore;
      pdScore = pdScore / totalScore;
      pspScore = pspScore / totalScore;
      msaScore = msaScore / totalScore;
    }

    _finalScores = {
      'HC': hcScore,
      'PD': pdScore,
      'PSP': pspScore,
      'MSA': msaScore,
    };

    // 주요 진단 결정
    final maxScore = [hcScore, pdScore, pspScore, msaScore].reduce(math.max);
    
    if (maxScore == hcScore) {
      _primaryDiagnosis = '정상 (Healthy Control)';
      _diagnosisExplanation = '검사 결과 정상 범위 내의 운동 및 음성 기능을 보이고 있습니다.';
      _diagnosisColor = Colors.green;
      _recommendations = [
        '정기적인 건강 검진을 받으시기 바랍니다',
        '규칙적인 운동을 지속하세요',
        '균형잡힌 식단을 유지하세요',
      ];
    } else if (maxScore == pdScore) {
      _primaryDiagnosis = '파킨슨병 의심 (Parkinson\'s Disease)';
      _diagnosisExplanation = '운동 기능 검사에서 파킨슨병과 유사한 패턴이 감지되었습니다.';
      _diagnosisColor = Colors.orange;
      _recommendations = [
        '신경과 전문의 진료를 받으시기 바랍니다',
        '정확한 진단을 위한 추가 검사가 필요합니다',
        '규칙적인 운동을 통해 근력을 유지하세요',
        '처방약이 있다면 정확히 복용하세요',
      ];
    } else if (maxScore == pspScore) {
      _primaryDiagnosis = '진행성핵상마비 의심 (PSP)';
      _diagnosisExplanation = '시선 추적 검사에서 PSP와 일치하는 수직 시선 제한이 발견되었습니다.';
      _diagnosisColor = Colors.red;
      _recommendations = [
        '운동질환 전문의 진료를 시급히 받으시기 바랍니다',
        'PSP 확진을 위한 정밀 검사가 필요합니다',
        '낙상 예방에 특별히 주의하세요',
        '물리치료를 통한 균형 훈련을 받으세요',
      ];
    } else {
      _primaryDiagnosis = '다계통위축증 의심 (MSA)';
      _diagnosisExplanation = '다양한 신경계 기능에서 MSA와 유사한 패턴이 관찰되었습니다.';
      _diagnosisColor = Colors.purple;
      _recommendations = [
        '신경과 전문의 진료를 받으시기 바랍니다',
        '종합적인 신경계 검사가 필요합니다',
        '증상 관리를 위한 의료진과 상담하세요',
        '안전한 환경에서 생활하세요',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  DiagnosisHeader(
                    diagnosisColor: _diagnosisColor,
                    primaryDiagnosis: _primaryDiagnosis,
                    diagnosisExplanation: _diagnosisExplanation,
                  ),

                  const SizedBox(height: 32),

                  // 질환별 확률
                  DiseaseScoreChart(finalScores: _finalScores),

                  const SizedBox(height: 24),

                  // 검사별 상세 결과
                  DetailedTestResults(
                    fingerTappingResult: widget.fingerTappingResult,
                    voiceAnalysisResult: widget.voiceAnalysisResult,
                    eyeTrackingResult: widget.eyeTrackingResult,
                  ),

                  const SizedBox(height: 24),

                  // 권장사항
                  RecommendationsPanel(recommendations: _recommendations),

                  const SizedBox(height: 32),

                  // 버튼들
                  DiagnosisActionButtons(onShare: _shareResults, onGoHome: _goToHome),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendResultsToAPI() async {
    // API 구현 예정
  }

  void _shareResults() {
    // 결과 공유 기능 (현재는 스낵바로 대체)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('결과 공유 기능이 구현될 예정입니다.'),
      ),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
}