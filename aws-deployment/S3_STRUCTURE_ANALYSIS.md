# S3 구조 분석 및 Flutter 시선추적 변경사항 반영

## 🔍 현재 S3 구조 분석

### 실제 S3 구조 (seoul-ht-09)
```
seoul-ht-09/
├── diagnosis/
│   └── {session_id}/
├── eye-tracking/
│   └── {analysis_id}/
│   └── guest_1758185149971/
│       └── 2fab5a64-fc34-4fb8-a41c-7a8c2a66fbc2_1758207098.mp4
├── finger-tapping/
│   └── {analysis_id}/
├── videos/
│   └── eye-tracking/
│       └── guest_1758185149971/
│           └── 02b17b39-8e5d-4fdf-8b06-f79f3b95a673_1758250840.mp4
└── voice-analysis/
    └── {analysis_id}/
```

## 🎯 분석 및 문제점 식별

### 1. 중복 저장 구조 문제
현재 **eye-tracking 비디오가 두 곳에 저장**되고 있습니다:
- `eye-tracking/guest_xxx/` - 기존 AWS 분석용
- `videos/eye-tracking/guest_xxx/` - 별도 저장소?

### 2. Flutter 시선추적 변경사항
- **이전**: AWS Lambda에서 서버사이드 분석
- **현재**: Flutter 클라이언트에서 실시간 분석
- **결과**: 비디오 업로드 불필요, JSON 결과만 저장

### 3. 저장 방식 재설계 필요성
시선추적이 클라이언트 분석으로 변경되면서:
- ✅ **실시간 분석 결과 (JSON)**: 저장 필요
- ❌ **원본 비디오 파일**: 저장 불필요 (네트워크 비용 절약)
- ❌ **중복 경로**: 정리 필요

## 🏗️ 제안하는 새로운 S3 구조

### 최적화된 구조
```
seoul-ht-09/
├── diagnosis/                          # 종합 진단 세션
│   └── {session_id}/
│       ├── session_data.json
│       └── comprehensive_results.json
│
├── eye-tracking/                       # 시선추적 (Flutter 분석)
│   └── results/                        # 분석 결과만 저장
│       └── {analysis_id}/
│           ├── realtime_analysis.json   # 실시간 분석 결과
│           └── summary.json             # 요약 정보
│
├── finger-tapping/                     # 손가락 탭핑 (AWS 분석)
│   ├── raw/                           # 원본 비디오
│   │   └── {analysis_id}/
│   │       └── input.mp4
│   ├── processed/                     # 처리된 데이터
│   │   └── {analysis_id}/
│   │       └── landmarks.json
│   └── results/                       # 분석 결과
│       └── {analysis_id}/
│           ├── analysis.json
│           └── features.csv
│
└── voice-analysis/                     # 음성 분석 (AWS 분석)
    ├── raw/                           # 원본 오디오
    │   └── {analysis_id}/
    │       └── input.wav
    ├── processed/                     # 처리된 데이터
    │   └── {analysis_id}/
    │       └── features.json
    └── results/                       # 분석 결과
        └── {analysis_id}/
            ├── analysis.json
            └── features.json
```

## 📋 저장 방식 재설계

### 1. Eye Tracking (Flutter 실시간 분석)
```
저장 대상: 분석 결과만
저장 경로: eye-tracking/results/{analysis_id}/
저장 파일:
- realtime_analysis.json (실시간 분석 데이터)
- summary.json (PSP 진단 요약)
```

