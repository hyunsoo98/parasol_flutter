// lib/config/aws_config.dart
import 'package:flutter/foundation.dart';

class AWSConfig {
  // API Gateway 엔드포인트 - 실제 배포된 값으로 교체 필요
  static const String apiEndpoint = kIsWeb 
    ? String.fromEnvironment('API_ENDPOINT', defaultValue: 'https://your-api-id.execute-api.us-west-1.amazonaws.com/dev')
    : 'https://your-api-id.execute-api.us-west-1.amazonaws.com/dev';
    
  // S3 버킷 이름 - 실제 버킷명
  static const String s3Bucket = kIsWeb
    ? String.fromEnvironment('S3_BUCKET', defaultValue: 'seoul-ht-09')
    : 'seoul-ht-09';
    
  // AWS 리전 (AWS_ 접두사 제거)
  static const String region = kIsWeb
    ? String.fromEnvironment('REGION', defaultValue: 'us-west-1')
    : 'us-west-1';

  // API 엔드포인트들
  static const String uploadEndpoint = '/api/v1/upload';
  static const String analyzeEyeTrackingEndpoint = '/api/v1/analyze/eye-tracking';
  static const String analyzeVoiceEndpoint = '/api/v1/analyze/voice';
  static const String analyzeFingerTappingEndpoint = '/api/v1/analyze/finger-tapping';
  static const String resultsEndpoint = '/api/v1/results';
  static const String healthEndpoint = '/api/v1/health';

  // Full URL 생성 헬퍼 메서드
  static String getFullUrl(String endpoint) {
    return '$apiEndpoint$endpoint';
  }

  // 환경 변수 초기화 (웹 전용)
  static void initialize() {
    if (kIsWeb) {
      print('AWS Config initialized for web:');
      print('API Endpoint: $apiEndpoint');
      print('S3 Bucket: $s3Bucket');
      print('Region: $region');
    }
  }

  // 개발/프로덕션 환경 구분
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;
}