# AWS 기능의 Flutter 화면 구현 가이드

## 🎯 목표
현재 AWS Lambda에서 처리되는 기능들을 Flutter 앱에서 직접 사용할 수 있는 화면과 UI로 구현하여 사용자 경험을 향상시킵니다.

## 📊 현재 AWS 아키텍처 분석

### 1. 통합 업로드 시스템 (lambda_unified_upload.py)
**현재 기능:**
- 파일 업로드 (비디오/오디오/JSON 결과)
- S3 저장 및 DynamoDB 메타데이터 관리
- SQS 큐를 통한 비동기 처리 시작

**지원하는 분석 타입:**
- `finger-tapping`: 비디오 → SQS 처리
- `voice-analysis`: 오디오 → SQS 처리
- `eye-tracking-results`: JSON 결과만 저장 (클라이언트 분석 완료됨)

### 2. 통합 상태 조회 시스템 (lambda_unified_status.py)
**현재 기능:**
- 분석 상태 실시간 조회 (uploaded/processing/completed/failed)
- 진행률 및 예상 완료 시간 표시
- 완료된 결과 다운로드 URL 생성
- 사용자별 분석 기록 조회

### 3. Finger Tapping 분석 시스템 (lambda_finger_process.py)
**현재 기능:**
- MediaPipe 손 감지 및 탭핑 횟수 카운트
- AdaBoost 모델을 통한 파킨슨병 예측
- 양손 개별 분석 및 Noisy-OR 결합
- CSV 결과 파일 생성 및 S3 저장

## 🚀 Flutter 구현 계획

### Phase 1: 업로드 및 상태 관리 화면

#### 1.1 통합 업로드 화면 (`UploadManagerScreen`)
```dart
// lib/screens/upload_manager_screen.dart
class UploadManagerScreen extends StatefulWidget {
  final String analysisType; // 'finger-tapping', 'voice-analysis'
  final File mediaFile;
  final Map<String, dynamic> parameters;
}
```

**기능:**
- 드래그 앤 드롭 파일 업로드
- 업로드 진행률 표시
- 분석 파라미터 설정 UI
- 업로드 완료 후 자동으로 상태 모니터링으로 이동

#### 1.2 분석 상태 모니터링 화면 (`AnalysisStatusScreen`)
```dart
// lib/screens/analysis_status_screen.dart
class AnalysisStatusScreen extends StatefulWidget {
  final String analysisId;
  final String analysisType;
}
```

**기능:**
- 실시간 분석 진행률 표시 (폴링 또는 WebSocket)
- 단계별 상태 시각화 (업로드됨 → 처리중 → 완료됨)
- 예상 완료 시간 표시
- 에러 발생시 재시작 옵션

#### 1.3 결과 조회 및 다운로드 화면 (`ResultsViewScreen`)
```dart
// lib/screens/results_view_screen.dart
class ResultsViewScreen extends StatefulWidget {
  final String analysisId;
  final String analysisType;
}
```

**기능:**
- 분석 결과 요약 표시
- 상세 결과 데이터 시각화
- CSV/JSON 다운로드 기능
- 결과 공유 기능

### Phase 2: 분석 기록 관리

#### 2.1 분석 기록 대시보드 (`AnalysisHistoryScreen`)
```dart
// lib/screens/analysis_history_screen.dart
class AnalysisHistoryScreen extends StatefulWidget {
  final String? userId;
}
```

**기능:**
- 사용자별 모든 분석 기록 표시
- 분석 타입별 필터링
- 상태별 필터링 (완료/진행중/실패)
- 각 기록 클릭시 상세 결과 화면으로 이동

#### 2.2 통계 및 트렌드 화면 (`AnalyticsDashboardScreen`)
```dart
// lib/screens/analytics_dashboard_screen.dart
class AnalyticsDashboardScreen extends StatefulWidget {
  final String userId;
}
```

**기능:**
- 시간별 분석 결과 트렌드
- 분석 타입별 성공률
- 평균 분석 시간 통계
- 차트 및 그래프 시각화

### Phase 3: 고급 기능

#### 3.1 배치 업로드 화면 (`BatchUploadScreen`)
```dart
// lib/screens/batch_upload_screen.dart
class BatchUploadScreen extends StatefulWidget {
  final String analysisType;
}
```

**기능:**
- 여러 파일 동시 업로드
- 각 파일별 개별 진행률 표시
- 전체 배치 완료율 표시
- 실패한 파일 재업로드 기능

#### 3.2 분석 설정 화면 (`AnalysisSettingsScreen`)
```dart
// lib/screens/analysis_settings_screen.dart
class AnalysisSettingsScreen extends StatefulWidget {
  final String analysisType;
}
```

**기능:**
- 분석 파라미터 세부 설정
- 프리셋 저장 및 불러오기
- 분석 품질 vs 속도 트레이드오프 설정
- 알림 설정 (분석 완료시)

## 🛠 구현 순서 및 우선순위

### 1단계: 핵심 기능 (1주)
1. `UploadManagerScreen` - 기본 업로드 기능
2. `AnalysisStatusScreen` - 상태 모니터링
3. `ResultsViewScreen` - 결과 조회
4. 관련 서비스 클래스들 구현

