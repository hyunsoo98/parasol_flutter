import 'package:flutter/material.dart';

// Eye Tracking 모드 정의
enum EyeTrackingMode {
  setup,
  calibration,
  test,
  analysis,
}

class EyeTrackingStep {
  final String title;
  final String instruction;
  final IconData? icon;
  final Color? iconColor;

  const EyeTrackingStep({
    required this.title,
    required this.instruction,
    this.icon,
    this.iconColor,
  });
}

class EyeTrackingConfig {
  static const List<EyeTrackingStep> setupSteps = [
    EyeTrackingStep(
      title: '핸드폰 고정하기',
      instruction: '벽이나 안정적인 물체에 핸드폰을 기대어 고정해주세요',
      icon: Icons.phone_android,
      iconColor: Colors.orange,
    ),
    EyeTrackingStep(
      title: '실시간 얼굴-눈동자 매핑',
      instruction: '자연스럽게 앞을 보맩니다. 얼굴과 눈동자가 실시간으로 매핑됩니다.',
      icon: Icons.face_retouching_natural,
      iconColor: Colors.green,
    ),
    EyeTrackingStep(
      title: '시선 추적 테스트',
      instruction: '머리를 움직이지 말고 눈으로만 지시사항을 따라주세요',
      icon: Icons.track_changes,
      iconColor: Colors.purple,
    ),
  ];

  static const List<EyeTrackingStep> pspSteps = [
    EyeTrackingStep(
      title: '핸드폰 고정하기',
      instruction: '핸드폰을 벽에 기대어 고정해주세요',
      icon: Icons.phone_android,
      iconColor: Colors.orange,
    ),
    EyeTrackingStep(
      title: '얼굴 기준점 캘리브레이션',
      instruction: '정면을 보고 가이드에 얼굴을 맞춰주세요. 기준점이 자동으로 설정됩니다.',
      icon: Icons.center_focus_strong,
      iconColor: Color(0xFF2F3DA3),
    ),
    EyeTrackingStep(
      title: '통합 얼굴-눈동자 매핑',
      instruction: '얼굴 기준으로 눈동자 위치가 매핑됩니다. 자연스럽게 있어주세요.',
      icon: Icons.face_retouching_natural,
      iconColor: Colors.green,
    ),
    EyeTrackingStep(
      title: '시선 추적 준비',
      instruction: '머리 고정, 눈으로만 움직일 준비',
      icon: Icons.visibility,
      iconColor: Colors.teal,
    ),
    EyeTrackingStep(
      title: 'PSP 시선 테스트',
      instruction: '머리를 고정하고 눈만 움직여주세요',
      icon: Icons.track_changes,
      iconColor: Colors.purple,
    ),
  ];
}

class GazeTestPhase {
  final int phase;
  final String instruction;
  final Offset? targetPosition;
  final int durationSeconds;

  const GazeTestPhase({
    required this.phase,
    required this.instruction,
    this.targetPosition,
    required this.durationSeconds,
  });

  static const List<GazeTestPhase> phases = [
    GazeTestPhase(
      phase: 0,
      instruction: '시선 테스트를 시작하려면 버튼을 누르세요',
      durationSeconds: 0,
    ),
    GazeTestPhase(
      phase: 1,
      instruction: '최대한 위쪽을 보세요',
      durationSeconds: 10,
    ),
    GazeTestPhase(
      phase: 2,
      instruction: '최대한 아래쪽을 보세요',
      durationSeconds: 10,
    ),
    GazeTestPhase(
      phase: 3,
      instruction: '테스트가 완료되었습니다',
      durationSeconds: 0,
    ),
  ];
}