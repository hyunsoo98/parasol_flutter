import 'package:flutter/material.dart';

/// 카메라 설정 화면에서 "얼굴을 이 영역에 맞춰주세요" 타원 가이드를 그린다.
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

    final oval =
        Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);
    canvas.drawOval(oval, paint);

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
      Offset(center.dx - textPainter.width / 2,
          center.dy + ovalHeight / 2 + 20),
    );
  }

  @override
  bool shouldRepaint(covariant FaceGuidePainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.isCorrect != isCorrect;
  }
}
