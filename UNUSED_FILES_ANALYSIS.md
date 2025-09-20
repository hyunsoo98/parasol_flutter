# 사용하지 않는 파일 분석 보고서

## 🔍 분석 결과

### ❌ 삭제해야 할 파일들 (현재 미사용)

#### 1. 구형 Eye Tracking 관련 서비스 (서버 분석 → 클라이언트 분석으로 전환됨)
- `lib/services/mediapipe_service.dart` - MediaPipe 직접 사용 (deprecated)
- `lib/services/eye_tracking_service.dart` - 구형 시선 추적 서비스
- `lib/services/lambda_eye_tracking_service.dart` - Lambda 기반 분석 (deprecated)
- `lib/services/aws_async_eye_tracking_service.dart` - 비동기 AWS 분석 (deprecated)
- `lib/services/integrated_face_eye_service.dart` - 통합 얼굴/시선 서비스 (사용 안됨)

#### 2. 구형 화면들 (새로운 구조화된 테스트로 대체됨)
- `lib/screens/lambda_eye_tracking_screen.dart` - Lambda 분석 화면 (deprecated)
- `lib/screens/aws_async_eye_tracking_screen.dart` - 비동기 AWS 분석 화면 (deprecated)
- `lib/screens/phone_mount_guide_screen.dart` - 폰 거치대 가이드 (사용 안됨)

#### 3. 사용하지 않는 유틸리티 및 모델
- `lib/utils/safe_cam.dart` - 안전 카메라 유틸리티 (사용 안됨)
- `lib/services/background_removal_service.dart` - 배경 제거 (사용 안됨)
- `lib/services/analysis_polling_service.dart` - 폴링 서비스 (실시간으로 대체됨)
- `lib/widgets/analysis_progress_card.dart` - 분석 진행 위젯 (사용 안됨)

#### 4. 인증 관련 (Firebase → AWS 전환됨)
- `lib/services/amplify_auth_service.dart` - Amplify 인증 (사용 안됨)
- `lib/screens/phone_auth_screen.dart` - 전화 인증 화면 (사용 안됨)

### ⚠️ 보류/검토 필요한 파일들

#### 1. API 서비스들 (기능 확인 필요)
- `lib/services/amplify_api_service.dart` - Amplify API (finger tapping에서 사용 가능성)
- `lib/services/unified_api_service.dart` - 통합 API (사용 여부 확인 필요)

#### 2. 화면들 (향후 사용 계획 확인 필요)
- `lib/screens/voice_test_screen.dart` - 음성 테스트 (향후 구현 예정?)
- `lib/screens/voice_analysis_screen.dart` - 음성 분석 (향후 구현 예정?)
- `lib/screens/final_diagnosis_screen.dart` - 최종 진단 (향후 구현 예정?)
- `lib/screens/my_page_screen.dart` - 마이페이지 (향후 구현 예정?)

#### 3. 서비스들 (기능 확인 필요)
- `lib/services/diagnosis_flow_service.dart` - 진단 플로우 (사용 여부 확인)
- `lib/services/permission_service.dart` - 권한 서비스 (사용 여부 확인)

### ✅ 현재 활성 사용 중인 파일들

#### 1. 핵심 서비스
- `lib/services/api_service.dart` - 메인 API 서비스
- `lib/services/face_mesh_iris_service.dart` - 얼굴 메쉬/홍채 분석
- `lib/services/server_compatibility_service.dart` - 서버 호환성
- `lib/services/test_flow_service.dart` - 테스트 플로우 관리
- `lib/services/parasol_auth_service.dart` - Parasol 인증
- `lib/services/auth_service.dart` - 기본 인증 서비스
- `lib/services/aws_finger_tapping_service.dart` - AWS finger tapping

#### 2. 핵심 화면
- `lib/screens/structured_eye_test_screen.dart` - 구조화된 시선 테스트
- `lib/screens/camera_setup_screen.dart` - 카메라 설정
- `lib/screens/finger_tapping_screen.dart` - 손가락 탭핑 테스트
- `lib/screens/home_screen.dart` - 홈 화면
- `lib/screens/login_screen.dart` - 로그인 화면
- `lib/screens/splash_screen.dart` - 스플래시 화면
- `lib/screens/finger_tapping_guide_screen.dart` - 손가락 탭핑 가이드

#### 3. 기본 구조
- `lib/main.dart` - 메인 앱 진입점
- `lib/providers/auth_provider.dart` - 인증 프로바이더
- `lib/models/diagnosis_result.dart` - 진단 결과 모델
- `lib/models/eye_tracking_models.dart` - 시선 추적 모델
- `lib/config/aws_config.dart` - AWS 설정

## 📝 추천 작업 순서

1. **즉시 삭제 가능**: 명확히 사용하지 않는 파일들 삭제
2. **사용 여부 확인**: 보류 파일들의 실제 사용 여부 체크
3. **의존성 정리**: pubspec.yaml에서 사용하지 않는 패키지 제거
4. **import 정리**: 남은 파일들에서 삭제된 파일들에 대한 import 제거

## 🎯 정리 후 예상 효과

- **코드베이스 크기 30% 감소**
- **빌드 시간 단축**
- **유지보수성 향상**
- **의존성 충돌 위험 감소**