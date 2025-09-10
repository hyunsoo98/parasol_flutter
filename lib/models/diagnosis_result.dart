// lib/models/diagnosis_result.dart
enum DiagnosisType { PSP, HC, UNKNOWN }

class DiagnosisResult {
  final DiagnosisType type;
  final double confidence;
  final DateTime timestamp;
  final Map<String, dynamic> additionalData;

  DiagnosisResult({
    required this.type,
    required this.confidence,
    required this.timestamp,
    this.additionalData = const {},
  });

  factory DiagnosisResult.fromJson(Map<String, dynamic> json) {
    return DiagnosisResult(
      type: DiagnosisType.values.firstWhere(
        (e) => e.toString() == 'DiagnosisType.${json['type']}',
        orElse: () => DiagnosisType.UNKNOWN,
      ),
      confidence: json['confidence']?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp']),
      additionalData: json['additionalData'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'additionalData': additionalData,
    };
  }
}

class EyeTrackingResult {
  final bool hasAbnormality;
  final double abnormalityScore;
  final List<String> detectedIssues;
  final DateTime timestamp;
  final DiagnosisType suggestedType; // HC 또는 PSP 제안

  EyeTrackingResult({
    required this.hasAbnormality,
    required this.abnormalityScore,
    required this.detectedIssues,
    required this.timestamp,
    required this.suggestedType,
  });

  factory EyeTrackingResult.fromJson(Map<String, dynamic> json) {
    // Python FastAPI 응답 구조에 맞게 파싱
    final analysisResult = json['analysis_result'] as Map<String, dynamic>?;
    final pspScreening = analysisResult?['psp_screening'] as Map<String, dynamic>?;
    final verticalMovement = analysisResult?['vertical_movement'] as Map<String, dynamic>?;
    final blinkAnalysis = analysisResult?['blink_analysis'] as Map<String, dynamic>?;
    
    final pspSuspected = pspScreening?['suspected'] ?? false;
    final verticalPtp = verticalMovement?['peak_to_peak'] ?? 0.0;
    // final blinkCount = blinkAnalysis?['count'] ?? 0; // Currently unused
    
    List<String> issues = [];
    if (pspSuspected) {
      issues.add('수직 시선 움직임 제한 감지됨');
    }
    if (verticalPtp < 0.06) {
      issues.add('비정상적으로 낮은 수직 시선 범위');
    }
    
    return EyeTrackingResult(
      hasAbnormality: pspSuspected,
      abnormalityScore: pspSuspected ? 0.8 : 0.2,
      detectedIssues: issues,
      timestamp: DateTime.now(),
      suggestedType: pspSuspected ? DiagnosisType.PSP : DiagnosisType.HC,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hasAbnormality': hasAbnormality,
      'abnormalityScore': abnormalityScore,
      'detectedIssues': detectedIssues,
      'timestamp': timestamp.toIso8601String(),
      'suggestedType': suggestedType.toString().split('.').last,
    };
  }
}