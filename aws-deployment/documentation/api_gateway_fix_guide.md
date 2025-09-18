# 🔧 API Gateway 권한 오류 해결 가이드

현재 오류: API Gateway ID `c7yw4o4948`에서 `/api/v1/results` POST 메서드가 Lambda와 연결되지 않음

## 🎯 문제 분석

**현재 상황:**
- API Gateway ID: `c7yw4o4948`
- 문제 경로: `/api/v1/results` (POST)
- Lambda 함수: `parasol-eye-tracking`
- 문제: 경로와 메서드가 Lambda 함수와 연결되지 않음

## 📋 해결 방법 (AWS 콘솔)

### 1단계: API Gateway 콘솔 확인

1. **AWS 콘솔 → API Gateway 서비스 접속**
2. **API ID `c7yw4o4948` 클릭**
3. **현재 리소스 구조 확인**

### 2단계: 올바른 리소스 구조 확인

**현재 Lambda Status 함수가 처리하는 경로:**
```
GET /status/{analysis_id}     # 특정 분석 상태 조회
GET /status?user_id=xxx       # 사용자별 분석 목록
```

**하지만 오류는 다른 경로에서 발생:**
```
POST /api/v1/results          # ← 이 경로가 문제
```

### 3단계: 해결 방안 선택

#### 옵션 1: API Gateway에서 올바른 경로 생성

1. **리소스 생성**
   - 루트(/) 선택
   - "작업" → "리소스 생성"
   - 리소스 이름: `api`

2. **v1 리소스 생성**
   - `/api` 리소스 선택
   - "작업" → "리소스 생성" 
   - 리소스 이름: `v1`

3. **results 리소스 생성**
   - `/api/v1` 리소스 선택
   - "작업" → "리소스 생성"
   - 리소스 이름: `results`

4. **POST 메서드 생성**
   - `/api/v1/results` 리소스 선택
   - "작업" → "메서드 생성"
   - "POST" 선택
   - Lambda 함수: `parasol-eye-tracking` 연결

#### 옵션 2: Flutter 앱의 API 호출 경로 수정 (더 간단)

현재 Flutter 앱에서 잘못된 경로를 호출하고 있을 수 있습니다.

### 4단계: Flutter 앱 확인 및 수정

#### 현재 Lambda Status 함수 경로:
```
GET /status/{analysis_id}
GET /status?user_id=xxx  
```

#### Flutter 서비스 파일 확인:
`lib/services/aws_async_eye_tracking_service.dart`에서:

**잘못된 호출 (만약 있다면):**
```dart
Uri.parse('$_baseUrl/api/v1/results')  // ❌ 잘못된 경로
```

**올바른 호출:**
```dart
Uri.parse('$_baseUrl/status/$analysisId')        // ✅ 특정 분석 상태
Uri.parse('$_baseUrl/status?user_id=$userId')    // ✅ 사용자별 목록
```

## 🔍 현재 설정 확인 방법

### 1. API Gateway 리소스 구조 확인
1. **API Gateway 콘솔 → API `c7yw4o4948`**
2. **좌측 "리소스" 메뉴에서 현재 구조 확인**
3. **다음 경로들이 있는지 확인:**
   - `/upload` (POST)
   - `/status` (GET)
   - `/status/{analysis_id}` (GET)

### 2. Lambda 함수 확인  
1. **Lambda 콘솔 → `parasol-eye-tracking` 함수**
2. **"구성" → "트리거" 탭에서 API Gateway 연결 상태 확인**

### 3. Flutter 앱 호출 경로 확인
현재 Flutter에서 어떤 URL로 API를 호출하는지 확인

## 🚀 권장 해결 방안

### 빠른 해결 (권장):

1. **Flutter 앱에서 올바른 경로 사용**
   ```dart
   // 분석 상태 조회
   final response = await http.get(
     Uri.parse('$_baseUrl/status/$analysisId'),
   );
   
   // 사용자별 목록 조회  
   final response = await http.get(
     Uri.parse('$_baseUrl/status?user_id=$userId'),
   );
   ```

2. **API Gateway에서 필요없는 경로 제거**
   - `/api/v1/results` 경로가 불필요하다면 삭제

### 완전한 해결:

1. **API Gateway에서 올바른 리소스 구조 생성**
2. **모든 경로에 Lambda 함수 연결**
3. **CORS 설정**
4. **API 재배포**

## 📞 즉시 테스트 방법

### API Gateway 테스트
1. **API Gateway 콘솔에서 각 메서드 선택**
2. **"테스트" 버튼 클릭**
3. **테스트 실행하여 Lambda 연결 확인**

### Flutter 앱 테스트
```dart
// 디버그 모드에서 API 호출 URL 출력
print('API URL: $_baseUrl/status/$analysisId');
```

## 🎯 최종 확인사항

- [ ] API Gateway에 `/upload`, `/status`, `/status/{id}` 경로 존재
- [ ] 각 경로가 올바른 Lambda 함수와 연결됨
- [ ] CORS 설정됨
- [ ] API 배포됨
- [ ] Flutter 앱이 올바른 경로 호출
- [ ] Lambda 함수 권한 설정 완료

대부분의 경우 **Flutter 앱에서 잘못된 경로를 호출**하는 것이 원인입니다. 먼저 Flutter 코드를 확인해보세요! 🔍