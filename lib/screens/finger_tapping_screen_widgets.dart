import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';

/// [FingerTappingScreen]의 프레젠테이션 위젯들. 순수 표시용이며, 상태는 전부 생성자로 받는다.

/// 검사 시작 전 준비 화면.
class FingerTappingPreparationView extends StatelessWidget {
  final bool fromEyeTest;
  final Map<String, dynamic>? eyeTestContext;
  final int testDuration;
  final VoidCallback onStartTest;

  const FingerTappingPreparationView({
    Key? key,
    required this.fromEyeTest,
    required this.eyeTestContext,
    required this.testDuration,
    required this.onStartTest,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.3), // 투명도 감소로 카메라 더 잘 보이게
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
                if (fromEyeTest && eyeTestContext != null) ...[
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
                          'PSP 위험도: ${(eyeTestContext?['psp_risk_from_eye'] ?? false) ? '높음' : '낮음'}',
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
                          Text('테스트 시간: 1초 → ${testDuration}초 (카운트업)',
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
                    onPressed: onStartTest,
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
}

/// 검사 진행 중 화면 — 카메라 프리뷰 + 카운트업 타이머 + 실시간 탭 카운트.
class FingerTappingTestingView extends StatelessWidget {
  final bool isInitialized;
  final CameraController? controller;
  final int testDuration;
  final CountDownController countDownController;
  final VoidCallback onCountdownComplete;
  final Animation<double> pulseAnimation;
  final int tapCount;
  final bool faceDetected;

  const FingerTappingTestingView({
    Key? key,
    required this.isInitialized,
    required this.controller,
    required this.testDuration,
    required this.countDownController,
    required this.onCountdownComplete,
    required this.pulseAnimation,
    required this.tapCount,
    required this.faceDetected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // 카메라 프리뷰 (전체 화면) - 항상 표시
          Positioned.fill(
            child: isInitialized && controller != null
                ? CameraPreview(controller!)
                : Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: Text(
                        '카메라 준비 중...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
          ),

          // 오버레이 UI (매우 투명하게 설정)
          Positioned.fill(
            child: Container(
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 상단 타이머 및 안내
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 카운트업 타이머 (1초부터 10초까지)
                        CircularCountDownTimer(
                          duration: testDuration,
                          initialDuration: 0,
                          controller: countDownController,
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
                          isReverse: false, // 카운트업으로 변경
                          isReverseAnimation: false, // 정방향 애니메이션
                          isTimerTextShown: true,
                          autoStart: false,
                          onComplete: onCountdownComplete,
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
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            AnimatedBuilder(
                              animation: pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: pulseAnimation.value,
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
                                        '$tapCount',
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
                                color: faceDetected ? Colors.green : Colors.red,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(
                                faceDetected ? Icons.videocam : Icons.videocam_off,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              faceDetected ? '인식 완료' : '인식 중',
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
}

/// 검사 결과 화면.
class FingerTappingResultsView extends StatelessWidget {
  final double? pdProbability;
  final String diagnosis;
  final Map<String, dynamic>? analysisResult;
  final VoidCallback onProceedToVoiceAnalysis;

  const FingerTappingResultsView({
    Key? key,
    required this.pdProbability,
    required this.diagnosis,
    required this.analysisResult,
    required this.onProceedToVoiceAnalysis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isPositive = (pdProbability ?? 0.0) > 0.6;
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
                        diagnosis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: resultColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      if (pdProbability != null)
                        Text(
                          'PD 확률: ${(pdProbability! * 100).toInt()}%',
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
                    onPressed: onProceedToVoiceAnalysis,
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
    if (analysisResult == null) return Container();

    return Column(
      children: [
        _buildResultRow('총 탭핑 횟수', '${analysisResult!['totalTaps']}회'),
        _buildResultRow('평균 간격', '${analysisResult!['averageInterval'].toStringAsFixed(2)}초'),
        _buildResultRow('리듬 일관성', '${(analysisResult!['rhythmConsistency'] * 100).toInt()}%'),
        _buildResultRow('속도', '${analysisResult!['tapsPerSecond'].toStringAsFixed(1)}회/초'),
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
}
