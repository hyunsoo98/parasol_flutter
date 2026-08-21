import 'package:flutter/material.dart';
import '../painters/eye_position_painter.dart';
import '../painters/grid_painter.dart';

/// [StructuredEyeTestScreen]의 프레젠테이션 위젯들.
/// 전부 상태를 생성자로만 전달받는 순수 표시용 위젯이라 여기로 분리했다.

/// 시선 방향/인식 상태에 대한 실시간 텍스트 피드백.
class EyeTestRealTimeFeedback extends StatelessWidget {
  final bool faceDetected;
  final double confidence;
  final double currentSetMinY;
  final double currentSetMaxY;
  final List<double> gazeVelocities;
  final bool forceContinueMode;
  final double irisY;
  final int failedFramesCount;
  final String gazeDirection;

  const EyeTestRealTimeFeedback({
    Key? key,
    required this.faceDetected,
    required this.confidence,
    required this.currentSetMinY,
    required this.currentSetMaxY,
    required this.gazeVelocities,
    required this.forceContinueMode,
    required this.irisY,
    required this.failedFramesCount,
    required this.gazeDirection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String feedbackText = '';
    String detailText = '';
    Color feedbackColor = Colors.white;
    IconData feedbackIcon = Icons.info;

    // 인식 상태에 따른 기본 정보
    if (!faceDetected) {
      feedbackText = '얼굴을 화면에 맞춰주세요';
      detailText = '카메라에 얼굴이 잘 보이도록 조정해주세요';
      feedbackColor = Colors.red;
      feedbackIcon = Icons.face_retouching_off;
    } else if (confidence < 0.3) { // 시선 추적 실패 판정 기준 완화 (0.5→0.3)
      feedbackText = '인식이 불안정합니다';
      detailText = '조명을 확인하고 얼굴을 더 가까이 해주세요';
      feedbackColor = Colors.orange;
      feedbackIcon = Icons.visibility_off;
    } else {
      // 시선 방향에 따른 피드백
      final currentRange = currentSetMaxY - currentSetMinY;
      final avgVelocity = gazeVelocities.isNotEmpty ?
          gazeVelocities.reduce((a, b) => a + b) / gazeVelocities.length : 0.0;

      switch (gazeDirection) {
        case 'looking_up':
          feedbackText = '✓ 위쪽 시선 인식 중';
          detailText = 'Y위치: ${(irisY * 100).toInt()}% | 범위: ${(currentRange * 100).toInt()}% | 속도: ${(avgVelocity * 100).toStringAsFixed(1)}% | ${forceContinueMode ? "강제진행" : "정상"}';
          feedbackColor = Colors.green;
          feedbackIcon = Icons.keyboard_arrow_up;
          break;
        case 'looking_down':
          feedbackText = '✓ 아래쪽 시선 인식 중';
          detailText = 'Y위치: ${(irisY * 100).toInt()}% | 범위: ${(currentRange * 100).toInt()}% | 속도: ${(avgVelocity * 100).toStringAsFixed(1)}% | ${forceContinueMode ? "강제진행" : "정상"}';
          feedbackColor = Colors.green;
          feedbackIcon = Icons.keyboard_arrow_down;
          break;
        case 'centered':
          feedbackText = '✓ 중앙 시선 인식 중';
          detailText = 'Y위치: ${(irisY * 100).toInt()}% | 범위: ${(currentRange * 100).toInt()}% | 속도: ${(avgVelocity * 100).toStringAsFixed(1)}% | ${forceContinueMode ? "강제진행" : "정상"}';
          feedbackColor = Colors.green;
          feedbackIcon = Icons.center_focus_strong;
          break;
        case 'not_following':
          feedbackText = forceContinueMode ? '⚠️ 강제 진행 중' : '⚠️ 지시된 방향을 봐주세요';
          detailText = 'Y위치: ${(irisY * 100).toInt()}% | 범위: ${(currentRange * 100).toInt()}% | 실패: ${failedFramesCount}프레임';
          feedbackColor = Colors.orange;
          feedbackIcon = forceContinueMode ? Icons.fast_forward : Icons.my_location;
          break;
        default:
          feedbackText = forceContinueMode ? '⚠️ 강제 진행 모드' : '눈동자 추적 중...';
          detailText = 'Y위치: ${(irisY * 100).toInt()}% | 범위: ${(currentRange * 100).toInt()}% | 신뢰도: ${(confidence * 100).toInt()}%';
          feedbackColor = forceContinueMode ? Colors.red : Colors.blue;
          feedbackIcon = forceContinueMode ? Icons.warning : Icons.visibility;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: feedbackColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: feedbackColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: feedbackColor.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // 메인 피드백
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                feedbackIcon,
                color: feedbackColor,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                feedbackText,
                style: TextStyle(
                  color: feedbackColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // 상세 정보
          if (detailText.isNotEmpty) ...[
            SizedBox(height: 6),
            Text(
              detailText,
              style: TextStyle(
                color: feedbackColor.withOpacity(0.8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// 우하단의 눈동자 위치 표시기(격자 + 눈동자 점 + 신뢰도 %) + 인식 상태 배지.
class EyeTestTrackingOverlay extends StatelessWidget {
  final double confidence;
  final bool faceDetected;
  final double irisX;
  final double irisY;

  const EyeTestTrackingOverlay({
    Key? key,
    required this.confidence,
    required this.faceDetected,
    required this.irisX,
    required this.irisY,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isStable = confidence > 0.4; // 안정성 판정 기준 완화 (0.7→0.4)
    final statusColor = faceDetected ? (isStable ? Colors.green : Colors.orange) : Colors.red;
    final statusText = faceDetected ? (isStable ? '인식 중' : '불안정') : '감지 안됨';

    return Positioned(
      right: 20,
      bottom: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 실시간 상태 표시
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  faceDetected ? (isStable ? Icons.visibility : Icons.visibility_off) : Icons.face_retouching_off,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),

          // 눈동자 위치 표시기
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // 배경 격자
                CustomPaint(
                  size: Size(120, 120),
                  painter: GridPainter(),
                ),
                // 눈동자 위치
                CustomPaint(
                  painter: EyePositionPainter(irisX, irisY, confidence, faceDetected),
                ),
                // 신뢰도 텍스트
                if (faceDetected)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(confidence * 100).toInt()}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
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

/// 좌상단 디버그/상태 패널(세션 ID, 얼굴 인식, 눈동자 좌표, 신뢰도, 단계, 진행률, 프레임 수, 안정성).
class EyeTestStatusInfo extends StatelessWidget {
  final double confidence;
  final String? sessionId;
  final bool faceDetected;
  final double irisX;
  final double irisY;
  final String currentGazePhase;
  final int currentSet;
  final int totalSets;
  final int frameCount;
  final bool lastStable;

  const EyeTestStatusInfo({
    Key? key,
    required this.confidence,
    required this.sessionId,
    required this.faceDetected,
    required this.irisX,
    required this.irisY,
    required this.currentGazePhase,
    required this.currentSet,
    required this.totalSets,
    required this.frameCount,
    required this.lastStable,
  }) : super(key: key);

  static const double kConfidenceHigh = 0.3;
  static const double kConfidenceMedium = 0.2;

  @override
  Widget build(BuildContext context) {
    // 신뢰도에 따른 색상 결정
    Color confidenceColor = Colors.red;
    String confidenceText = 'Low';
    if (confidence >= kConfidenceHigh) {
      confidenceColor = Colors.green;
      confidenceText = 'High';
    } else if (confidence >= kConfidenceMedium) {
      confidenceColor = Colors.orange;
      confidenceText = 'Medium';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: faceDetected ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 세션 정보
          Row(
            children: [
              Icon(Icons.fingerprint, color: Colors.blue, size: 16),
              SizedBox(width: 4),
              Text(
                'Session: ${sessionId?.substring(0, 8)}...',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 6),

          // 얼굴 감지 상태
          Row(
            children: [
              Icon(
                faceDetected ? Icons.face : Icons.face_retouching_off,
                color: faceDetected ? Colors.green : Colors.red,
                size: 16,
              ),
              SizedBox(width: 4),
              Text(
                'Face: ${faceDetected ? 'Detected' : 'Not Found'}',
                style: TextStyle(
                  color: faceDetected ? Colors.green : Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 눈동자 위치
          Row(
            children: [
              Icon(Icons.visibility, color: Colors.blue, size: 16),
              SizedBox(width: 4),
              Text(
                'Eye: (${irisX.toStringAsFixed(2)}, ${irisY.toStringAsFixed(2)})',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 신뢰도
          Row(
            children: [
              Icon(Icons.speed, color: confidenceColor, size: 16),
              SizedBox(width: 4),
              Text(
                'Quality: $confidenceText (${(confidence * 100).toInt()}%)',
                style: TextStyle(
                  color: confidenceColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 현재 단계
          Row(
            children: [
              Icon(Icons.directions, color: Colors.yellow, size: 16),
              SizedBox(width: 4),
              Text(
                'Phase: $currentGazePhase',
                style: const TextStyle(color: Colors.yellow, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 세트 진행률
          Row(
            children: [
              Icon(Icons.timeline, color: Colors.cyan, size: 16),
              SizedBox(width: 4),
              Text(
                'Set: ${currentSet + 1}/$totalSets',
                style: const TextStyle(color: Colors.cyan, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 4),

          // 프레임 수
          Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.purple, size: 16),
              SizedBox(width: 4),
              Text(
                'Frames: $frameCount',
                style: const TextStyle(color: Colors.purple, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 6),

          // 안정성 표시
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: lastStable ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              lastStable ? 'STABLE' : 'UNSTABLE',
              style: TextStyle(
                color: lastStable ? Colors.green : Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
