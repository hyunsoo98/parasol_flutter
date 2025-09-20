# AWS 환경변수 통합 마이그레이션 체크리스트

## 🎯 마이그레이션 목표
기존의 분산된 AWS 리소스 설정을 통일된 환경변수 시스템으로 마이그레이션하여 일관성 있고 관리 가능한 아키텍처를 구축합니다.

## 📋 마이그레이션 체크리스트

### 1. 사전 준비 ✅
- [ ] 기존 Lambda 함수 백업 완료
- [ ] 기존 DynamoDB 테이블 백업 완료
- [ ] S3 버킷 현재 상태 백업 완료
- [ ] API Gateway 엔드포인트 설정 문서화 완료
- [ ] Flutter 앱 현재 설정 백업 완료

### 2. AWS 리소스 이름 변경 🔄

#### DynamoDB 테이블 마이그레이션
**기존 → 새로운 이름**
- [ ] `eye-tracking-results` → `parasol-eye-tracking-results`
- [ ] `finger-tapping-results` → `parasol-finger-tapping-results`
- [ ] `voice-analysis-results` → `parasol-voice-analysis-results`

**마이그레이션 방법:**
```bash
# 1. 기존 테이블 백업
aws dynamodb create-backup --table-name eye-tracking-results --backup-name eye-tracking-results-backup-$(date +%Y%m%d)

# 2. 새 테이블 생성 (스크립트 사용)
./deploy_environment_variables.sh

# 3. 데이터 마이그레이션 (필요시)
aws dynamodb scan --table-name eye-tracking-results > eye-tracking-backup.json
# 새 테이블로 데이터 복사 (스크립트 필요)
```

#### S3 구조 마이그레이션
**기존 → 새로운 구조**
- [ ] `videos/finger-tapping/` → `parasol/uploads/videos/finger-tapping/`
- [ ] `audio/voice-analysis/` → `parasol/uploads/audio/voice-analysis/`
- [ ] `results/eye-tracking/` → `parasol/uploads/data/eye-tracking/`
- [ ] 새로운 결과 경로: `parasol/results/{analysis-type}/`

**마이그레이션 방법:**
```bash
# S3 구조 생성
./deploy_environment_variables.sh

# 기존 데이터 이동 (예시)
aws s3 sync s3://seoul-ht-09/videos/ s3://seoul-ht-09/parasol/uploads/videos/ --dryrun
aws s3 sync s3://seoul-ht-09/audio/ s3://seoul-ht-09/parasol/uploads/audio/ --dryrun
```

#### Lambda 함수 이름 변경
**기존 → 새로운 이름**
- [ ] `unified-upload` → `parasol-unified-upload`
- [ ] `unified-status` → `parasol-unified-status`
- [ ] `finger-process` → `parasol-finger-process`
- [ ] 새로 추가: `parasol-voice-process`

### 3. Lambda 함수 환경변수 업데이트 🔧

#### parasol-unified-upload
- [ ] `S3_BUCKET=seoul-ht-09`
- [ ] `S3_MAIN_PREFIX=parasol`
- [ ] `S3_UPLOAD_PREFIX=parasol/uploads`
- [ ] `S3_RESULTS_PREFIX=parasol/results`
- [ ] `FINGER_TAPPING_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/730335212232/finger-tapping-processing.fifo`
- [ ] `VOICE_ANALYSIS_QUEUE_URL=https://sqs.us-west-1.amazonaws.com/730335212232/voice-analysis-processing.fifo`
- [ ] `EYE_TRACKING_RESULTS_TABLE=parasol-eye-tracking-results`
- [ ] `FINGER_TAPPING_RESULTS_TABLE=parasol-finger-tapping-results`
- [ ] `VOICE_ANALYSIS_RESULTS_TABLE=parasol-voice-analysis-results`
- [ ] `MAX_FILE_SIZE_MB=100`
- [ ] `UPLOAD_TIMEOUT_SECONDS=300`

#### parasol-unified-status
- [ ] 모든 공통 환경변수 적용
- [ ] `PRESIGNED_URL_EXPIRATION_SECONDS=3600`
- [ ] `MAX_HISTORY_RECORDS=100`

#### parasol-finger-process
- [ ] 모든 공통 환경변수 적용
- [ ] `MODEL_PATH=/opt/models/best_pipeline_recall_AdaBoost.joblib`
- [ ] `MAX_PROCESSING_TIME_SECONDS=600`
- [ ] `DEFAULT_THRESHOLD=0.5`

#### parasol-voice-process (향후)
- [ ] 모든 공통 환경변수 적용
- [ ] `VOICE_MODEL_PATH=/opt/models/voice_analysis_model.joblib`
- [ ] `AUDIO_SAMPLE_RATE=16000`
- [ ] `MAX_AUDIO_DURATION_SECONDS=300`