### 2단계: 사용자 경험 개선 (1주)
1. `AnalysisHistoryScreen` - 기록 관리
2. 에러 처리 및 재시도 로직
3. 오프라인 지원 (로컬 캐싱)
4. 푸시 알림 통합

### 3단계: 고급 기능 (1주)
1. `BatchUploadScreen` - 배치 처리
2. `AnalyticsDashboardScreen` - 통계
3. `AnalysisSettingsScreen` - 설정 관리
4. 성능 최적화

## 📱 UI/UX 가이드라인

### 디자인 원칙
1. **진행률 투명성**: 모든 단계에서 현재 상태를 명확히 표시
2. **인터랙티브 피드백**: 사용자 액션에 즉각적인 반응
3. **에러 복구**: 실패시 명확한 원인과 해결 방법 제시
4. **일관성**: 모든 분석 타입에서 동일한 UI 패턴 사용

### 컴포넌트 재사용성
```dart
// 공통 위젯들
- UploadProgressWidget
- AnalysisStatusWidget
- ResultSummaryWidget
- ErrorRecoveryWidget
- FilePickerWidget
```

## 🔧 필요한 서비스 클래스

### 1. AWS API 통합 서비스
```dart
// lib/services/aws_integration_service.dart
class AwsIntegrationService {
  Future<UploadResponse> uploadFile(File file, String analysisType, Map<String, dynamic> params);
  Future<AnalysisStatus> getAnalysisStatus(String analysisId);
  Future<AnalysisResult> getAnalysisResult(String analysisId);
  Future<List<AnalysisRecord>> getUserAnalyses(String userId);
  Future<String> generateDownloadUrl(String s3Key);
}
```

### 2. 실시간 상태 폴링 서비스
```dart
// lib/services/status_polling_service.dart
class StatusPollingService {
  Stream<AnalysisStatus> watchAnalysisStatus(String analysisId);
  void startPolling(String analysisId);
  void stopPolling(String analysisId);
}
```

### 3. 로컬 캐시 서비스
```dart
// lib/services/analysis_cache_service.dart
class AnalysisCacheService {
  Future<void> cacheAnalysisResult(String analysisId, AnalysisResult result);
  Future<AnalysisResult?> getCachedResult(String analysisId);
  Future<void> cacheUserHistory(String userId, List<AnalysisRecord> records);
}
```

## 📊 데이터 모델

### 분석 상태 모델
```dart
// lib/models/analysis_models.dart
class AnalysisStatus {
  final String analysisId;
  final String userId;
  final String analysisType;
  final String status; // uploaded, processing, completed, failed
  final int progress; // 0-100
  final String progressMessage;
  final DateTime timestamp;
  final int? estimatedCompletion;
}

class AnalysisResult {
  final String analysisId;
  final String analysisType;
  final Map<String, dynamic> result;
  final Map<String, dynamic> summary;
  final List<DownloadUrl> downloadUrls;
  final DateTime completedAt;
}

class AnalysisRecord {
  final String analysisId;
  final String analysisType;
  final String status;
  final DateTime timestamp;
  final int progress;
  final int? fileSize;
}
```

## 🔄 통합 플로우

### Finger Tapping 전체 플로우
1. **녹화**: `FingerTappingScreen`에서 비디오 녹화
2. **업로드**: `UploadManagerScreen`으로 자동 이동
3. **모니터링**: `AnalysisStatusScreen`에서 실시간 상태 확인
4. **결과**: `ResultsViewScreen`에서 결과 확인
5. **기록**: `AnalysisHistoryScreen`에서 이전 결과들과 비교

### Eye Tracking 플로우 (이미 구현됨)
1. **실시간 분석**: `StructuredEyeTestScreen`에서 실시간 분석
2. **결과 업로드**: JSON 형태로 AWS에 결과만 저장
3. **기록 관리**: 다른 테스트와 동일한 인터페이스

## 📈 성능 고려사항

### 1. 파일 업로드 최적화
- 청크 단위 업로드 (대용량 파일)
- 재시도 로직 (네트워크 불안정)
- 압축 옵션 (파일 크기 최적화)

### 2. 실시간 상태 업데이트
- 폴링 간격 최적화 (처리 단계별 차등)
- WebSocket 고려 (실시간성 중요시)
- 백그라운드 상태에서 폴링 중단

### 3. 결과 캐싱
- 로컬 데이터베이스 (SQLite)
- 이미지/차트 캐싱
- 오프라인 모드 지원

## 🎉 예상 효과

### 사용자 경험
- **투명성**: 분석 과정의 모든 단계를 실시간으로 확인
- **편의성**: 하나의 앱에서 모든 기능 통합
- **신뢰성**: 에러 상황에서도 명확한 안내와 복구 옵션

### 개발 효율성
- **재사용성**: 공통 컴포넌트로 개발 시간 단축
- **유지보수**: 일관된 패턴으로 버그 수정 용이
- **확장성**: 새로운 분석 타입 추가시 기존 구조 활용

이 가이드를 따라 구현하면 AWS의 강력한 백엔드 처리 능력과 Flutter의 뛰어난 사용자 인터페이스가 결합된 완성도 높은 앱을 만들 수 있습니다.