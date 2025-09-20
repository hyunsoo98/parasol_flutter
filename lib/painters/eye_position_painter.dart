// lib/painters/eye_position_painter.dart
import 'package:flutter/material.dart';

class EyePositionPainter extends CustomPainter {
  EyePositionPainter(this.irisX, this.irisY, this.confidence, this.faceDetected);

  final double irisX;        // 0.0 ~ 1.0 (정규화 좌표라고 가정)
  final double irisY;        // 0.0 ~ 1.0
  final double confidence;   // 0.0 ~ 1.0
  final bool faceDetected;

  @override
  void paint(Canvas canvas, Size size) {
    // 좌표를 캔버스 크기에 매핑
    final dx = (irisX.clamp(0.0, 1.0)) * size.width;
    final dy = (irisY.clamp(0.0, 1.0)) * size.height;
    final center = Offset(dx, dy);

    // 신뢰도/탐지 여부에 따라 색상
    final active = faceDetected && confidence >= 0.5;
    final color = active ? Colors.green : Colors.grey.withOpacity(0.5);

    // 포인트(동공 위치) 표시
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, 6, fill);      // 점
    canvas.drawCircle(center, 12, stroke);   // 바깥 원

    // 십자선(가이드)
    final cross = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - 10, center.dy),
        Offset(center.dx + 10, center.dy), cross);
    canvas.drawLine(Offset(center.dx, center.dy - 10),
        Offset(center.dx, center.dy + 10), cross);
  }

  @override
  bool shouldRepaint(covariant EyePositionPainter oldDelegate) {
    return irisX != oldDelegate.irisX ||
        irisY != oldDelegate.irisY ||
        confidence != oldDelegate.confidence ||
        faceDetected != oldDelegate.faceDetected;
  }
}
