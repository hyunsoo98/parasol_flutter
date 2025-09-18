# 📊 파킨슨 분석 결과 값 표현 형식

## 🎯 **개별 분석 결과 형식**

### **1. 아이 트래킹 분석 결과**
```json
{
  "analysis_id": "eye_20240917_123456_abc123",
  "analysis_type": "eye-tracking",
  "status": "completed",
  "timestamp": 1694956800,
  "processing_time": 45.2,
  "results": {
    "eye_movement_metrics": {
      "saccade_count": 234,
      "saccade_velocity_avg": 287.5,
      "saccade_amplitude_avg": 4.2,
      "fixation_duration_avg": 245.8,
      "smooth_pursuit_gain": 0.89,
      "microsaccade_rate": 1.2
    },
    "parkinson_indicators": {
      "saccade_hypometria": 0.78,
      "pursuit_deficit": 0.65,
      "fixation_instability": 0.43,
      "overall_severity": "moderate"
    },
    "classification": {
      "pd_probability": 0.78,
      "confidence": 0.85,
      "risk_level": "high",
      "recommendation": "추가 신경학적 검사 권장"
    }
  },
  "summary": {
    "key_findings": [
      "사카드 운동의 진폭 감소 관찰",
      "부드러운 추적 운동의 정확도 저하",
      "고정점 유지 시 미세한 불안정성"
    ],
    "severity_score": 7.2,
    "interpretation": "중등도 파킨슨병 징후 검출"
  }
}
```

### **2. 손가락 태핑 분석 결과**
```json
{
  "analysis_id": "finger_20240917_123456_def456",
  "analysis_type": "finger-tapping",
  "status": "completed",
  "timestamp": 1694956800,
  "processing_time": 32.1,
  "results": {
    "tapping_metrics": {
      "tap_count": 127,
      "frequency_hz": 4.23,
      "amplitude_avg": 2.8,
      "amplitude_decrease": 0.34,
      "rhythm_variability": 0.28,
      "fatigue_index": 0.56
    },
    "motion_analysis": {
      "velocity_consistency": 0.72,
      "acceleration_pattern": 0.68,
      "hesitation_episodes": 3,
      "freezing_episodes": 1
    },
    "parkinson_indicators": {
      "bradykinesia": 0.71,
      "decrementing_amplitude": 0.65,
      "rhythm_irregularity": 0.58,
      "overall_severity": "mild_to_moderate"
    },
    "classification": {
      "pd_probability": 0.73,
      "confidence": 0.82,
      "risk_level": "moderate",
      "recommendation": "추가 운동 검사 필요"
    }
  },
  "summary": {
    "key_findings": [
      "태핑 진폭의 점진적 감소",
      "리듬 불규칙성 관찰",
      "경미한 운동완서 징후"
    ],
    "severity_score": 6.8,
    "interpretation": "경도-중등도 운동 장애 징후"
  }
}
```

### **3. 음성 분석 결과 (PyTorch 모델)**
```json
{
  "analysis_id": "voice_20240917_123456_ghi789",
  "analysis_type": "voice-analysis",
  "status": "completed",
  "timestamp": 1694956800,
  "processing_time": 28.7,
  "results": {
    "audio_features": {
      "mel_spectrogram_features": {
        "spectral_centroid": 1245.6,
        "spectral_rolloff": 3456.8,
        "zero_crossing_rate": 0.034,
        "energy_distribution": [0.23, 0.31, 0.28, 0.18]
      },
      "mfcc_features": {
        "mfcc_coefficients": [12.3, -4.1, 2.8, -1.2, 0.9, -0.4, 0.2, -0.1, 0.05, -0.03, 0.02, -0.01, 0.01],
        "delta_mfcc": [0.8, -0.3, 0.2, -0.1, 0.05, -0.02, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        "delta2_mfcc": [0.1, -0.05, 0.03, -0.02, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
      },
      "prosodic_features": {
        "fundamental_frequency": 145.3,
        "jitter": 0.0156,
        "shimmer": 0.0234,
        "hnr": 15.67
      }
    },
    "model_predictions": {
      "multibranch_output": {
        "cnn_branch": [0.12, 0.76, 0.08, 0.04],
        "bigru_branch": [0.15, 0.72, 0.09, 0.04],
        "mlp_branch": [0.11, 0.78, 0.07, 0.04]
      },
      "ensemble_result": [0.126, 0.753, 0.080, 0.041],
      "class_probabilities": {
        "HC": 0.126,  // Healthy Control
        "PD": 0.753,  // Parkinson's Disease
        "MSA": 0.080, // Multiple System Atrophy
        "PSP": 0.041  // Progressive Supranuclear Palsy
      }
    },
    "classification": {
      "predicted_class": "PD",
      "confidence": 0.753,
      "risk_level": "high",
      "differential_diagnosis": {
        "primary": "파킨슨병",
        "secondary": "다계통위축증",
        "certainty": "높음"
      }
    },
    "voice_biomarkers": {
      "vocal_tremor": 0.67,
      "breathy_voice": 0.54,
      "monotonic_speech": 0.71,
      "articulation_difficulty": 0.48
    }
  },
  "summary": {
    "key_findings": [
      "음성에서 파킨슨병 특징적 패턴 검출",
      "단조로운 억양과 떨림 성분 관찰",
      "발음 명료도 경미한 감소"
    ],
    "severity_score": 7.5,
    "interpretation": "파킨슨병 고위험군, 신경과 진료 권장"
  }
}
```

