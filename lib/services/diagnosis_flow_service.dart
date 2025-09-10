// lib/services/diagnosis_flow_service.dart
import '../models/diagnosis_result.dart';

enum TestStep {
  INITIAL_CLASSIFICATION,
  PHONE_SETUP_GUIDE, // 폰 세팅 안내
  HEAD_POSITION_GUIDE, // 머리 위치 안내
  PHONE_MOUNT_1, // 첫 번째 폰 거치 (시선 추적용)
  EYE_TRACKING_GUIDE,
  EYE_TRACKING,
  FINGER_TAPPING_GUIDE,
  FINGER_TAPPING,
  PHONE_MOUNT_2, // 두 번째 폰 거치 (음성용)
  VOICE_ANALYSIS,
  COMPLETED
}

class DiagnosisFlowService {
  static DiagnosisFlowService? _instance;
  DiagnosisFlowService._internal();
  
  factory DiagnosisFlowService() {
    _instance ??= DiagnosisFlowService._internal();
    return _instance!;
  }

  // 현재 진단 플로우 상태
  DiagnosisResult? _initialClassification;
  EyeTrackingResult? _eyeTrackingResult;
  Map<String, dynamic>? _fingerTappingResult;
  Map<String, dynamic>? _voiceAnalysisResult;
  TestStep _currentStep = TestStep.INITIAL_CLASSIFICATION;

  // Getters
  DiagnosisResult? get initialClassification => _initialClassification;
  EyeTrackingResult? get eyeTrackingResult => _eyeTrackingResult;
  Map<String, dynamic>? get fingerTappingResult => _fingerTappingResult;
  Map<String, dynamic>? get voiceAnalysisResult => _voiceAnalysisResult;
  TestStep get currentStep => _currentStep;

  /// 초기 분류 결과 설정 (Python API에서 받아올 예정)
  void setInitialClassification(DiagnosisResult result) {
    _initialClassification = result;
    _currentStep = _getNextStep();
  }

  /// 시선 추적 결과 설정
  void setEyeTrackingResult(EyeTrackingResult result) {
    _eyeTrackingResult = result;
    _currentStep = _getNextStep();
  }

  /// 핑거 탭핑 결과 설정
  void setFingerTappingResult(Map<String, dynamic> result) {
    _fingerTappingResult = result;
    _currentStep = _getNextStep();
  }

  /// 음성 분석 결과 설정
  void setVoiceAnalysisResult(Map<String, dynamic> result) {
    _voiceAnalysisResult = result;
    _currentStep = _getNextStep();
  }

  /// 다음 단계 결정 로직
  TestStep _getNextStep() {
    switch (_currentStep) {
      case TestStep.INITIAL_CLASSIFICATION:
        if (_initialClassification == null) return TestStep.INITIAL_CLASSIFICATION;
        return TestStep.PHONE_SETUP_GUIDE;
        
      case TestStep.PHONE_SETUP_GUIDE:
        return TestStep.HEAD_POSITION_GUIDE;
        
      case TestStep.HEAD_POSITION_GUIDE:
        return TestStep.PHONE_MOUNT_1;
        
      case TestStep.PHONE_MOUNT_1:
        // 모든 경우에 시선 검사를 먼저 진행
        return TestStep.EYE_TRACKING_GUIDE;
        
      case TestStep.EYE_TRACKING_GUIDE:
        return TestStep.EYE_TRACKING;
        
      case TestStep.EYE_TRACKING:
        // 시선 검사 결과에 따라 다음 단계 결정
        if (_eyeTrackingResult != null) {
          // HC 판정 시: 핑거 탭핑으로
          if (_eyeTrackingResult!.suggestedType == DiagnosisType.HC) {
            return TestStep.FINGER_TAPPING_GUIDE;
          }
          // PSP 판정 시: 음성 검사로
          else {
            return TestStep.PHONE_MOUNT_2;
          }
        }
        return TestStep.PHONE_MOUNT_2; // 기본값
        
      case TestStep.FINGER_TAPPING_GUIDE:
        return TestStep.FINGER_TAPPING;
        
      case TestStep.FINGER_TAPPING:
        return TestStep.PHONE_MOUNT_2;
        
      case TestStep.PHONE_MOUNT_2:
        return TestStep.VOICE_ANALYSIS;
        
      case TestStep.VOICE_ANALYSIS:
        return TestStep.COMPLETED;
        
      case TestStep.COMPLETED:
        return TestStep.COMPLETED;
    }
  }

  /// 현재 단계에서 실행해야 할 검사 타입 반환
  List<TestStep> getRequiredTests() {
    if (_initialClassification == null) {
      return [TestStep.INITIAL_CLASSIFICATION];
    }

    List<TestStep> tests = [];
    
    if (_initialClassification!.type == DiagnosisType.PSP) {
      // PSP: 시선 → 음성
      if (_eyeTrackingResult == null) tests.add(TestStep.EYE_TRACKING);
      if (_voiceAnalysisResult == null) tests.add(TestStep.VOICE_ANALYSIS);
    } else if (_initialClassification!.type == DiagnosisType.HC) {
      // HC: 핑거 탭핑 → 음성
      if (_fingerTappingResult == null) tests.add(TestStep.FINGER_TAPPING);
      if (_voiceAnalysisResult == null) tests.add(TestStep.VOICE_ANALYSIS);
    }
    
    return tests;
  }

  /// 진단 플로우 완료 여부 확인
  bool isFlowCompleted() {
    return _currentStep == TestStep.COMPLETED;
  }

  /// 진단 플로우 재시작
  void resetFlow() {
    _initialClassification = null;
    _eyeTrackingResult = null;
    _fingerTappingResult = null;
    _voiceAnalysisResult = null;
    _currentStep = TestStep.INITIAL_CLASSIFICATION;
  }

  /// 최종 진단 결과 생성
  Map<String, dynamic> getFinalDiagnosisResult() {
    return {
      'initialClassification': _initialClassification?.toJson(),
      'eyeTrackingResult': _eyeTrackingResult?.toJson(),
      'fingerTappingResult': _fingerTappingResult,
      'voiceAnalysisResult': _voiceAnalysisResult,
      'completedAt': DateTime.now().toIso8601String(),
      'flowType': _initialClassification?.type.toString().split('.').last,
    };
  }

  /// 진행률 계산
  double getProgress() {
    if (_initialClassification == null) return 0.0;
    
    int completed = 1; // 초기 분류 완료
    int total = 3; // 초기 분류 + 2개 검사
    
    if (_initialClassification!.type == DiagnosisType.PSP) {
      if (_eyeTrackingResult != null) completed++;
    } else if (_initialClassification!.type == DiagnosisType.HC) {
      if (_fingerTappingResult != null) completed++;
    }
    
    if (_voiceAnalysisResult != null) completed++;
    
    return completed / total;
  }
}