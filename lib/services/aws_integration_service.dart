// lib/services/aws_integration_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/analysis_models.dart';
import '../config/aws_config.dart';

/// AWS Lambda와의 통합을 담당하는 서비스
class AwsIntegrationService {
  static String get _baseUrl => AwsConfig.apiGatewayBaseUrl;

  static AwsIntegrationService? _instance;
  AwsIntegrationService._internal();

  factory AwsIntegrationService() {
    _instance ??= AwsIntegrationService._internal();
    return _instance!;
  }

  /// 공통 헤더 생성
  Map<String, String> _getHeaders({bool isJson = true}) {
    final headers = <String, String>{
      if (isJson) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Flutter-App/1.0',
    };

    // AwsConfig의 기본 헤더 추가 (API Key 포함)
    headers.addAll(AwsConfig.defaultHeaders);

    return headers;
  }

  /// 파일을 AWS에 업로드하고 분석 시작
  Future<UploadResponse> uploadFile({
    required File file,
    required String analysisType,
    required String userId,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final uri = Uri.parse(AwsConfig.getUploadUrl());

      // 파일을 Base64로 인코딩
      final fileBytes = await file.readAsBytes();
      final base64Data = base64.encode(fileBytes);

      final requestBody = {
        'analysis_type': analysisType,
        'video_data': base64Data, // 또는 audio_data
        'user_id': userId,
        'parameters': parameters ?? {},
      };

      final response = await http.post(
        uri,
        headers: _getHeaders(),
        body: json.encode(requestBody),
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return UploadResponse.fromJson(responseData);
      } else {
        final errorData = json.decode(response.body);
        throw Exception('업로드 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('파일 업로드 중 오류 발생: $e');
    }
  }

  /// 시선 추적 결과를 JSON으로 업로드 (클라이언트 분석 완료 후)
  Future<UploadResponse> uploadEyeTrackingResults({
    required Map<String, dynamic> resultsData,
    required String userId,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final uri = Uri.parse(AwsConfig.getUploadUrl());

      final requestBody = {
        'analysis_type': 'eye-tracking',  // API 문서 기준으로 수정
        'results_data': resultsData,      // JSON 결과 데이터
        'user_id': userId,
        'parameters': parameters ?? {},
      };

      final response = await http.post(
        uri,
        headers: _getHeaders(),
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return UploadResponse.fromJson(responseData);
      } else {
        final errorData = json.decode(response.body);
        throw Exception('결과 업로드 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('시선 추적 결과 업로드 중 오류 발생: $e');
    }
  }

  /// 분석 상태 조회
  Future<AnalysisStatus> getAnalysisStatus(String analysisId, {String? analysisType}) async {
    try {
      final queryParams = <String, String>{};
      if (analysisType != null) {
        queryParams['analysis_type'] = analysisType;
      }

      final uri = Uri.parse('${AwsConfig.getStatusUrl()}/$analysisId').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: _getHeaders(isJson: false),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          return AnalysisStatus.fromJson(responseData['data']);
        } else {
          throw Exception('API 응답 오류: ${responseData['error']}');
        }
      } else if (response.statusCode == 404) {
        throw Exception('분석을 찾을 수 없습니다');
      } else {
        final errorData = json.decode(response.body);
        throw Exception('상태 조회 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('분석 상태 조회 중 오류 발생: $e');
    }
  }

  /// 분석 결과 조회
  Future<AnalysisResult> getAnalysisResult(String analysisId, {String? analysisType, bool generateDownloadUrl = true}) async {
    try {
      final queryParams = <String, String>{
        'download_url': generateDownloadUrl.toString(),
      };
      if (analysisType != null) {
        queryParams['analysis_type'] = analysisType;
      }

      final uri = Uri.parse('${AwsConfig.getResultsUrl()}/$analysisId').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: _getHeaders(isJson: false),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          // download_urls 처리
          final downloadUrls = <DownloadUrl>[];
          if (responseData['download_urls'] != null) {
            final urls = responseData['download_urls'] as Map<String, dynamic>;
            urls.forEach((type, url) {
              downloadUrls.add(DownloadUrl(
                type: type,
                url: url as String,
                expiresAt: DateTime.now().add(const Duration(hours: 1)), // 1시간 후 만료
              ));
            });
          }

          return AnalysisResult(
            analysisId: analysisId,
            analysisType: responseData['analysis_type'] ?? '',
            result: responseData['result'] ?? {},
            summary: responseData['summary'] ?? {},
            downloadUrls: downloadUrls,
            completedAt: DateTime.now(),
          );
        } else {
          throw Exception('API 응답 오류: ${responseData['error']}');
        }
      } else if (response.statusCode == 404) {
        throw Exception('분석 결과를 찾을 수 없습니다');
      } else {
        final errorData = json.decode(response.body);
        throw Exception('결과 조회 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('분석 결과 조회 중 오류 발생: $e');
    }
  }

  /// 사용자별 분석 기록 조회
  Future<List<AnalysisRecord>> getUserAnalyses(String userId, {String? analysisType}) async {
    try {
      final queryParams = <String, String>{
        'user_id': userId,
      };
      if (analysisType != null) {
        queryParams['analysis_type'] = analysisType;
      }

      final uri = Uri.parse(AwsConfig.getStatusUrl()).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: _getHeaders(isJson: false),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final analyses = responseData['analyses'] as List<dynamic>;
          return analyses.map((analysis) => AnalysisRecord.fromJson(analysis)).toList();
        } else {
          throw Exception('API 응답 오류: ${responseData['error']}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception('기록 조회 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('사용자 분석 기록 조회 중 오류 발생: $e');
    }
  }

  /// 서버 상태 확인
  Future<bool> checkServerHealth() async {
    try {
      final uri = Uri.parse('${AwsConfig.getApiEndpoint('/api/v1/health')}');

      print('서버 상태 확인 중: $uri');
      final response = await http.get(
        uri,
        headers: _getHeaders(isJson: false),
      ).timeout(const Duration(seconds: 10));

      print('서버 상태 응답: ${response.statusCode} - ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('서버 상태 확인 실패: $e');
      return false;
    }
  }

  /// AWS API 연결 테스트
  Future<Map<String, dynamic>> testApiConnection() async {
    try {
      print('=== AWS API 연결 테스트 시작 ===');
      print('Base URL: ${AwsConfig.apiGatewayBaseUrl}');

      // 여러 엔드포인트 테스트
      final testEndpoints = [
        {'path': '', 'name': 'Root'},
        {'path': '/api/v1/health', 'name': 'Health Check'},
        {'path': '/api/v1/upload', 'name': 'Upload Endpoint'},
        {'path': '/api/v1/status', 'name': 'Status Endpoint'},
      ];

      final results = <Map<String, dynamic>>[];

      for (final endpoint in testEndpoints) {
        try {
          final uri = Uri.parse('${AwsConfig.apiGatewayBaseUrl}${endpoint['path']}');
          final headers = _getHeaders(isJson: false);

          print('\n--- ${endpoint['name']} 테스트 ---');
          print('URL: $uri');
          print('헤더: $headers');

          final response = await http.get(uri, headers: headers)
              .timeout(const Duration(seconds: 10));

          print('응답 코드: ${response.statusCode}');
          print('응답 헤더: ${response.headers}');
          print('응답 본문: ${response.body}');

          results.add({
            'endpoint': endpoint['name'],
            'url': uri.toString(),
            'status_code': response.statusCode,
            'headers': response.headers,
            'body': response.body,
            'success': response.statusCode != 403,
          });

        } catch (e) {
          print('${endpoint['name']} 테스트 실패: $e');
          results.add({
            'endpoint': endpoint['name'],
            'error': e.toString(),
            'success': false,
          });
        }
      }

      return {
        'success': results.any((r) => r['success'] == true),
        'results': results,
      };

    } catch (e) {
      print('API 연결 테스트 전체 실패: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 분석 취소 (가능한 경우)
  Future<bool> cancelAnalysis(String analysisId) async {
    try {
      final uri = Uri.parse('${AwsConfig.getApiEndpoint('/api/v1/cancel')}/$analysisId');

      final response = await http.post(
        uri,
        headers: _getHeaders(),
        body: json.encode({}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['success'] == true;
      } else {
        return false;
      }
    } catch (e) {
      print('분석 취소 실패: $e');
      return false;
    }
  }

  /// 파일 다운로드 (Presigned URL 사용)
  Future<File> downloadFile(String downloadUrl, String localPath) async {
    try {
      final response = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        throw Exception('파일 다운로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('파일 다운로드 중 오류 발생: $e');
    }
  }

  /// 배치 업로드 (여러 파일 동시 업로드)
  Future<List<UploadResponse>> uploadMultipleFiles({
    required List<File> files,
    required String analysisType,
    required String userId,
    Map<String, dynamic>? parameters,
    Function(int completed, int total)? onProgress,
  }) async {
    final results = <UploadResponse>[];

    for (int i = 0; i < files.length; i++) {
      try {
        final result = await uploadFile(
          file: files[i],
          analysisType: analysisType,
          userId: userId,
          parameters: parameters,
        );
        results.add(result);

        // 진행률 콜백 호출
        onProgress?.call(i + 1, files.length);
      } catch (e) {
        print('파일 ${files[i].path} 업로드 실패: $e');
        // 실패한 파일도 결과에 포함 (에러 정보와 함께)
        // 실제 구현에서는 실패한 파일에 대한 정보도 포함해야 함
      }
    }

    return results;
  }

  /// 분석 재시도
  Future<UploadResponse> retryAnalysis(String analysisId) async {
    try {
      final uri = Uri.parse('${AwsConfig.getApiEndpoint('/api/v1/retry')}/$analysisId');

      final response = await http.post(
        uri,
        headers: _getHeaders(),
        body: json.encode({}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return UploadResponse.fromJson(responseData);
      } else {
        final errorData = json.decode(response.body);
        throw Exception('재시도 실패: ${errorData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      throw Exception('분석 재시도 중 오류 발생: $e');
    }
  }

  /// 시선추적 비디오를 S3에 업로드
  Future<Map<String, dynamic>> uploadEyeTrackingVideo({
    required String videoPath,
    required String fileName,
    required String sessionId,
  }) async {
    try {
      print('시선추적 비디오 S3 업로드 시작: $fileName');

      final file = File(videoPath);
      if (!await file.exists()) {
        return {'success': false, 'error': '비디오 파일이 존재하지 않습니다'};
      }

      final fileBytes = await file.readAsBytes();
      final fileSizeMB = fileBytes.length / (1024 * 1024);
      print('비디오 파일 크기: ${fileSizeMB.toStringAsFixed(2)} MB');

      // 파일이 50MB보다 크면 업로드 건너뛰기 (413 오류 방지)
      if (fileSizeMB > 50) {
        print('비디오 파일이 너무 큽니다 (${fileSizeMB.toStringAsFixed(2)} MB). 업로드를 건너뜁니다.');
        return {
          'success': false,
          'error': '비디오 파일이 너무 큽니다 (${fileSizeMB.toStringAsFixed(2)} MB). 50MB 제한.',
          'skipped': true,
        };
      }

      // 비디오 압축 또는 결과만 저장 옵션
      if (fileSizeMB > 10) {
        print('비디오 파일이 큽니다. 분석 결과만 저장합니다.');
        return {
          'success': false,
          'error': '비디오 파일이 큽니다 (${fileSizeMB.toStringAsFixed(2)} MB). 분석 결과만 저장됩니다.',
          'results_only': true,
        };
      }

      // 파일을 Base64로 인코딩
      final base64Data = base64.encode(fileBytes);

      final uri = Uri.parse(AwsConfig.getUploadUrl());

      final requestBody = {
        'analysis_type': 'eye-tracking-video', // 비디오 전용 타입
        'video_data': base64Data,
        'file_name': fileName,
        'session_id': sessionId,
        'content_type': 'video/mp4',
        'metadata': {
          'upload_source': 'flutter_app',
          'timestamp': DateTime.now().toIso8601String(),
          'file_size': fileBytes.length,
          'duration_estimate': '30-60s',
        },
      };

      final response = await http.post(
        uri,
        headers: _getHeaders(),
        body: json.encode(requestBody),
      ).timeout(const Duration(minutes: 3)); // 타임아웃 단축

      print('S3 업로드 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('S3 업로드 성공: $responseData');

        if (responseData['success'] == true) {
          return {
            'success': true,
            's3_url': responseData['s3_url'],
            'analysis_id': responseData['analysis_id'],
            'file_size': fileBytes.length,
          };
        } else {
          return {
            'success': false,
            'error': responseData['error'] ?? 'Unknown upload error',
          };
        }
      } else if (response.statusCode == 413) {
        return {
          'success': false,
          'error': '비디오 파일이 서버 제한을 초과했습니다. 분석 결과만 저장됩니다.',
          'payload_too_large': true,
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${errorData['error'] ?? 'Upload failed'}',
        };
      }
    } catch (e) {
      print('S3 업로드 예외: $e');
      return {
        'success': false,
        'error': '업로드 중 예외 발생: $e',
      };
    }
  }
}