**JSON 구조 예시:**
```json
{
  "analysis_id": "uuid",
  "user_id": "guest_xxx",
  "analysis_type": "eye-tracking",
  "test_duration": 65.2,
  "total_frames": 1956,
  "vertical_range": 0.045,
  "psp_detected": false,
  "blink_count": 12,
  "confidence": "high",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### 2. Finger Tapping (AWS 서버 분석)
```
저장 대상: 원본 비디오 + 분석 결과
저장 경로:
- finger-tapping/raw/{analysis_id}/input.mp4
- finger-tapping/results/{analysis_id}/analysis.json
```

### 3. Voice Analysis (AWS 서버 분석 - 향후)
```
저장 대상: 원본 오디오 + 분석 결과
저장 경로:
- voice-analysis/raw/{analysis_id}/input.wav
- voice-analysis/results/{analysis_id}/analysis.json
```

## 🗂️ 정리해야 할 중복/불필요 경로

### 삭제 대상
1. **`videos/eye-tracking/`** - 중복 경로, 불필요
2. **`eye-tracking/{user_id}/`** - 기존 비디오 저장소, Flutter 분석으로 불필요
3. **기존 eye-tracking 비디오 파일들** - 클라이언트 분석으로 불필요

### 마이그레이션 계획
1. **기존 데이터 백업**
2. **새로운 구조로 점진적 이전**
3. **중복 경로 삭제**

## 🔄 Lambda 함수별 변경사항

### unified-upload Lambda
```python
# 변경 전
if analysis_type == 'eye-tracking':
    # 비디오 업로드 → SQS 전송

# 변경 후
if analysis_type == 'eye-tracking':
    # JSON 결과만 직접 저장, SQS 처리 없음
    s3_key = f"eye-tracking/results/{analysis_id}/realtime_analysis.json"
    # 즉시 completed 상태로 변경
```

### eye-tracking-process Lambda
```
상태: 삭제 또는 비활성화
이유: Flutter에서 실시간 분석으로 대체됨
```

### unified-status Lambda
```python
# eye-tracking 상태 조회시
if analysis_type == 'eye-tracking':
    # results 경로에서 JSON 파일 확인
    s3_key = f"eye-tracking/results/{analysis_id}/realtime_analysis.json"
```

## 📱 Flutter 클라이언트 변경사항

### 시선추적 플로우
```dart
// 1. 실시간 분석 수행 (StructuredEyeTestScreen)
final analysisResult = await eyeTestService.performAnalysis();

// 2. 결과를 JSON으로 AWS 업로드
await awsIntegrationService.uploadEyeTrackingResults(
  analysisId: analysisResult.analysisId,
  resultsData: analysisResult.toJson(),
  userId: currentUser.id,
);

// 3. 비디오 저장 없음 - 네트워크 비용 절약
```

### API 호출 변경
```dart
// 기존
await uploadFile(videoFile, 'eye-tracking', userId);

// 변경 후
await uploadEyeTrackingResults(analysisResults, userId);
```

## 💾 DynamoDB 스키마 조정

### analyses 테이블
```json
{
  "analysis_id": "uuid",
  "user_id": "guest_xxx",
  "analysis_type": "eye-tracking",
  "status": "completed",  // 즉시 완료
  "s3_paths": {
    "results": "eye-tracking/results/{analysis_id}/realtime_analysis.json"
    // raw 경로 없음 (비디오 저장 안함)
  },
  "results": {
    "psp_detected": false,
    "vertical_range": 0.045,
    "confidence": "high"
  }
}
```

## 🚀 마이그레이션 단계

### Phase 1: 정리 작업
1. **중복 경로 식별 및 백업**
2. **`videos/eye-tracking/` 폴더 삭제**
3. **기존 eye-tracking 비디오 파일 아카이브**

### Phase 2: 새 구조 적용
1. **Lambda 함수 업데이트**
2. **Flutter 앱 업데이트**
3. **API 엔드포인트 테스트**

### Phase 3: 검증 및 정리
1. **전체 플로우 테스트**
2. **불필요한 리소스 정리**
3. **비용 절약 효과 확인**

## 💰 예상 효과

### 비용 절약
- **네트워크 전송량 감소**: 시선추적 비디오 업로드 제거
- **S3 저장 비용 감소**: 중복 저장 경로 제거
- **Lambda 실행 비용 감소**: eye-tracking-process 불필요

### 성능 향상
- **실시간 분석**: 업로드 대기 시간 없음
- **즉시 결과 확인**: 서버 처리 시간 제거
- **네트워크 부하 감소**: 대용량 비디오 전송 없음

이 구조 변경으로 **비용 효율적이고 성능이 우수한** 시스템이 됩니다! 🎯