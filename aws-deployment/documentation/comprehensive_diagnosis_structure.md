# 🎯 종합 진단 결과 관리 구조

## 📊 **데이터 구조 설계**

### **1. 개별 분석 결과 (기존 유지)**
```
eye-tracking-results      → Eye tracking 전용 결과
finger-tapping-results    → Finger tapping 전용 결과
voice-analysis-results    → Voice analysis 전용 결과
```

### **2. 종합 진단 세션 (신규 추가)**
```
comprehensive-diagnosis   → 3가지 분석을 묶은 종합 진단
```

## 🔄 **진단 세션 플로우**

### **Step 1: 진단 세션 시작**
```json
POST /api/v1/diagnosis/start
{
  "user_id": "user123",
  "session_name": "2024년 1월 정기검진"
}

Response:
{
  "diagnosis_session_id": "session-uuid-12345",
  "status": "in_progress",
  "required_analyses": ["eye-tracking", "finger-tapping", "voice-analysis"],
  "completed_analyses": []
}
```

### **Step 2: 개별 분석 수행**
```json
POST /api/v1/upload
{
  "analysis_type": "eye-tracking",
  "diagnosis_session_id": "session-uuid-12345",  // ← 세션 연결
  "video_data": "...",
  "user_id": "user123"
}
```

### **Step 3: 세션 상태 업데이트**
각 분석 완료시 종합 진단 테이블 업데이트:
```json
{
  "diagnosis_session_id": "session-uuid-12345",
  "user_id": "user123",
  "status": "in_progress",
  "timestamp": 1703123456,
  "analyses": {
    "eye-tracking": {
      "analysis_id": "eye-uuid-123",
      "status": "completed",
      "completion_time": 1703123456,
      "parkinson_probability": 0.65
    },
    "finger-tapping": {
      "analysis_id": "finger-uuid-456",
      "status": "completed",
      "completion_time": 1703123467,
      "parkinson_probability": 0.72
    },
    "voice-analysis": {
      "analysis_id": "voice-uuid-789",
      "status": "processing",
      "completion_time": null,
      "parkinson_probability": null
    }
  },
  "comprehensive_result": null  // 모든 분석 완료 후 생성
}
```

### **Step 4: 종합 결과 생성**
```json
{
  "diagnosis_session_id": "session-uuid-12345",
  "status": "completed",
  "comprehensive_result": {
    "overall_parkinson_probability": 0.71,
    "confidence_level": "high",
    "assessment": "파킨슨병 징후 중등도 의심",
    "individual_scores": {
      "eye-tracking": 0.65,
      "finger-tapping": 0.72,
      "voice-analysis": 0.76
    },
    "dominant_indicators": [
      "음성 분석에서 높은 위험도",
      "손가락 탭핑에서 리듬 불규칙성",
      "안구 운동에서 경미한 이상"
    ],
    "recommendations": [
      "신경과 전문의 상담 권장",
      "정기적인 모니터링 필요",
      "생활습관 개선 방안"
    ]
  }
}
```

## 🎯 **API 엔드포인트 확장**

### **기존 API (개별 분석)**
```
POST /api/v1/upload           → 개별 분석
GET  /api/v1/status/{id}      → 개별 결과
GET  /api/v1/results/{id}     → 개별 결과 상세
```

### **신규 API (종합 진단)**
```
POST /api/v1/diagnosis/start                    → 진단 세션 시작
GET  /api/v1/diagnosis/{session_id}             → 세션 상태 조회
GET  /api/v1/diagnosis/{session_id}/summary     → 종합 결과 요약
GET  /api/v1/diagnosis/user/{user_id}           → 사용자별 진단 이력
```

## 🔄 **사용 시나리오**

### **시나리오 1: 순차적 진단**
```dart
// 1. 진단 세션 시작
final session = await startDiagnosisSession(userId: 'user123');

// 2. Eye tracking 분석
final eyeResult = await uploadAnalysis(
  analysisType: 'eye-tracking',
  sessionId: session.sessionId,
  videoData: eyeVideoData
);

// 3. Finger tapping 분석
final fingerResult = await uploadAnalysis(
  analysisType: 'finger-tapping',
  sessionId: session.sessionId,
  videoData: fingerVideoData
);

// 4. Voice analysis 분석
final voiceResult = await uploadAnalysis(
  analysisType: 'voice-analysis',
  sessionId: session.sessionId,
  audioData: voiceAudioData
);

// 5. 종합 결과 조회
final comprehensiveResult = await getDiagnosisSummary(session.sessionId);
```

### **시나리오 2: 병렬 진단**
```dart
// 1. 진단 세션 시작
final session = await startDiagnosisSession(userId: 'user123');

// 2. 3가지 분석 동시 시작
final futures = await Future.wait([
  uploadAnalysis(analysisType: 'eye-tracking', sessionId: session.sessionId, ...),
  uploadAnalysis(analysisType: 'finger-tapping', sessionId: session.sessionId, ...),
  uploadAnalysis(analysisType: 'voice-analysis', sessionId: session.sessionId, ...)
]);

// 3. 모든 분석 완료까지 대기
await waitForSessionCompletion(session.sessionId);

// 4. 종합 결과 조회
final result = await getDiagnosisSummary(session.sessionId);
```

## 🎨 **결과 표시 UI 구조**

### **진행 상태 화면**
```
진단 진행률: ████████░░ 80%

✅ 안구 운동 분석 완료 (위험도: 중간)
✅ 손가락 탭핑 분석 완료 (위험도: 높음)
🔄 음성 분석 진행중... (예상 완료: 1분 후)
```

### **종합 결과 화면**
```
🎯 종합 진단 결과

전체 파킨슨병 위험도: ⚠️ 71% (중등도 위험)

개별 분석 결과:
📊 안구 운동: 65% (중간)
✋ 손가락 탭핑: 72% (높음)
🎵 음성 분석: 76% (높음)

주요 소견:
• 음성 떨림 및 단조로운 말투 감지
• 손가락 탭핑 리듬 불규칙성
• 안구 운동 속도 경미한 저하

권장사항:
• 신경과 전문의 상담 권장
• 3개월 후 재검사 권장
```

## 🔧 **구현 고려사항**

### **장점**
✅ **개별 + 통합**: 각 분석 결과도 보고 종합 결과도 제공
✅ **점진적 완성**: 하나씩 완료되어도 중간 결과 확인 가능
✅ **이력 관리**: 사용자별 진단 세션 이력 추적
✅ **유연성**: 일부 분석만 수행해도 결과 제공

### **단점**
⚠️ **복잡성 증가**: 데이터 구조 및 로직 복잡
⚠️ **일관성 관리**: 개별 결과와 종합 결과 동기화 필요

### **권장 접근법**
1. **1단계**: 개별 분석 완성 (현재 구조)
2. **2단계**: 종합 진단 세션 추가
3. **3단계**: AI 기반 종합 분석 고도화

어떤 방향으로 진행하시겠습니까?
- A) 개별 결과만 제공 (단순)
- B) 종합 진단 세션 추가 (완전)
- C) 단계적 구현 (권장)