// lib/services/amplify_api_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import '../models/diagnosis_result.dart';

class AmplifyApiService {
  static AmplifyApiService? _instance;
  AmplifyApiService._internal();
  factory AmplifyApiService() {
    _instance ??= AmplifyApiService._internal();
    return _instance!;
  }

  /// S3에 비디오 업로드
  Future<String> uploadVideo({
    required Uint8List videoBytes,
    required String fileName,
    String? userId,
  }) async {
    try {
      final storageKey = userId != null 
          ? 'videos/$userId/$fileName'
          : 'videos/anonymous/$fileName';
      
      final result = await Amplify.Storage.uploadData(
        data: S3DataPayload.bytes(videoBytes),
        key: storageKey,
        options: const StorageUploadDataOptions(
          accessLevel: StorageAccessLevel.private,
          metadata: <String, String>{
            'contentType': 'video/mp4',
            'source': 'parkinson-app',
          },
        ),
      ).result;
      
      safePrint('Video uploaded successfully: ${result.uploadedItem.key}');
      return result.uploadedItem.key;
    } catch (e) {
      safePrint('Video upload failed: $e');
      throw Exception('비디오 업로드 실패: $e');
    }
  }

  /// CSV 파일 업로드 (분석 결과)
  Future<String> uploadCSV({
    required String csvContent,
    required String fileName,
    String? userId,
  }) async {
    try {
      final storageKey = userId != null 
          ? 'results/$userId/$fileName'
          : 'results/anonymous/$fileName';
      
      final result = await Amplify.Storage.uploadData(
        data: S3DataPayload.string(csvContent),
        key: storageKey,
        options: const StorageUploadDataOptions(
          accessLevel: StorageAccessLevel.private,
          metadata: <String, String>{
            'contentType': 'text/csv',
            'source': 'parkinson-app',
          },
        ),
      ).result;
      
      safePrint('CSV uploaded successfully: ${result.uploadedItem.key}');
      return result.uploadedItem.key;
    } catch (e) {
      safePrint('CSV upload failed: $e');
      throw Exception('CSV 업로드 실패: $e');
    }
  }

  /// Lambda를 통한 시선 추적 분석
  Future<EyeTrackingResult> analyzeEyeTracking({
    required String videoKey,
    int step = 2,
    double vppThresh = 0.06,
    double blinkThresh = 0.18,
    int maxFrames = 12000,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/eye/process',
        body: HttpPayload.json({
          'videoKey': videoKey,
          'step': step,
          'vpp_thresh': vppThresh,
          'blink_thresh': blinkThresh,
          'max_frames': maxFrames,
          'save': true,
          'return_overlay': false,
        }),
      );

      final response = await Amplify.API.post(request).response;
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.decodeBody());
        return EyeTrackingResult.fromJson(data);
      } else {
        throw Exception('시선 추적 API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      safePrint('Eye tracking analysis failed: $e');
      throw Exception('시선 추적 분석 실패: $e');
    }
  }

  /// Lambda를 통한 음성 분석
  Future<Map<String, dynamic>> analyzeSpeech({
    required Map<String, dynamic> speechData,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/speech/predict',
        body: HttpPayload.json(speechData),
      );

      final response = await Amplify.API.post(request).response;
      
      if (response.statusCode == 200) {
        return json.decode(response.decodeBody());
      } else {
        throw Exception('음성 분석 API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      safePrint('Speech analysis failed: $e');
      throw Exception('음성 분석 실패: $e');
    }
  }

  /// Lambda를 통한 손가락 태핑 분석
  Future<Map<String, dynamic>> analyzeFingerTapping({
    required Map<String, dynamic> fingerData,
  }) async {
    try {
      final request = RESTRequest(
        method: RESTMethod.post,
        path: '/finger/predict',
        body: HttpPayload.json(fingerData),
      );

      final response = await Amplify.API.post(request).response;
      
      if (response.statusCode == 200) {
        return json.decode(response.decodeBody());
      } else {
        throw Exception('손가락 태핑 분석 API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      safePrint('Finger tapping analysis failed: $e');
      throw Exception('손가락 태핑 분석 실패: $e');
    }
  }

  /// 헬스 체크
  Future<bool> checkHealth() async {
    try {
      final request = RESTRequest(
        method: RESTMethod.get,
        path: '/health',
      );

      final response = await Amplify.API.get(request).response;
      return response.statusCode == 200;
    } catch (e) {
      safePrint('Health check failed: $e');
      return false;
    }
  }

  /// S3에서 파일 다운로드
  Future<S3GetDataResult> downloadFile(String key) async {
    try {
      final result = await Amplify.Storage.downloadData(
        key: key,
        options: const StorageDownloadDataOptions(
          accessLevel: StorageAccessLevel.private,
        ),
      ).result;
      
      return result;
    } catch (e) {
      safePrint('File download failed: $e');
      throw Exception('파일 다운로드 실패: $e');
    }
  }

  /// 사용자의 분석 결과 목록 조회
  Future<List<StorageItem>> listUserFiles({
    required String userId,
    String prefix = 'results/',
  }) async {
    try {
      final result = await Amplify.Storage.list(
        path: StoragePath.fromString('$prefix$userId/'),
        options: const StorageListOptions(
          accessLevel: StorageAccessLevel.private,
          pageSize: 100,
        ),
      ).result;
      
      return result.items;
    } catch (e) {
      safePrint('List files failed: $e');
      throw Exception('파일 목록 조회 실패: $e');
    }
  }
}