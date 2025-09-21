// lib/config/aws_config.dart
import 'package:flutter/foundation.dart';

class AwsConfig {
  // Core Infrastructure (API 문서 기준 정정)
  static const String awsRegion = 'us-west-1';
  static const String awsAccountId = '327784329358';

  // S3 Configuration (실제 구조 기준 + Flutter 시선추적 반영)
  static const String s3Bucket = 'seoul-ht-09';
  static const String s3EyeTrackingPrefix = 'eye-tracking/results';  // JSON 결과만 저장
  static const String s3FingerTappingPrefix = 'finger-tapping';
  static const String s3VoiceAnalysisPrefix = 'voice-analysis';

  // API Gateway
  static const String apiGatewayBaseUrl = kIsWeb
    ? String.fromEnvironment('API_ENDPOINT', defaultValue: 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod')
    : 'https://c7yw4o4948.execute-api.us-west-1.amazonaws.com/prod';

  // DynamoDB Tables (API 문서 기준 정정)
  static const String analysesTable = 'analyses';
  static const String diagnosisSessionsTable = 'diagnosis_sessions';

  // Analysis Types (Flutter 시선추적 반영)
  static const String eyeTrackingType = 'eye-tracking';  // 클라이언트 분석, JSON 결과만
  static const String fingerTappingType = 'finger-tapping';  // AWS 서버 분석
  static const String voiceAnalysisType = 'voice-analysis';  // AWS 서버 분석

  // SQS Queue URLs (API 문서 기준 정정)
  static const String eyeTrackingQueueUrl = 'https://sqs.us-west-1.amazonaws.com/327784329358/eye-tracking-queue.fifo';
  static const String fingerTappingQueueUrl = 'https://sqs.us-west-1.amazonaws.com/327784329358/finger-tapping-queue.fifo';
  static const String voiceAnalysisQueueUrl = 'https://sqs.us-west-1.amazonaws.com/327784329358/voice-analysis-queue.fifo';

  // Lambda Function Names (API 문서 기준 정정)
  static const String lambdaUnifiedUpload = 'unified-upload';
  static const String lambdaUnifiedStatus = 'unified-status';
  static const String lambdaComprehensiveDiagnosis = 'comprehensive-diagnosis';
  static const String lambdaEyeTrackingProcess = 'eye-tracking-process';
  static const String lambdaFingerTappingProcess = 'finger-tapping-process';
  static const String lambdaVoiceAnalysisProcess = 'voice-analysis-process';

  // File Upload Settings
  static const int maxFileSizeMB = 100;
  static const int uploadTimeoutSeconds = 300;
  static const int presignedUrlExpirationSeconds = 3600;

  // API Endpoints
  static const String apiBasePath = '/api/v1';
  static const String authRegisterEndpoint = '/api/v1/auth/register';
  static const String authLoginEndpoint = '/api/v1/auth/login';
  static const String uploadEndpoint = '/api/v1/upload';
  static const String statusEndpoint = '/api/v1/status';
  static const String resultsEndpoint = '/api/v1/results';
  static const String diagnosisStartEndpoint = '/api/v1/diagnosis/start';
  static const String diagnosisEndpoint = '/api/v1/diagnosis';

  /// S3 Raw 파일 경로 생성 (실제 구조 + Flutter 시선추적 반영)
  static String getS3RawPath(String analysisType, String analysisId, String fileName) {
    switch (analysisType) {
      case eyeTrackingType:
        // 시선추적은 원본 파일 저장하지 않음 (Flutter 실시간 분석으로 JSON 결과만 저장)
        throw UnsupportedError('Eye tracking does not use raw file storage - uses Flutter client-side analysis');
      case fingerTappingType:
        return '$s3FingerTappingPrefix/raw/$analysisId/$fileName';
      case voiceAnalysisType:
        return '$s3VoiceAnalysisPrefix/raw/$analysisId/$fileName';
      default:
        return 'unknown/raw/$analysisId/$fileName';
    }
  }

  /// S3 Processed 파일 경로 생성 (API 문서 기준)
  static String getS3ProcessedPath(String analysisType, String analysisId, String fileName) {
    switch (analysisType) {
      case eyeTrackingType:
        return '$s3EyeTrackingPrefix/processed/$analysisId/$fileName';
      case fingerTappingType:
        return '$s3FingerTappingPrefix/processed/$analysisId/$fileName';
      case voiceAnalysisType:
        return '$s3VoiceAnalysisPrefix/processed/$analysisId/$fileName';
      default:
        return 'unknown/processed/$analysisId/$fileName';
    }
  }

  /// S3 Results 파일 경로 생성 (실제 구조 + Flutter 시선추적 반영)
  static String getS3ResultsPath(String analysisType, String analysisId, String fileName) {
    switch (analysisType) {
      case eyeTrackingType:
        // 시선추적은 이미 results 경로에 저장됨
        return '$s3EyeTrackingPrefix/$analysisId/$fileName';
      case fingerTappingType:
        return '$s3FingerTappingPrefix/results/$analysisId/$fileName';
      case voiceAnalysisType:
        return '$s3VoiceAnalysisPrefix/results/$analysisId/$fileName';
      default:
        return 'unknown/results/$analysisId/$fileName';
    }
  }

  /// 분석 타입별 표시 이름
  static String getAnalysisTypeDisplayName(String analysisType) {
    switch (analysisType) {
      case fingerTappingType:
        return '손가락 탭핑 분석';
      case voiceAnalysisType:
        return '음성 분석';
      case eyeTrackingType:
        return '시선 추적 분석';
      default:
        return analysisType;
    }
  }

  /// DynamoDB 테이블 이름 가져오기 (API 문서 기준 - 모든 분석은 analyses 테이블 사용)
  static String getDynamoDbTable(String analysisType) {
    // API 문서에 따르면 모든 분석은 단일 'analyses' 테이블을 사용
    return analysesTable;
  }

  /// 진단 세션용 DynamoDB 테이블
  static String getDiagnosisSessionsTable() {
    return diagnosisSessionsTable;
  }

  /// API 엔드포인트 생성
  static String getApiEndpoint(String path) {
    return '$apiGatewayBaseUrl$path';
  }

  // Full URL 생성 헬퍼 메서드
  static String getFullUrl(String endpoint) {
    return '$apiGatewayBaseUrl$endpoint';
  }

  // Auth URL 메서드
  static String getRegisterUrl() => getFullUrl(authRegisterEndpoint);
  static String getLoginUrl() => getFullUrl(authLoginEndpoint);

  // 통합 API URL 헬퍼 메서드
  static String getUploadUrl() => getFullUrl(uploadEndpoint);
  static String getStatusUrl() => getFullUrl(statusEndpoint);
  static String getResultsUrl() => getFullUrl(resultsEndpoint);

  // 종합 진단 URL 메서드
  static String getDiagnosisStartUrl() => getFullUrl(diagnosisStartEndpoint);
  static String getDiagnosisUrl() => getFullUrl(diagnosisEndpoint);

  // 분석 타입별 URL (모두 통합 업로드 사용)
  static String getEyeTrackingUrl() => getUploadUrl();
  static String getFingerTappingUrl() => getUploadUrl();
  static String getVoiceAnalysisUrl() => getUploadUrl();

  // HTTP API 설정 초기화
  static void initialize() {
    if (kIsWeb || kDebugMode) {
      print('=== AWS Configuration ===');
      print('Region: $awsRegion');
      print('S3 Bucket: $s3Bucket');
      print('API Gateway: $apiGatewayBaseUrl');
      print('Analyses Table: $analysesTable');
      print('Diagnosis Sessions Table: $diagnosisSessionsTable');
      print('========================');
    }
  }

  // 환경별 설정
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;

  // API Key (필요시 설정)
  static const String? apiKey = null; // API Key가 필요하면 여기에 추가

  // HTTP 헤더 설정
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'Flutter-App/1.0',
    if (apiKey != null) 'x-api-key': apiKey!,
  };

  // Amplify Configuration (호환성 유지)
  static const Map<String, dynamic> amplifyconfig = {
    "UserAgent": "aws-amplify-cli/2.0",
    "Version": "1.0",
    "api": {
      "plugins": {
        "awsAPIPlugin": {
          "parkinson": {
            "endpointType": "REST",
            "endpoint": apiGatewayBaseUrl,
            "region": awsRegion,
            "authorizationType": "NONE"
          }
        }
      }
    },
    "storage": {
      "plugins": {
        "awsS3StoragePlugin": {
          "bucket": s3Bucket,
          "region": awsRegion,
          "defaultAccessLevel": "guest"
        }
      }
    }
  };
}