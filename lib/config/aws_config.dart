// lib/config/aws_config.dart
import 'package:flutter/foundation.dart';

class AWSConfig {
  // 새로운 parasol-api API Gateway 엔드포인트
  static const String apiEndpoint = kIsWeb
    ? String.fromEnvironment('API_ENDPOINT', defaultValue: 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod')
    : 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';

  // S3 버킷은 서버 사이드에서만 사용 (클라이언트 불필요)
  static const String s3Bucket = 'seoul-ht-09';  // 참조용만

  // AWS 리전 정보 (참조용만)
  static const String region = 'us-west-1';

  // 새로운 통합 API 엔드포인트들

  // API v1 base path
  static const String apiBasePath = '/api/v1';

  // Auth 엔드포인트
  static const String authRegisterEndpoint = '/api/v1/auth/register';
  static const String authLoginEndpoint = '/api/v1/auth/login';

  // 분석 엔드포인트 (통합)
  static const String uploadEndpoint = '/api/v1/upload';
  static const String statusEndpoint = '/api/v1/status';
  static const String resultsEndpoint = '/api/v1/results';

  // 종합 진단 엔드포인트
  static const String diagnosisStartEndpoint = '/api/v1/diagnosis/start';
  static const String diagnosisEndpoint = '/api/v1/diagnosis';

  // Full URL 생성 헬퍼 메서드
  static String getFullUrl(String endpoint) {
    return '$apiEndpoint$endpoint';
  }

  // Auth URL 메서드
  static String getRegisterUrl() => getFullUrl(authRegisterEndpoint);
  static String getLoginUrl() => getFullUrl(authLoginEndpoint);

  // 통합 API URL 헬퍼 메서드 (HTTP만 사용)
  static String getUploadUrl() => getFullUrl(uploadEndpoint);
  static String getStatusUrl() => getFullUrl(statusEndpoint);
  static String getResultsUrl() => getFullUrl(resultsEndpoint);

  // 종합 진단 URL 메서드
  static String getDiagnosisStartUrl() => getFullUrl(diagnosisStartEndpoint);
  static String getDiagnosisUrl() => getFullUrl(diagnosisEndpoint);

  // 분석 타입별 URL (모두 통합 업로드 사용)
  static String getEyeTrackingUrl() => getUploadUrl();  // analysis_type: 'eye-tracking'
  static String getFingerTappingUrl() => getUploadUrl();  // analysis_type: 'finger-tapping'
  static String getVoiceAnalysisUrl() => getUploadUrl();  // analysis_type: 'voice-analysis'

  // HTTP API 설정 초기화 (웹 전용)
  static void initialize() {
    if (kIsWeb) {
      print('HTTP API Config initialized:');
      print('API Endpoint: $apiEndpoint');
      print('Region: $region');
    }
  }

  // 개발/프로덕션 환경 구분
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;

  // HTTP 헤더 설정
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}