### 4. Flutter 앱 설정 업데이트 📱

#### lib/config/aws_config.dart
- [ ] `AwsConfig` 클래스로 이름 통일
- [ ] 모든 상수값 새로운 표준으로 업데이트
- [ ] 헬퍼 메서드 추가 및 테스트
- [ ] 기존 `AWSConfig` 참조 모두 변경

#### 서비스 클래스 업데이트
- [ ] `lib/services/aws_integration_service.dart` - 새로운 AwsConfig 사용
- [ ] `lib/services/api_service.dart` - 엔드포인트 URL 업데이트
- [ ] `lib/services/auth_service.dart` - 필요시 업데이트
- [ ] 기타 AWS 관련 서비스들 점검

#### 화면 및 위젯 업데이트
- [ ] `lib/screens/upload_manager_screen.dart` - 새로운 설정 적용
- [ ] `lib/screens/analysis_status_screen.dart` - 테이블명 변경 반영
- [ ] `lib/screens/results_view_screen.dart` - 다운로드 URL 패턴 변경
- [ ] 기타 AWS 리소스 참조하는 모든 화면 점검

### 5. API Gateway 설정 확인 🌐
- [ ] 엔드포인트 URL 확인: `https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod`
- [ ] CORS 설정 확인
- [ ] Lambda 통합 연결 확인
- [ ] 새로운 함수명으로 연결 업데이트

### 6. IAM 권한 업데이트 🔐
- [ ] Lambda 실행 역할 권한 확인
- [ ] 새로운 DynamoDB 테이블 접근 권한 추가
- [ ] S3 새로운 prefix 접근 권한 확인
- [ ] SQS 큐 접근 권한 확인

### 7. 배포 및 테스트 🚀

#### 자동 배포 실행
```bash
# 환경변수 및 리소스 배포
cd aws-deployment
chmod +x deploy_environment_variables.sh
./deploy_environment_variables.sh
```

#### 수동 검증
- [ ] DynamoDB 테이블 생성 확인
- [ ] SQS 큐 생성 확인
- [ ] S3 디렉토리 구조 생성 확인
- [ ] Lambda 함수 환경변수 적용 확인

#### Flutter 앱 테스트
- [ ] 빌드 에러 없이 컴파일 확인
- [ ] API 연결 테스트
- [ ] 파일 업로드 테스트
- [ ] 분석 상태 조회 테스트
- [ ] 결과 다운로드 테스트

#### 통합 테스트
- [ ] Finger Tapping 전체 플로우 테스트
- [ ] Eye Tracking 결과 저장 테스트
- [ ] 오류 처리 시나리오 테스트
- [ ] 성능 테스트 (응답 시간, 처리량)

### 8. 마이그레이션 완료 후 정리 🧹
- [ ] 기존 DynamoDB 테이블 삭제 (데이터 이전 후)
- [ ] 기존 S3 구조 정리 (데이터 이동 후)
- [ ] 사용하지 않는 Lambda 함수 삭제
- [ ] CloudWatch 로그 그룹 정리
- [ ] 사용하지 않는 IAM 정책 정리

### 9. 문서화 및 모니터링 📝
- [ ] 새로운 아키텍처 문서 업데이트
- [ ] 운영 가이드 작성
- [ ] 모니터링 대시보드 설정
- [ ] 알람 설정 업데이트
- [ ] 백업 정책 수립

### 10. 팀 교육 및 인수인계 👥
- [ ] 개발팀 새로운 설정 교육
- [ ] 운영팀 모니터링 방법 교육
- [ ] 배포 프로세스 문서화
- [ ] 트러블슈팅 가이드 작성

## 🚨 주의사항

### 데이터 손실 방지
- 모든 마이그레이션 전에 백업 완료 필수
- 단계적 마이그레이션으로 리스크 최소화
- 롤백 계획 수립

### 서비스 중단 최소화
- 점진적 마이그레이션 방식 채택
- Blue-Green 배포 방식 고려
- 사용자 공지 및 점검 시간 설정

### 검증 및 테스트
- 각 단계별 검증 필수
- 자동화된 테스트 스위트 실행
- 실제 사용자 시나리오 테스트

## 📞 마이그레이션 지원

### 자동화 도구
- `deploy_environment_variables.sh` - 환경변수 일괄 배포
- `AWS_ENVIRONMENT_CONFIG.md` - 전체 설정 가이드
- `AWS_MIGRATION_CHECKLIST.md` - 이 체크리스트

### 수동 작업이 필요한 부분
1. DynamoDB 데이터 마이그레이션
2. S3 기존 데이터 이동
3. Lambda 함수 이름 변경
4. API Gateway 연결 업데이트

이 체크리스트를 순서대로 진행하면 안전하고 체계적인 마이그레이션을 완료할 수 있습니다! 🎉