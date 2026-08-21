import 'package:flutter/material.dart';
import '../painters/face_guide_painter.dart';

/// [CameraSetupScreen]의 프레젠테이션 위젯들. 순수 표시용이며, 상태는 전부 생성자로 받는다.

/// 펄스 애니메이션을 타는 얼굴 가이드 오버레이.
class CameraGuideOverlay extends StatelessWidget {
  final Animation<double> pulseAnimation;

  const CameraGuideOverlay({Key? key, required this.pulseAnimation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: FaceGuidePainter(
            scale: pulseAnimation.value,
            isCorrect: false, // 검출 없이 가이드만
          ),
        );
      },
    );
  }
}

/// 상태 메시지 패널.
class CameraStatusPanel extends StatelessWidget {
  final bool canStart;
  final String statusMessage;
  final Color statusColor;

  const CameraStatusPanel({
    Key? key,
    required this.canStart,
    required this.statusMessage,
    required this.statusColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            statusMessage,
            style: TextStyle(
              color: statusColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (!canStart)
            const Text(
              '잠시만요...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }
}

/// 하단의 "검사 시작" / "테스트 완료" 버튼.
class CameraBottomButton extends StatelessWidget {
  final bool canStart;
  final bool testStarted;
  final VoidCallback onPressed;

  const CameraBottomButton({
    Key? key,
    required this.canStart,
    required this.testStarted,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final label = testStarted ? '테스트 완료' : (canStart ? '검사 시작' : '준비 중...');
    final enabled = testStarted || canStart;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? Colors.green : Colors.grey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// 위/아래 방향 안내 인디케이터.
class CameraDirectionIndicator extends StatelessWidget {
  final String currentDirection;
  final Color feedbackColor;

  const CameraDirectionIndicator({
    Key? key,
    required this.currentDirection,
    required this.feedbackColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: currentDirection == '위' ? 150 : null,
      bottom: currentDirection == '아래' ? 150 : null,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: feedbackColor.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Icon(
            currentDirection == '위'
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: 50,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
