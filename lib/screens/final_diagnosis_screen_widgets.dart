import 'package:flutter/material.dart';

/// [FinalDiagnosisScreen]의 프레젠테이션 위젯들. 순수 표시용이며, 상태는 전부 생성자로 받는다.

/// 상단 진단 요약 헤더(아이콘 + 진단명 + 설명).
class DiagnosisHeader extends StatelessWidget {
  final Color diagnosisColor;
  final String primaryDiagnosis;
  final String diagnosisExplanation;

  const DiagnosisHeader({
    Key? key,
    required this.diagnosisColor,
    required this.primaryDiagnosis,
    required this.diagnosisExplanation,
  }) : super(key: key);

  IconData _getDiagnosisIcon() {
    if (primaryDiagnosis.contains('정상')) return Icons.check_circle;
    if (primaryDiagnosis.contains('파킨슨병')) return Icons.warning;
    if (primaryDiagnosis.contains('PSP')) return Icons.error;
    return Icons.help;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [diagnosisColor.withOpacity(0.8), diagnosisColor.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: diagnosisColor.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            _getDiagnosisIcon(),
            size: 80,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          const Text(
            '종합 진단 결과',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            primaryDiagnosis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            diagnosisExplanation,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 질환별 확률 막대그래프 카드. finalScores가 null이면 제목만 표시하고
/// 막대그래프는 생략한다 (원본 로직 그대로 - 카드 자체는 항상 렌더링됨).
class DiseaseScoreChart extends StatelessWidget {
  final Map<String, double>? finalScores;

  const DiseaseScoreChart({Key? key, required this.finalScores}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '질환별 확률 분석',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (finalScores != null) ..._buildScoreCharts(finalScores!),
        ],
      ),
    );
  }

  List<Widget> _buildScoreCharts(Map<String, double> finalScores) {
    final diseases = ['HC', 'PD', 'PSP', 'MSA'];
    final colors = [Colors.green, Colors.orange, Colors.red, Colors.purple];
    final fullNames = {
      'HC': '정상 (HC)',
      'PD': '파킨슨병 (PD)',
      'PSP': '진행성핵상마비 (PSP)',
      'MSA': '다계통위축증 (MSA)',
    };

    return diseases.asMap().entries.map((entry) {
      final index = entry.key;
      final disease = entry.value;
      final score = finalScores[disease] ?? 0.0;
      final color = colors[index];
      final fullName = fullNames[disease] ?? disease;

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fullName,
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
            const SizedBox(height: 8),
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: score,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

/// 검사별 상세 결과(손가락 탭핑/음성 분석/시선 추적) 카드 묶음.
class DetailedTestResults extends StatelessWidget {
  final Map<String, dynamic>? fingerTappingResult;
  final Map<String, dynamic>? voiceAnalysisResult;
  final Map<String, dynamic>? eyeTrackingResult;

  const DetailedTestResults({
    Key? key,
    required this.fingerTappingResult,
    required this.voiceAnalysisResult,
    required this.eyeTrackingResult,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTestResult(
          '손가락 움직임 검사',
          Icons.touch_app,
          Color(0xFF2F3DA3),
          fingerTappingResult != null
            ? _formatFingerTappingResult(fingerTappingResult!)
            : {'상태': '완료'},
        ),
        if (voiceAnalysisResult != null) ...[
          const SizedBox(height: 16),
          _buildTestResult(
            '음성 분석 검사',
            Icons.mic,
            Colors.purple,
            _formatVoiceAnalysisResult(voiceAnalysisResult!),
          ),
        ],
        if (eyeTrackingResult != null) ...[
          const SizedBox(height: 16),
          _buildTestResult(
            '시선 추적 검사',
            Icons.visibility,
            Colors.orange,
            _formatEyeTrackingResult(eyeTrackingResult!),
          ),
        ],
      ],
    );
  }

  Widget _buildTestResult(String title, IconData icon, Color color, Map<String, String> results) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...results.entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 14)),
                Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Map<String, String> _formatFingerTappingResult(Map<String, dynamic> result) {
    return {
      '총 탭핑 횟수': '${result['totalTaps'] ?? 0}회',
      '평균 간격': '${(result['averageInterval'] ?? 0.0).toStringAsFixed(2)}초',
      '리듬 일관성': '${((result['rhythmConsistency'] ?? 0.0) * 100).toInt()}%',
      '탭핑 속도': '${(result['tapsPerSecond'] ?? 0.0).toStringAsFixed(1)}회/초',
    };
  }

  Map<String, String> _formatVoiceAnalysisResult(Map<String, dynamic> result) {
    return {
      '기본 주파수': '${(result['fundamental_frequency'] ?? 0.0).toStringAsFixed(1)} Hz',
      '음성 안정성': '${((result['stability'] ?? 0.0) * 100).toInt()}%',
      '진폭 변화': '${((result['amplitude_variation'] ?? 0.0) * 100).toInt()}%',
      '음성 품질': '${((result['voice_quality'] ?? 0.0) * 100).toInt()}%',
    };
  }

  Map<String, String> _formatEyeTrackingResult(Map<String, dynamic> result) {
    return {
      '수직 시선 범위': '${(result['vertical_range'] ?? 0.0).toStringAsFixed(1)}px',
      '수평 시선 범위': '${(result['horizontal_range'] ?? 0.0).toStringAsFixed(1)}px',
      '시선 안정성': '${((result['gaze_stability'] ?? 0.0) * 100).toInt()}%',
      '수집된 데이터': '${result['total_gaze_points'] ?? 0}개',
    };
  }
}

/// 권장사항 목록 패널.
class RecommendationsPanel extends StatelessWidget {
  final List<String> recommendations;

  const RecommendationsPanel({Key? key, required this.recommendations}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF2F3DA3).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF2F3DA3).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: Color(0xFF2F3DA3)),
              const SizedBox(width: 8),
              Text(
                '권장사항',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F3DA3).withOpacity(0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recommendations.map((rec) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle,
                     color: Color(0xFF2F3DA3), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rec,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF2F3DA3).withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}

/// 하단 "결과 공유" / "홈으로" 버튼.
class DiagnosisActionButtons extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onGoHome;

  const DiagnosisActionButtons({Key? key, required this.onShare, required this.onGoHome}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onShare,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF2F3DA3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.share),
            label: const Text(
              '결과 공유하기',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onGoHome,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.home),
            label: const Text(
              '홈으로 돌아가기',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
