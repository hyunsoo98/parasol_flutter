# 파킨슨 진단 앱 - 활용 중인 파일 목록

## 🏗️ 핵심 화면 (Screens)

### ✅ 활용 중
- `lib/main.dart` - 앱 진입점
- `lib/screens/splash_screen.dart` - 스플래시 화면
- `lib/screens/login_screen.dart` - 로그인 화면
- `lib/screens/phone_auth_screen.dart` - 전화번호 인증
- `lib/screens/home_screen.dart` - 홈 화면 (종합 건강 검사 버튼만)
- `lib/screens/diagnosis_guide_screen.dart` - 진단 안내 화면
- `lib/screens/camera_setup_screen.dart` - 카메라 거리 설정
- `lib/screens/finger_tapping_screen.dart` - 손가락 움직임 검사
- `lib/screens/voice_analysis_screen.dart` - 음성 분석 검사
- `lib/screens/eye_tracking_screen.dart` - 시선 추적 검사
- `lib/screens/final_diagnosis_screen.dart` - 최종 진단 결과

### ❌ 사용 안함 (제거 가능)
- `lib/screens/camera_screen.dart` - 개별 카메라 기능 (홈에서 제거됨)
- `lib/screens/voice_recorder_screen.dart` - 개별 음성 녹음 (홈에서 제거됨)

## 🔧 서비스 & 유틸리티

### ✅ 활용 중
- `lib/services/api_service.dart` - API 통신
- `lib/services/permission_service.dart` - 권한 관리
- `lib/services/auth_service.dart` - 인증 서비스
- `lib/services/mediapipe_service.dart` - MediaPipe 얼굴/시선 추적
- `lib/services/face_mesh_iris_service.dart` - 홍채 추적
- `lib/services/integrated_face_eye_service.dart` - 통합 얼굴-눈 서비스

### ⚠️ 검토 필요
- `lib/services/background_removal_service.dart` - 배경 제거 (사용 여부 확인 필요)
- `lib/services/eye_tracking_service.dart` - 시선 추적 (중복 가능성)

## 🎯 모델 & 프로바이더

### ✅ 활용 중
- `lib/models/eye_tracking_models.dart` - 시선 추적 모델
- `lib/providers/auth_provider.dart` - 인증 상태 관리

## 🗂️ 진단 플로우

```
홈 화면
    ↓
진단 안내 (3단계 설명)
    ↓
[첫 번째 검사 바로 시작]
    ↓
카메라 설정
    ↓
손가락 움직임 검사
    ↓ (PD 의심시만)
음성 분석 검사
    ↓ (추가 확인 필요시만)
시선 추적 검사
    ↓
최종 진단 결과
```

## 📋 제거 권장 파일들

이제 사용하지 않는 파일들:
- `lib/screens/camera_screen.dart`
- `lib/screens/voice_recorder_screen.dart`
- 불필요한 service 파일들 (중복 기능)

## 🚀 최적화된 구조

총 **11개 핵심 화면**으로 완전한 진단 시스템 구현:
1. 스플래시 → 2. 로그인 → 3. 홈 → 4. 안내 → 5. 카메라설정 
6. 손가락검사 → 7. 음성분석 → 8. 시선추적 → 9. 최종결과