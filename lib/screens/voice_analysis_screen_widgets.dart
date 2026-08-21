import 'package:flutter/material.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';

/// [VoiceAnalysisScreen]의 프레젠테이션 위젯들. 순수 표시용이며, 상태는 전부 생성자로 받는다.

/// 녹음 시작 전 준비 화면.
class VoiceAnalysisPreparationView extends StatelessWidget {
  final int recordingDuration;
  final VoidCallback onStartRecording;

  const VoiceAnalysisPreparationView({
    Key? key,
    required this.recordingDuration,
    required this.onStartRecording,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                            '녹음 시간: ${recordingDuration}초',
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
                    onPressed: onStartRecording,
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
}

/// 녹음 진행 중 화면 — 카운트다운 타이머 + 실시간 파형.
class VoiceAnalysisRecordingView extends StatelessWidget {
  final int recordingDuration;
  final CountDownController countDownController;
  final VoidCallback onRecordingComplete;
  final Animation<double> waveAnimation;
  final List<double> audioLevels;

  const VoiceAnalysisRecordingView({
    Key? key,
    required this.recordingDuration,
    required this.countDownController,
    required this.onRecordingComplete,
    required this.waveAnimation,
    required this.audioLevels,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 카운트다운 타이머
          CircularCountDownTimer(
            duration: recordingDuration,
            initialDuration: 0,
            controller: countDownController,
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
            onComplete: onRecordingComplete,
          ),

          const SizedBox(height: 40),

          // 음성 레벨 시각화
          AnimatedBuilder(
            animation: waveAnimation,
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
    if (audioLevels.isEmpty) {
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
        final levelIndex = (audioLevels.length - 20 + index).clamp(0, audioLevels.length - 1);
        final level = audioLevels.isNotEmpty ? audioLevels[levelIndex] : 0.0;
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
}

/// 분석 결과 화면 — 진단 요약, 질환별 유사도, 상세 음성 특성.
class VoiceAnalysisResultsView extends StatelessWidget {
  final String finalDiagnosis;
  final Map<String, double>? diseaseScores;
  final Map<String, dynamic>? analysisResult;
  final VoidCallback onProceedToFinalResults;

  const VoiceAnalysisResultsView({
    Key? key,
    required this.finalDiagnosis,
    required this.diseaseScores,
    required this.analysisResult,
    required this.onProceedToFinalResults,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                          finalDiagnosis,
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
                        if (diseaseScores != null) ..._buildDiseaseScores(),
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
                        if (analysisResult != null) ..._buildDetailedAnalysis(),
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
              onPressed: onProceedToFinalResults,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '최종 결과 확인',
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
      final score = diseaseScores![disease] ?? 0.0;
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
      _buildAnalysisRow('평균 주파수', '${analysisResult!['fundamental_frequency'].toStringAsFixed(1)} Hz'),
      _buildAnalysisRow('음성 안정성', '${(analysisResult!['stability'] * 100).toInt()}%'),
      _buildAnalysisRow('진폭 변화', '${(analysisResult!['amplitude_variation'] * 100).toInt()}%'),
      _buildAnalysisRow('음성 품질', '${(analysisResult!['voice_quality'] * 100).toInt()}%'),
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
}