## 🏥 **종합 진단 결과 형식**

### **통합 진단 세션 결과**
```json
{
  "session_id": "diagnosis_20240917_123456_xyz",
  "user_id": "user_12345",
  "status": "completed",
  "timestamp": 1694956800,
  "total_processing_time": 156.8,
  "individual_analyses": {
    "eye_tracking": "eye_20240917_123456_abc123",
    "finger_tapping": "finger_20240917_123456_def456",
    "voice_analysis": "voice_20240917_123456_ghi789"
  },
  "comprehensive_results": {
    "overall_assessment": {
      "pd_probability": 0.768,
      "confidence": 0.873,
      "consensus_level": "high",
      "risk_classification": "high_risk"
    },
    "multimodal_analysis": {
      "eye_tracking_score": 7.2,
      "finger_tapping_score": 6.8,
      "voice_analysis_score": 7.5,
      "weighted_average": 7.17,
      "consistency_score": 0.89
    },
    "biomarker_correlation": {
      "motor_symptoms": {
        "bradykinesia": 0.69,
        "rigidity_indicators": 0.54,
        "tremor_components": 0.61
      },
      "non_motor_symptoms": {
        "cognitive_markers": 0.43,
        "speech_changes": 0.67,
        "autonomic_indicators": 0.38
      }
    },
    "clinical_interpretation": {
      "primary_diagnosis": "파킨슨병 의심",
      "confidence_level": "높음",
      "stage_estimation": "초기-중기 (Hoehn-Yahr 2단계 추정)",
      "symptom_profile": [
        "운동완서 (bradykinesia)",
        "음성 변화",
        "안구운동 이상"
      ]
    }
  },
  "recommendations": {
    "immediate_actions": [
      "신경과 전문의 진료 예약",
      "도파민 운반체 스캔 (DaTscan) 검토",
      "운동 기능 정밀 검사"
    ],
    "follow_up": [
      "3개월 후 재평가",
      "운동 치료 프로그램 시작",
      "가족력 및 환경 요인 조사"
    ],
    "lifestyle": [
      "규칙적인 운동 (주 3회 이상)",
      "균형감각 훈련",
      "음성 치료 고려"
    ]
  },
  "summary": {
    "executive_summary": "다중 모달 분석 결과, 파킨슨병의 초기-중기 징후가 일관되게 관찰됨. 특히 운동 기능과 음성 변화에서 뚜렷한 이상 소견을 보임.",
    "overall_severity": "moderate",
    "urgency": "high_priority",
    "next_steps": "신경과 전문의 진료를 통한 정밀 진단 필요"
  }
}
```

## 📈 **상태 진행 단계**

### **분석 상태 코드**
```json
{
  "uploaded": "파일 업로드 완료",
  "queued": "처리 대기 중",
  "processing": "분석 진행 중",
  "completed": "분석 완료",
  "failed": "분석 실패",
  "timeout": "처리 시간 초과"
}
```

### **진단 세션 상태**
```json
{
  "initiated": "세션 시작",
  "collecting": "개별 분석 수집 중",
  "analyzing": "종합 분석 중",
  "completed": "진단 완료",
  "expired": "세션 만료"
}
```

## 🎨 **Flutter 앱 표시 형식**

### **개별 분석 결과 카드**
```dart
ResultCard(
  analysisType: "음성 분석",
  severity: 7.5,
  riskLevel: "높음",
  keyFindings: [
    "파킨슨병 특징적 패턴 검출",
    "단조로운 억양과 떨림 성분",
    "발음 명료도 경미한 감소"
  ],
  recommendation: "신경과 진료 권장",
  confidenceScore: 0.753
)
```

### **종합 진단 대시보드**
```dart
ComprehensiveDashboard(
  overallScore: 7.17,
  riskLevel: "높음",
  primaryDiagnosis: "파킨슨병 의심",
  subScores: {
    "eye_tracking": 7.2,
    "finger_tapping": 6.8,
    "voice_analysis": 7.5
  },
  recommendations: [...],
  nextSteps: [...]
)
```

이렇게 체계적으로 결과가 구조화되어 사용자에게 명확하고 실용적인 정보를 제공합니다.