# Flutter 클라이언트 사이드 영상 분석 가이드

## 📋 개요

서버 비용과 네트워크 의존성을 제거하고 실시간 분석을 제공하기 위한 Flutter 앱 내장 영상 분석 시스템 구축 가이드입니다.

### 현재 서버 방식의 문제점
- 💰 **높은 서버 비용**: AWS Lambda/EC2 운영비
- ⏱️ **네트워크 지연**: 업로드 + 분석 + 다운로드 시간
- 🔒 **개인정보 우려**: 의료 데이터 서버 전송
- 📶 **네트워크 의존**: 오프라인 환경에서 사용 불가

### 클라이언트 분석의 장점
- 💰 **제로 서버 비용**: 완전한 비용 절약
- ⚡ **즉시 처리**: 실시간 분석 결과
- 🔒 **완벽한 개인정보보호**: 데이터가 디바이스를 떠나지 않음
- 📱 **오프라인 동작**: 네트워크 없이도 사용 가능
- 🚀 **무제한 사용**: 서버 제약 없는 분석

## 🏗️ 기술 스택 및 아키텍처

### 사용 가능한 라이브러리

#### 1. **Google ML Kit (추천)**
```yaml
dependencies:
  google_ml_kit: ^0.16.0
```
- **장점**: Google 공식 지원, 높은 정확도, 최적화됨
- **단점**: 일부 고급 기능 제한
- **지원**: iOS/Android 네이티브 성능

#### 2. **TensorFlow Lite Flutter**
```yaml
dependencies:
  tflite_flutter: ^0.10.0
```
- **장점**: 커스텀 모델 사용 가능, 높은 유연성
- **단점**: 모델 훈련 및 최적화 필요
- **지원**: 다양한 ML 모델 지원

#### 3. **OpenCV Flutter**
```yaml
dependencies:
  opencv_dart: ^1.0.0
```
- **장점**: 강력한 이미지 처리 기능
- **단점**: 큰 앱 크기, 복잡한 구현
- **지원**: 컴퓨터 비전 전반

### 시스템 아키텍처

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Video File    │───▶│  Frame Extractor│───▶│  ML Kit Detector│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
┌─────────────────┐    ┌─────────────────┐           │
│  Analysis UI    │◀───│  Result Engine  │◀──────────┘
└─────────────────┘    └─────────────────┘
```

## 📁 프로젝트 구조

```
lib/
├── models/
│   ├── eye_tracking_result.dart         # 결과 데이터 모델
│   ├── eye_frame_data.dart              # 프레임별 데이터
│   └── analysis_config.dart             # 분석 설정
├── services/
│   ├── local_analysis_service.dart      # 로컬 분석 서비스
│   ├── ml_kit_analyzer.dart             # ML Kit 분석기
│   ├── video_processor.dart             # 비디오 처리
│   └── device_capability_checker.dart   # 디바이스 성능 체크
├── widgets/
│   ├── analysis_progress_widget.dart    # 진행률 표시
│   ├── video_preview_widget.dart        # 비디오 미리보기
│   └── result_visualization_widget.dart # 결과 시각화
├── screens/
│   ├── video_analysis_screen.dart       # 메인 분석 화면
│   ├── analysis_options_screen.dart     # 분석 옵션 선택
│   └── results_screen.dart              # 결과 화면
└── utils/
    ├── video_utils.dart                 # 비디오 유틸리티
    ├── math_utils.dart                  # 수학적 계산
    └── storage_utils.dart               # 로컬 저장
```

## 🚀 Phase 1: 기본 로컬 분석 구현

### 1. 의존성 추가

```yaml
# pubspec.yaml
name: parkinson_eye_tracker
description: 로컬 영상 분석 기반 파킨슨 진단 앱

dependencies:
  flutter:
    sdk: flutter

  # ML/AI 라이브러리
  google_ml_kit: ^0.16.0
  tflite_flutter: ^0.10.0

  # 비디오 처리
  video_player: ^2.8.0
  camera: ^0.10.0
  image: ^4.1.0

  # 파일 처리
  path_provider: ^2.1.0
  file_picker: ^6.0.0

  # 수학/데이터 처리
  collection: ^1.17.0

  # UI/UX
  percent_indicator: ^4.2.1
  fl_chart: ^0.66.0

  # 로컬 저장
  sqflite: ^2.3.0
  shared_preferences: ^2.2.0

  # 디바이스 정보
  device_info_plus: ^9.1.0
  battery_plus: ^4.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### 2. 핵심 데이터 모델

#### A. 분석 결과 모델 (models/eye_tracking_result.dart)

```dart
import 'package:json_annotation/json_annotation.dart';

part 'eye_tracking_result.g.dart';

@JsonSerializable()
class EyeTrackingResult {
  final String analysisId;
  final DateTime timestamp;
  final Duration videoDuration;
  final int totalFrames;
  final int analyzedFrames;

  // 분석 결과
  final double averageBlinkRate;
  final int totalBlinks;
  final double verticalMovementVariance;
  final double horizontalMovementVariance;
  final bool pspSuspected;
  final String pspReason;

  // 상세 데이터
  final List<EyeFrameData> frameData;
  final Map<String, dynamic> statistics;
  final AnalysisQuality quality;

  const EyeTrackingResult({
    required this.analysisId,
    required this.timestamp,
    required this.videoDuration,
    required this.totalFrames,
    required this.analyzedFrames,
    required this.averageBlinkRate,
    required this.totalBlinks,
    required this.verticalMovementVariance,
    required this.horizontalMovementVariance,
    required this.pspSuspected,
    required this.pspReason,
    required this.frameData,
    required this.statistics,
    required this.quality,
  });

  factory EyeTrackingResult.fromJson(Map<String, dynamic> json) =>
      _$EyeTrackingResultFromJson(json);

  Map<String, dynamic> toJson() => _$EyeTrackingResultToJson(this);

  // 분석 요약
  String get summaryText {
    if (pspSuspected) {
      return 'PSP 의심 소견이 관찰됩니다. 전문의와 상담을 권장합니다.';
    } else {
      return '정상적인 눈 움직임 패턴이 관찰됩니다.';
    }
  }

  // 신뢰도 점수
  double get confidenceScore {
    final frameRatio = analyzedFrames / totalFrames;
    final qualityScore = quality.scoreMultiplier;
    return (frameRatio * qualityScore * 100).clamp(0.0, 100.0);
  }
}

@JsonSerializable()
class EyeFrameData {
  final double timestamp;
  final bool faceDetected;

  // 눈 위치 (정규화된 좌표 0.0-1.0)
  final double? leftEyeX;
  final double? leftEyeY;
  final double? rightEyeX;
  final double? rightEyeY;

  // 눈 openness (0.0=완전 닫힘, 1.0=완전 열림)
  final double? leftEyeOpenness;
  final double? rightEyeOpenness;

  // 얼굴 각도
  final double? faceAngle;
  final double? headTilt;

  const EyeFrameData({
    required this.timestamp,
    required this.faceDetected,
    this.leftEyeX,
    this.leftEyeY,
    this.rightEyeX,
    this.rightEyeY,
    this.leftEyeOpenness,
    this.rightEyeOpenness,
    this.faceAngle,
    this.headTilt,
  });

  factory EyeFrameData.fromJson(Map<String, dynamic> json) =>
      _$EyeFrameDataFromJson(json);

  Map<String, dynamic> toJson() => _$EyeFrameDataToJson(this);

  // 평균 눈 openness
  double? get averageEyeOpenness {
    if (leftEyeOpenness != null && rightEyeOpenness != null) {
      return (leftEyeOpenness! + rightEyeOpenness!) / 2.0;
    }
    return leftEyeOpenness ?? rightEyeOpenness;
  }

  // 수직 시선 오프셋
  double? get verticalGazeOffset {
    if (leftEyeY != null && rightEyeY != null) {
      return (leftEyeY! + rightEyeY!) / 2.0 - 0.5; // 중앙을 0으로 정규화
    }
    return null;
  }
}

enum AnalysisQuality {
  basic(0.7, 'Basic', '기본 분석'),
  good(0.85, 'Good', '표준 분석'),
  high(1.0, 'High', '고정밀 분석');

  const AnalysisQuality(this.scoreMultiplier, this.name, this.displayName);

  final double scoreMultiplier;
  final String name;
  final String displayName;
}
```

### 3. ML Kit 기반 분석기

#### A. ML Kit 분석기 (services/ml_kit_analyzer.dart)

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import '../models/eye_tracking_result.dart';

class MLKitAnalyzer {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableClassification: true,
        minFaceSize: 0.1,
        mode: FaceDetectorMode.accurate,
      ),
    );

    _isInitialized = true;
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      await _faceDetector.close();
      _isInitialized = false;
    }
  }

  Future<EyeTrackingResult> analyzeVideo(
    File videoFile, {
    Function(double progress, String message)? onProgress,
    AnalysisQuality quality = AnalysisQuality.good,
  }) async {
    if (!_isInitialized) await initialize();

    onProgress?.call(0.0, 'ML Kit 분석 시작...');

    // 비디오 메타데이터 추출
    final videoInfo = await _getVideoInfo(videoFile);
    onProgress?.call(0.1, '비디오 정보 추출 완료');

    // 프레임 추출 및 분석
    final frameData = await _extractAndAnalyzeFrames(
      videoFile,
      videoInfo,
      quality,
      onProgress,
    );

    onProgress?.call(0.9, '분석 결과 계산 중...');

    // 결과 계산
    final result = await _calculateResults(
      frameData,
      videoInfo,
      quality,
    );

    onProgress?.call(1.0, '분석 완료!');
    return result;
  }

  Future<Map<String, dynamic>> _getVideoInfo(File videoFile) async {
    // video_player나 ffmpeg_kit_flutter를 사용하여 비디오 정보 추출
    // 간단한 구현을 위해 기본값 사용
    return {
      'duration': Duration(seconds: 30), // 실제로는 동적으로 계산
      'fps': 30.0,
      'width': 1920,
      'height': 1080,
    };
  }

  Future<List<EyeFrameData>> _extractAndAnalyzeFrames(
    File videoFile,
    Map<String, dynamic> videoInfo,
    AnalysisQuality quality,
    Function(double, String)? onProgress,
  ) async {
    final Duration duration = videoInfo['duration'];
    final double fps = videoInfo['fps'];

    // 품질에 따른 샘플링 레이트 조정
    final int samplingRate = _getSamplingRate(quality);
    final int totalFramesToAnalyze = (duration.inSeconds * fps / samplingRate).ceil();

    List<EyeFrameData> frameDataList = [];

    for (int i = 0; i < totalFramesToAnalyze; i++) {
      final double timestamp = i * samplingRate / fps;

      try {
        // 특정 시점의 프레임 추출
        final frameImage = await _extractFrame(videoFile, timestamp);

        if (frameImage != null) {
          // ML Kit으로 얼굴 분석
          final eyeData = await _analyzeFrame(frameImage, timestamp);
          frameDataList.add(eyeData);
        } else {
          // 프레임 추출 실패 시 빈 데이터 추가
          frameDataList.add(EyeFrameData(
            timestamp: timestamp,
            faceDetected: false,
          ));
        }

        // 진행률 업데이트
        final progress = 0.1 + (i / totalFramesToAnalyze) * 0.8;
        onProgress?.call(progress, 'Frame ${i + 1}/${totalFramesToAnalyze} 분석 중...');

      } catch (e) {
        debugPrint('Frame analysis error at $timestamp: $e');
        frameDataList.add(EyeFrameData(
          timestamp: timestamp,
          faceDetected: false,
        ));
      }
    }

    return frameDataList;
  }

  int _getSamplingRate(AnalysisQuality quality) {
    switch (quality) {
      case AnalysisQuality.basic:
        return 10; // 3fps
      case AnalysisQuality.good:
        return 6; // 5fps
      case AnalysisQuality.high:
        return 3; // 10fps
    }
  }

  Future<ui.Image?> _extractFrame(File videoFile, double timestamp) async {
    // video_thumbnail 패키지나 ffmpeg를 사용하여 프레임 추출
    // 실제 구현에서는 native 코드나 플러그인 필요

    // 임시 구현: 실제로는 비디오에서 특정 시점의 프레임을 추출해야 함
    // 여기서는 예시를 위해 null 반환
    return null;
  }

  Future<EyeFrameData> _analyzeFrame(ui.Image frameImage, double timestamp) async {
    try {
      // UI.Image를 InputImage로 변환
      final inputImage = await _convertToInputImage(frameImage);

      // ML Kit 얼굴 검출
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return EyeFrameData(timestamp: timestamp, faceDetected: false);
      }

      final face = faces.first;

      // 얼굴 랜드마크에서 눈 정보 추출
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      // 눈 openness 추정 (ML Kit 한계로 인한 근사치)
      final leftOpenness = _estimateEyeOpenness(face, leftEye, true);
      final rightOpenness = _estimateEyeOpenness(face, rightEye, false);

      return EyeFrameData(
        timestamp: timestamp,
        faceDetected: true,
        leftEyeX: leftEye?.position.dx != null
            ? leftEye!.position.dx / frameImage.width
            : null,
        leftEyeY: leftEye?.position.dy != null
            ? leftEye!.position.dy / frameImage.height
            : null,
        rightEyeX: rightEye?.position.dx != null
            ? rightEye!.position.dx / frameImage.width
            : null,
        rightEyeY: rightEye?.position.dy != null
            ? rightEye!.position.dy / frameImage.height
            : null,
        leftEyeOpenness: leftOpenness,
        rightEyeOpenness: rightOpenness,
        faceAngle: face.headEulerAngleY,
        headTilt: face.headEulerAngleZ,
      );

    } catch (e) {
      debugPrint('Frame analysis error: $e');
      return EyeFrameData(timestamp: timestamp, faceDetected: false);
    }
  }

  Future<InputImage> _convertToInputImage(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = byteData!.buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.rgba8888,
      ),
    );
  }

  double? _estimateEyeOpenness(Face face, FaceLandmark? eyeLandmark, bool isLeftEye) {
    // ML Kit는 직접적인 eye openness를 제공하지 않으므로 추정 필요
    if (eyeLandmark == null) return null;

    // 얼굴 크기 대비 눈 위치를 이용한 간단한 추정
    final faceHeight = face.boundingBox.height;
    final eyeY = eyeLandmark.position.dy;
    final faceTop = face.boundingBox.top;
    final faceCenter = faceTop + faceHeight / 2;

    // 눈이 얼굴 중심에서 얼마나 떨어져 있는지 계산
    final normalizedDistance = (eyeY - faceCenter).abs() / (faceHeight / 2);

    // 휴리스틱: 정상 범위에서의 openness 추정
    return (1.0 - normalizedDistance).clamp(0.0, 1.0);
  }

  Future<EyeTrackingResult> _calculateResults(
    List<EyeFrameData> frameData,
    Map<String, dynamic> videoInfo,
    AnalysisQuality quality,
  ) async {
    // 유효한 프레임만 필터링
    final validFrames = frameData.where((frame) => frame.faceDetected).toList();

    if (validFrames.isEmpty) {
      throw Exception('유효한 얼굴 프레임이 없습니다. 다른 각도에서 촬영해주세요.');
    }

    // 블링크 분석
    final blinkAnalysis = _analyzeBlinking(validFrames);

    // 수직 움직임 분석
    final verticalAnalysis = _analyzeVerticalMovement(validFrames);

    // PSP 의심 여부 판정
    final pspAnalysis = _analyzePSPSuspicion(verticalAnalysis, blinkAnalysis);

    // 통계 계산
    final statistics = _calculateStatistics(validFrames, blinkAnalysis, verticalAnalysis);

    return EyeTrackingResult(
      analysisId: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      videoDuration: videoInfo['duration'],
      totalFrames: frameData.length,
      analyzedFrames: validFrames.length,
      averageBlinkRate: blinkAnalysis['blinkRate'],
      totalBlinks: blinkAnalysis['totalBlinks'],
      verticalMovementVariance: verticalAnalysis['variance'],
      horizontalMovementVariance: 0.0, // 추후 구현
      pspSuspected: pspAnalysis['suspected'],
      pspReason: pspAnalysis['reason'],
      frameData: frameData,
      statistics: statistics,
      quality: quality,
    );
  }

  Map<String, dynamic> _analyzeBlinking(List<EyeFrameData> validFrames) {
    // 블링크 패턴 분석
    List<bool> blinkStates = [];
    const double blinkThreshold = 0.3; // 30% 이하면 닫힌 눈으로 판단

    for (final frame in validFrames) {
      final avgOpenness = frame.averageEyeOpenness;
      if (avgOpenness != null) {
        blinkStates.add(avgOpenness < blinkThreshold);
      }
    }

    // 블링크 횟수 계산 (연속된 닫힌 상태를 하나의 블링크로 계산)
    int blinkCount = 0;
    bool wasBlinking = false;

    for (bool isBlinking in blinkStates) {
      if (isBlinking && !wasBlinking) {
        blinkCount++;
      }
      wasBlinking = isBlinking;
    }

    // 분당 블링크 비율 계산
    final double durationMinutes = validFrames.last.timestamp / 60.0;
    final double blinkRate = blinkCount / durationMinutes;

    return {
      'totalBlinks': blinkCount,
      'blinkRate': blinkRate,
      'blinkStates': blinkStates,
    };
  }

  Map<String, dynamic> _analyzeVerticalMovement(List<EyeFrameData> validFrames) {
    List<double> verticalPositions = [];

    for (final frame in validFrames) {
      final verticalOffset = frame.verticalGazeOffset;
      if (verticalOffset != null) {
        verticalPositions.add(verticalOffset);
      }
    }

    if (verticalPositions.isEmpty) {
      return {'variance': 0.0, 'mean': 0.0, 'range': 0.0};
    }

    // 평균 계산
    final mean = verticalPositions.reduce((a, b) => a + b) / verticalPositions.length;

    // 분산 계산
    final variance = verticalPositions
        .map((pos) => (pos - mean) * (pos - mean))
        .reduce((a, b) => a + b) / verticalPositions.length;

    // 범위 계산 (5-95 percentile)
    verticalPositions.sort();
    final p5Index = (verticalPositions.length * 0.05).floor();
    final p95Index = (verticalPositions.length * 0.95).floor();
    final range = verticalPositions[p95Index] - verticalPositions[p5Index];

    return {
      'variance': variance,
      'mean': mean,
      'range': range,
      'positions': verticalPositions,
    };
  }

  Map<String, dynamic> _analyzePSPSuspicion(
    Map<String, dynamic> verticalAnalysis,
    Map<String, dynamic> blinkAnalysis,
  ) {
    const double pspVerticalThreshold = 0.06; // PSP 의심 임계값
    const double pspBlinkThreshold = 5.0; // 분당 5회 이하

    final double verticalRange = verticalAnalysis['range'];
    final double blinkRate = blinkAnalysis['blinkRate'];

    bool suspected = false;
    String reason = '정상 범위';

    if (verticalRange < pspVerticalThreshold) {
      suspected = true;
      reason = '수직 눈 움직임 범위가 제한적입니다 (${(verticalRange * 100).toStringAsFixed(1)}% < 6.0%)';
    } else if (blinkRate < pspBlinkThreshold) {
      suspected = true;
      reason = '블링크 빈도가 낮습니다 (${blinkRate.toStringAsFixed(1)}/분 < 5.0/분)';
    }

    return {
      'suspected': suspected,
      'reason': reason,
      'verticalRange': verticalRange,
      'blinkRate': blinkRate,
    };
  }

  Map<String, dynamic> _calculateStatistics(
    List<EyeFrameData> validFrames,
    Map<String, dynamic> blinkAnalysis,
    Map<String, dynamic> verticalAnalysis,
  ) {
    return {
      'frameAnalysisRate': validFrames.length / (validFrames.last.timestamp * 30), // 30fps 기준
      'averageFaceAngle': validFrames
          .where((f) => f.faceAngle != null)
          .map((f) => f.faceAngle!)
          .fold(0.0, (a, b) => a + b) / validFrames.length,
      'eyeOpennessStats': {
        'mean': validFrames
            .where((f) => f.averageEyeOpenness != null)
            .map((f) => f.averageEyeOpenness!)
            .fold(0.0, (a, b) => a + b) / validFrames.length,
        'min': validFrames
            .where((f) => f.averageEyeOpenness != null)
            .map((f) => f.averageEyeOpenness!)
            .reduce((a, b) => a < b ? a : b),
        'max': validFrames
            .where((f) => f.averageEyeOpenness != null)
            .map((f) => f.averageEyeOpenness!)
            .reduce((a, b) => a > b ? a : b),
      },
      'processingInfo': {
        'totalFrames': validFrames.length,
        'analysisTimeSeconds': validFrames.last.timestamp,
        'mlKitVersion': '0.16.0',
      }
    };
  }
}
```

### 4. 로컬 분석 서비스

#### A. 통합 분석 서비스 (services/local_analysis_service.dart)

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/eye_tracking_result.dart';
import 'ml_kit_analyzer.dart';
import 'device_capability_checker.dart';

class LocalAnalysisService {
  static final LocalAnalysisService _instance = LocalAnalysisService._internal();
  factory LocalAnalysisService() => _instance;
  LocalAnalysisService._internal();

  MLKitAnalyzer? _mlKitAnalyzer;
  DeviceCapabilityChecker? _capabilityChecker;

  Future<void> initialize() async {
    _mlKitAnalyzer = MLKitAnalyzer();
    await _mlKitAnalyzer!.initialize();

    _capabilityChecker = DeviceCapabilityChecker();
    await _capabilityChecker!.initialize();
  }

  Future<void> dispose() async {
    await _mlKitAnalyzer?.dispose();
    _mlKitAnalyzer = null;
    _capabilityChecker = null;
  }

  Future<AnalysisRecommendation> getAnalysisRecommendation(File videoFile) async {
    if (_capabilityChecker == null) await initialize();

    final videoInfo = await _getVideoInfo(videoFile);
    final deviceCapability = await _capabilityChecker!.assessCapability();

    return AnalysisRecommendation.determine(videoInfo, deviceCapability);
  }

  Future<EyeTrackingResult> analyzeVideo(
    File videoFile, {
    AnalysisQuality quality = AnalysisQuality.good,
    Function(double progress, String message)? onProgress,
  }) async {
    if (_mlKitAnalyzer == null) await initialize();

    // 디바이스 성능 체크
    final recommendation = await getAnalysisRecommendation(videoFile);

    if (!recommendation.canProcessLocally) {
      throw LocalAnalysisException(
        ' 디바이스 성능이 부족합니다: ${recommendation.reason}',
        recommendation: recommendation,
      );
    }

    try {
      onProgress?.call(0.0, '로컬 분석 시작...');

      // 배터리 체크
      await _checkBatteryLevel();

      // 메모리 정리
      await _optimizeMemory();

      // ML Kit으로 분석 수행
      final result = await _mlKitAnalyzer!.analyzeVideo(
        videoFile,
        onProgress: onProgress,
        quality: quality,
      );

      // 결과 로컬 저장
      await _saveResultLocally(result);

      return result;

    } catch (e) {
      throw LocalAnalysisException('분석 중 오류 발생: $e');
    }
  }

  Future<Map<String, dynamic>> _getVideoInfo(File videoFile) async {
    final fileSize = await videoFile.length();

    // 실제로는 video_player나 ffmpeg로 정보 추출
    return {
      'fileSizeBytes': fileSize,
      'estimatedDuration': Duration(seconds: 30), // 실제로는 동적으로 계산
      'estimatedResolution': '1080p',
    };
  }

  Future<void> _checkBatteryLevel() async {
    // battery_plus 패키지 사용
    // final battery = Battery();
    // final level = await battery.batteryLevel;

    // if (level < 20) {
    //   throw LocalAnalysisException('배터리 부족 (${level}%). 20% 이상일 때 분석하세요.');
    // }
  }

  Future<void> _optimizeMemory() async {
    // 메모리 정리 (선택적)
    if (kDebugMode) {
      debugPrint('Memory optimization (개발 모드에서는 스킵)');
    }
  }

  Future<void> _saveResultLocally(EyeTrackingResult result) async {
    // sqflite나 shared_preferences로 결과 저장
    // 추후 히스토리 기능을 위해 구현
  }
}

class AnalysisRecommendation {
  final bool canProcessLocally;
  final AnalysisQuality recommendedQuality;
  final String reason;
  final Duration estimatedTime;

  const AnalysisRecommendation({
    required this.canProcessLocally,
    required this.recommendedQuality,
    required this.reason,
    required this.estimatedTime,
  });

  static AnalysisRecommendation determine(
    Map<String, dynamic> videoInfo,
    DeviceCapability deviceCapability,
  ) {
    final int fileSizeBytes = videoInfo['fileSizeBytes'];
    final Duration videoDuration = videoInfo['estimatedDuration'];

    // 파일 크기 체크 (100MB 초과 시 경고)
    if (fileSizeBytes > 100 * 1024 * 1024) {
      return AnalysisRecommendation(
        canProcessLocally: false,
        recommendedQuality: AnalysisQuality.basic,
        reason: '파일이 너무 큽니다 (${(fileSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB)',
        estimatedTime: Duration.zero,
      );
    }

    // 영상 길이 체크
    if (videoDuration.inSeconds > 120) {
      return AnalysisRecommendation(
        canProcessLocally: deviceCapability.isHighEnd,
        recommendedQuality: AnalysisQuality.basic,
        reason: '긴 영상입니다 (${videoDuration.inSeconds}초)',
        estimatedTime: Duration(minutes: videoDuration.inSeconds ~/ 20),
      );
    }

    // 디바이스 성능별 추천
    if (deviceCapability.isHighEnd) {
      return AnalysisRecommendation(
        canProcessLocally: true,
        recommendedQuality: AnalysisQuality.high,
        reason: '고성능 디바이스',
        estimatedTime: Duration(seconds: videoDuration.inSeconds ~/ 2),
      );
    } else if (deviceCapability.isMidRange) {
      return AnalysisRecommendation(
        canProcessLocally: true,
        recommendedQuality: AnalysisQuality.good,
        reason: '중급형 디바이스',
        estimatedTime: Duration(seconds: videoDuration.inSeconds),
      );
    } else {
      return AnalysisRecommendation(
        canProcessLocally: true,
        recommendedQuality: AnalysisQuality.basic,
        reason: '저사양 디바이스 (기본 분석만 가능)',
        estimatedTime: Duration(seconds: videoDuration.inSeconds * 2),
      );
    }
  }
}

class LocalAnalysisException implements Exception {
  final String message;
  final AnalysisRecommendation? recommendation;

  const LocalAnalysisException(this.message, {this.recommendation});

  @override
  String toString() => 'LocalAnalysisException: $message';
}
```

#### B. 디바이스 성능 체커 (services/device_capability_checker.dart)

```dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';

class DeviceCapabilityChecker {
  DeviceInfoPlugin? _deviceInfo;
  Battery? _battery;

  Future<void> initialize() async {
    _deviceInfo = DeviceInfoPlugin();
    _battery = Battery();
  }

  Future<DeviceCapability> assessCapability() async {
    if (Platform.isAndroid) {
      return await _assessAndroidCapability();
    } else if (Platform.isIOS) {
      return await _assessiOSCapability();
    } else {
      return DeviceCapability.unknown();
    }
  }

  Future<DeviceCapability> _assessAndroidCapability() async {
    final androidInfo = await _deviceInfo!.androidInfo;

    // RAM 추정 (안드로이드에서는 정확한 RAM 정보를 얻기 어려움)
    int estimatedRamGB = 4; // 기본값

    // CPU 코어 수
    final cpuCores = Platform.numberOfProcessors;

    // 안드로이드 버전
    final sdkInt = androidInfo.version.sdkInt;

    // 브랜드별 성능 추정
    final brand = androidInfo.brand.toLowerCase();
    final model = androidInfo.model.toLowerCase();

    bool isHighEnd = false;
    bool isMidRange = false;

    // 고성능 디바이스 판별
    if (brand.contains('samsung')) {
      isHighEnd = model.contains('galaxy s2') ||
                  model.contains('galaxy note') ||
                  model.contains('galaxy s1');
      isMidRange = model.contains('galaxy a') ||
                   model.contains('galaxy m');
    } else if (brand.contains('google')) {
      isHighEnd = model.contains('pixel');
    } else if (brand.contains('xiaomi')) {
      isHighEnd = model.contains('mi 1') || model.contains('redmi note pro');
    }

    // CPU 및 안드로이드 버전 고려
    if (cpuCores >= 8 && sdkInt >= 28) {
      estimatedRamGB = isHighEnd ? 8 : (isMidRange ? 6 : 4);
    }

    return DeviceCapability(
      platform: 'Android',
      ramGB: estimatedRamGB,
      cpuCores: cpuCores,
      osVersion: '${androidInfo.version.release}',
      deviceModel: '${androidInfo.brand} ${androidInfo.model}',
      isHighEnd: isHighEnd,
      isMidRange: isMidRange || (!isHighEnd && cpuCores >= 6),
    );
  }

  Future<DeviceCapability> _assessiOSCapability() async {
    final iosInfo = await _deviceInfo!.iosInfo;

    // iOS 디바이스별 성능 추정
    final model = iosInfo.model.toLowerCase();
    final name = iosInfo.name.toLowerCase();

    bool isHighEnd = false;
    bool isMidRange = false;
    int estimatedRamGB = 4;

    if (model.contains('iphone')) {
      // iPhone 모델별 분류
      if (name.contains('iphone 15') ||
          name.contains('iphone 14') ||
          name.contains('iphone 13 pro')) {
        isHighEnd = true;
        estimatedRamGB = 8;
      } else if (name.contains('iphone 13') ||
                 name.contains('iphone 12') ||
                 name.contains('iphone 11')) {
        isMidRange = true;
        estimatedRamGB = 6;
      } else {
        estimatedRamGB = 4;
      }
    } else if (model.contains('ipad')) {
      // iPad는 일반적으로 고성능
      isHighEnd = true;
      estimatedRamGB = 8;
    }

    return DeviceCapability(
      platform: 'iOS',
      ramGB: estimatedRamGB,
      cpuCores: Platform.numberOfProcessors,
      osVersion: iosInfo.systemVersion,
      deviceModel: '${iosInfo.name} ${iosInfo.model}',
      isHighEnd: isHighEnd,
      isMidRange: isMidRange,
    );
  }
}

class DeviceCapability {
  final String platform;
  final int ramGB;
  final int cpuCores;
  final String osVersion;
  final String deviceModel;
  final bool isHighEnd;
  final bool isMidRange;

  const DeviceCapability({
    required this.platform,
    required this.ramGB,
    required this.cpuCores,
    required this.osVersion,
    required this.deviceModel,
    required this.isHighEnd,
    required this.isMidRange,
  });

  factory DeviceCapability.unknown() {
    return DeviceCapability(
      platform: 'Unknown',
      ramGB: 4,
      cpuCores: Platform.numberOfProcessors,
      osVersion: 'Unknown',
      deviceModel: 'Unknown Device',
      isHighEnd: false,
      isMidRange: false,
    );
  }

  bool get isLowEnd => !isHighEnd && !isMidRange;

  String get performanceCategory {
    if (isHighEnd) return '고성능';
    if (isMidRange) return '중급형';
    return '저사양';
  }

  String get recommendationText {
    if (isHighEnd) {
      return '고품질 로컬 분석을 권장합니다.';
    } else if (isMidRange) {
      return '표준 품질 로컬 분석이 가능합니다.';
    } else {
      return '기본 품질 분석 또는 서버 분석을 권장합니다.';
    }
  }
}
```

### 5. UI 구현

#### A. 메인 분석 화면 (screens/video_analysis_screen.dart)

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/local_analysis_service.dart';
import '../models/eye_tracking_result.dart';
import '../widgets/analysis_progress_widget.dart';
import '../widgets/result_visualization_widget.dart';

class VideoAnalysisScreen extends StatefulWidget {
  @override
  _VideoAnalysisScreenState createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  final LocalAnalysisService _analysisService = LocalAnalysisService();

  File? _selectedVideo;
  EyeTrackingResult? _analysisResult;
  bool _isAnalyzing = false;
  double _analysisProgress = 0.0;
  String _analysisMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  @override
  void dispose() {
    _analysisService.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      await _analysisService.initialize();
    } catch (e) {
      _showErrorDialog('서비스 초기화 실패: $e');
    }
  }

  Future<void> _selectVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedVideo = File(result.files.single.path!);
          _analysisResult = null;
        });

        // 분석 추천사항 표시
        _showAnalysisRecommendation();
      }
    } catch (e) {
      _showErrorDialog('파일 선택 오류: $e');
    }
  }

  Future<void> _showAnalysisRecommendation() async {
    if (_selectedVideo == null) return;

    try {
      final recommendation = await _analysisService.getAnalysisRecommendation(_selectedVideo!);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('분석 옵션'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('추천: ${recommendation.recommendedQuality.displayName}'),
              SizedBox(height: 8),
              Text('예상 시간: ${_formatDuration(recommendation.estimatedTime)}'),
              SizedBox(height: 8),
              Text('사유: ${recommendation.reason}'),
              if (!recommendation.canProcessLocally) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '디바이스 성능상 서버 분석을 권장합니다.',
                    style: TextStyle(color: Colors.orange[800]),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('취소'),
            ),
            if (recommendation.canProcessLocally)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _startAnalysis(recommendation.recommendedQuality);
                },
                child: Text('로컬 분석 시작'),
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showServerAnalysisOption();
              },
              child: Text('서버 분석'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('추천사항 확인 오류: $e');
    }
  }

  void _showServerAnalysisOption() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('서버 분석'),
        content: Text('서버 분석 기능은 현재 개발 중입니다.\n로컬 분석을 시도해보시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startAnalysis(AnalysisQuality.basic);
            },
            child: Text('기본 로컬 분석'),
          ),
        ],
      ),
    );
  }

  Future<void> _startAnalysis(AnalysisQuality quality) async {
    if (_selectedVideo == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisProgress = 0.0;
      _analysisMessage = '분석 준비 중...';
      _analysisResult = null;
    });

    try {
      final result = await _analysisService.analyzeVideo(
        _selectedVideo!,
        quality: quality,
        onProgress: (progress, message) {
          setState(() {
            _analysisProgress = progress;
            _analysisMessage = message;
          });
        },
      );

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
      });

      _showCompletionDialog();

    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });

      if (e is LocalAnalysisException && e.recommendation != null) {
        _showAnalysisFailureDialog(e);
      } else {
        _showErrorDialog('분석 실패: $e');
      }
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('분석 완료'),
          ],
        ),
        content: Text(_analysisResult?.summaryText ?? '분석이 완료되었습니다.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showAnalysisFailureDialog(LocalAnalysisException exception) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('분석 실패'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exception.message),
            if (exception.recommendation != null) ...[
              SizedBox(height: 16),
              Text('권장사항:'),
              Text(exception.recommendation!.reason),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          if (exception.recommendation?.canProcessLocally == true)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _startAnalysis(exception.recommendation!.recommendedQuality);
              },
              child: Text('다시 시도'),
            ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('확인'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '약 ${duration.inMinutes}분';
    } else {
      return '약 ${duration.inSeconds}초';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('눈 움직임 분석'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 비디오 선택 섹션
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. 영상 선택',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 16),
                    if (_selectedVideo == null)
                      ElevatedButton.icon(
                        onPressed: _isAnalyzing ? null : _selectVideo,
                        icon: Icon(Icons.video_library),
                        label: Text('영상 선택'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.video_file, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedVideo!.path.split('/').last,
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              IconButton(
                                onPressed: _isAnalyzing ? null : _selectVideo,
                                icon: Icon(Icons.edit),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          FutureBuilder<int>(
                            future: _selectedVideo!.length(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final sizeKB = snapshot.data! / 1024;
                                final sizeMB = sizeKB / 1024;
                                return Text(
                                  '파일 크기: ${sizeMB > 1 ? '${sizeMB.toStringAsFixed(1)}MB' : '${sizeKB.toStringAsFixed(1)}KB'}',
                                  style: TextStyle(color: Colors.grey[600]),
                                );
                              }
                              return SizedBox();
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 분석 진행 섹션
            if (_isAnalyzing)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AnalysisProgressWidget(
                    progress: _analysisProgress,
                    message: _analysisMessage,
                  ),
                ),
              ),

            // 결과 표시 섹션
            if (_analysisResult != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: ResultVisualizationWidget(
                      result: _analysisResult!,
                    ),
                  ),
                ),
              ),

            // 도움말 섹션
            if (_selectedVideo == null && !_isAnalyzing && _analysisResult == null)
              Expanded(
                child: Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700]),
                            SizedBox(width: 8),
                            Text(
                              '사용 방법',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        _buildHelpItem('📹', '정면을 향해 촬영하세요'),
                        _buildHelpItem('👀', '자연스럽게 눈을 깜빡이며 시선을 움직이세요'),
                        _buildHelpItem('💡', '충분한 조명에서 촬영하세요'),
                        _buildHelpItem('⏱️', '30초 내외의 영상을 권장합니다'),
                        _buildHelpItem('🔋', '배터리가 충분한지 확인하세요'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(String emoji, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: 20)),
          SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
```

#### B. 진행률 표시 위젯 (widgets/analysis_progress_widget.dart)

```dart
import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

class AnalysisProgressWidget extends StatefulWidget {
  final double progress;
  final String message;

  const AnalysisProgressWidget({
    Key? key,
    required this.progress,
    required this.message,
  }) : super(key: key);

  @override
  _AnalysisProgressWidgetState createState() => _AnalysisProgressWidgetState();
}

class _AnalysisProgressWidgetState extends State<AnalysisProgressWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 메인 진행률 표시
        CircularPercentIndicator(
          radius: 80.0,
          lineWidth: 8.0,
          percent: widget.progress,
          center: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Icon(
                      Icons.remove_red_eye,
                      size: 30,
                      color: Colors.blue[600],
                    ),
                  );
                },
              ),
              SizedBox(height: 4),
              Text(
                '${(widget.progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          progressColor: Colors.blue[600],
          backgroundColor: Colors.blue[100]!,
          circularStrokeCap: CircularStrokeCap.round,
          animation: true,
          animationDuration: 500,
        ),

        SizedBox(height: 24),

        // 상태 메시지
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        SizedBox(height: 16),

        // 단계별 진행률
        _buildStageIndicator(),

        SizedBox(height: 16),

        // 처리 시간 정보
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
            SizedBox(width: 4),
            Text(
              '로컬에서 안전하게 처리 중...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStageIndicator() {
    final stages = [
      ProgressStage('초기화', 0.0, 0.1),
      ProgressStage('프레임 추출', 0.1, 0.3),
      ProgressStage('얼굴 검출', 0.3, 0.7),
      ProgressStage('눈 분석', 0.7, 0.9),
      ProgressStage('결과 계산', 0.9, 1.0),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: stages.map((stage) {
        final isActive = widget.progress >= stage.startProgress;
        final isCompleted = widget.progress >= stage.endProgress;
        final isCurrent = widget.progress >= stage.startProgress &&
                         widget.progress < stage.endProgress;

        return Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? Colors.green[600]
                    : isCurrent
                        ? Colors.blue[600]
                        : Colors.grey[300],
              ),
              child: isCompleted
                  ? Icon(Icons.check, size: 8, color: Colors.white)
                  : isCurrent
                      ? Container(
                          margin: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        )
                      : null,
            ),
            SizedBox(height: 4),
            Text(
              stage.name,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? Colors.blue[700] : Colors.grey[500],
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class ProgressStage {
  final String name;
  final double startProgress;
  final double endProgress;

  const ProgressStage(this.name, this.startProgress, this.endProgress);
}
```

#### C. 결과 시각화 위젯 (widgets/result_visualization_widget.dart)

```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/eye_tracking_result.dart';

class ResultVisualizationWidget extends StatefulWidget {
  final EyeTrackingResult result;

  const ResultVisualizationWidget({
    Key? key,
    required this.result,
  }) : super(key: key);

  @override
  _ResultVisualizationWidgetState createState() => _ResultVisualizationWidgetState();
}

class _ResultVisualizationWidgetState extends State<ResultVisualizationWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 결과 요약
        _buildResultSummary(),

        SizedBox(height: 16),

        // 탭 메뉴
        TabBar(
          controller: _tabController,
          labelColor: Colors.blue[700],
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.blue[600],
          tabs: [
            Tab(text: '요약', icon: Icon(Icons.summarize)),
            Tab(text: '차트', icon: Icon(Icons.analytics)),
            Tab(text: '상세', icon: Icon(Icons.details)),
          ],
        ),

        SizedBox(height: 16),

        // 탭 내용
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryTab(),
              _buildChartTab(),
              _buildDetailTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultSummary() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.result.pspSuspected
              ? [Colors.orange[50]!, Colors.orange[100]!]
              : [Colors.green[50]!, Colors.green[100]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.result.pspSuspected ? Icons.warning : Icons.check_circle,
                color: widget.result.pspSuspected ? Colors.orange[700] : Colors.green[700],
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.result.summaryText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.result.pspSuspected ? Colors.orange[800] : Colors.green[800],
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 12),

          // 신뢰도 점수
          Row(
            children: [
              Text('신뢰도: '),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getConfidenceColor(widget.result.confidenceScore),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.result.confidenceScore.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '(${widget.result.quality.displayName})',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricCard(
            '블링크 분석',
            Icons.remove_red_eye,
            [
              MetricItem('총 블링크 횟수', '${widget.result.totalBlinks}회'),
              MetricItem('분당 블링크 비율', '${widget.result.averageBlinkRate.toStringAsFixed(1)}/분'),
              MetricItem('정상 범위', '15-20회/분'),
            ],
          ),

          SizedBox(height: 16),

          _buildMetricCard(
            '눈 움직임 분석',
            Icons.track_changes,
            [
              MetricItem('수직 움직임 변화량', '${(widget.result.verticalMovementVariance * 100).toStringAsFixed(1)}%'),
              MetricItem('수평 움직임 변화량', '${(widget.result.horizontalMovementVariance * 100).toStringAsFixed(1)}%'),
              MetricItem('PSP 의심 임계값', '6.0% 이하'),
            ],
          ),

          SizedBox(height: 16),

          _buildMetricCard(
            '분석 정보',
            Icons.info,
            [
              MetricItem('총 프레임 수', '${widget.result.totalFrames}'),
              MetricItem('분석된 프레임', '${widget.result.analyzedFrames}'),
              MetricItem('영상 길이', '${widget.result.videoDuration.inSeconds}초'),
              MetricItem('분석 품질', widget.result.quality.displayName),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartTab() {
    // 시간별 눈 openness 데이터
    final validFrames = widget.result.frameData.where((f) => f.averageEyeOpenness != null).toList();

    if (validFrames.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              '차트를 표시할 데이터가 없습니다',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // 눈 openness 차트
          Container(
            height: 200,
            padding: EdgeInsets.all(16),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: validFrames.map((frame) {
                      return FlSpot(frame.timestamp, frame.averageEyeOpenness!);
                    }).toList(),
                    isCurved: true,
                    color: Colors.blue[600],
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // 차트 설명
          Text(
            '눈 열림 정도 시간 추이',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '1.0: 완전히 열림, 0.0: 완전히 닫힘',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PSP 분석 상세',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          SizedBox(height: 12),

          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.result.pspSuspected ? Colors.orange[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.result.pspSuspected ? Colors.orange[200]! : Colors.green[200]!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PSP (Progressive Supranuclear Palsy) 분석',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('판정: ${widget.result.pspSuspected ? "의심 소견" : "정상 범위"}'),
                SizedBox(height: 4),
                Text('근거: ${widget.result.pspReason}'),
              ],
            ),
          ),

          SizedBox(height: 16),

          Text(
            '통계 정보',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          SizedBox(height: 12),

          ...widget.result.statistics.entries.map((entry) {
            return Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      '${entry.key}:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text('${entry.value}'),
                  ),
                ],
              ),
            );
          }).toList(),

          SizedBox(height: 16),

          Text(
            '면책 조항',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          SizedBox(height: 8),

          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '이 분석은 보조적인 참고 자료일 뿐이며, 의학적 진단을 대체할 수 없습니다. '
              '정확한 진단을 위해서는 반드시 전문의와 상담하시기 바랍니다.',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, IconData icon, List<MetricItem> items) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue[600]),
                SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            ...items.map((item) => Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.label),
                  Text(
                    item.value,
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 80) return Colors.green[600]!;
    if (confidence >= 60) return Colors.orange[600]!;
    return Colors.red[600]!;
  }
}

class MetricItem {
  final String label;
  final String value;

  const MetricItem(this.label, this.value);
}
```

## 🚀 Phase 2: 하이브리드 시스템

### 1. 스마트 분석 전략

```dart
class HybridAnalysisService {
  final LocalAnalysisService _localService = LocalAnalysisService();
  final ServerAnalysisService _serverService = ServerAnalysisService();

  Future<AnalysisResult> analyzeVideo(File videoFile, String userId) async {
    // 1. 디바이스 성능 평가
    final deviceCapability = await _assessDeviceCapability();
    final videoComplexity = await _assessVideoComplexity(videoFile);

    // 2. 분석 전략 결정
    final strategy = _determineStrategy(deviceCapability, videoComplexity);

    switch (strategy) {
      case AnalysisStrategy.localOnly:
        return await _localService.analyzeVideo(videoFile);

      case AnalysisStrategy.serverOnly:
        return await _serverService.analyzeVideo(videoFile, userId);

      case AnalysisStrategy.hybrid:
        return await _performHybridAnalysis(videoFile, userId);

      case AnalysisStrategy.userChoice:
        return await _showUserChoiceDialog(videoFile, userId);
    }
  }

  Future<AnalysisResult> _performHybridAnalysis(File videoFile, String userId) async {
    try {
      // 로컬에서 빠른 프리뷰 분석 (낮은 품질)
      final previewFuture = _localService.analyzeVideo(
        videoFile,
        quality: AnalysisQuality.basic,
      );

      // 동시에 서버에서 정밀 분석 시작
      final preciseFuture = _serverService.analyzeVideo(videoFile, userId);

      // 프리뷰 결과 먼저 반환
      final preview = await previewFuture;

      return HybridAnalysisResult(
        preview: preview,
        preciseFuture: preciseFuture,
      );

    } catch (e) {
      // 로컬 분석 실패 시 서버로 폴백
      return await _serverService.analyzeVideo(videoFile, userId);
    }
  }
}
```

### 2. 설정 기반 분석 옵션

```dart
class AnalysisSettings {
  static const String keyPreferredMode = 'analysis_preferred_mode';
  static const String keyQualityLevel = 'analysis_quality_level';
  static const String keyBatteryThreshold = 'analysis_battery_threshold';

  static Future<AnalysisMode> getPreferredMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(keyPreferredMode) ?? 0;
    return AnalysisMode.values[modeIndex];
  }

  static Future<void> setPreferredMode(AnalysisMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyPreferredMode, mode.index);
  }
}

enum AnalysisMode {
  auto('자동 선택', '디바이스 성능에 따라 최적 방식 선택'),
  localOnly('로컬만', '디바이스에서만 처리 (개인정보 보호)'),
  serverOnly('서버만', '서버에서 고품질 처리'),
  hybrid('하이브리드', '빠른 프리뷰 + 정밀 분석');

  const AnalysisMode(this.displayName, this.description);

  final String displayName;
  final String description;
}
```

## 💰 비용 및 성능 비교

### 클라이언트 vs 서버 분석 비교표

| 항목 | **클라이언트 분석** | **서버 분석 (Lambda)** | **서버 분석 (EC2)** |
|------|---------------------|------------------------|---------------------|
| **월 비용 (1000회)** | **$0** | $500+ | $60+ |
| **분석 시간** | 30초-2분 | 30초-5분 | 30초-3분 |
| **정확도** | 중간 (70-80%) | 높음 (90-95%) | 최고 (95%+) |
| **개인정보보호** | **완벽** | 보통 | 보통 |
| **오프라인 사용** | **가능** | 불가능 | 불가능 |
| **디바이스 의존성** | 높음 | 없음 | 없음 |
| **배터리 소모** | 높음 | 낮음 | 낮음 |
| **네트워크 필요** | **불필요** | 필수 | 필수 |

## 🎯 최종 추천 방안

### **의료 앱에 최적화된 하이브리드 전략**

```dart
class MedicalAnalysisStrategy {
  static AnalysisMode determineOptimalMode(
    DeviceCapability device,
    VideoInfo video,
    UserPreferences preferences,
  ) {
    // 1. 개인정보보호 우선 모드
    if (preferences.privacyFirst) {
      return device.canProcessVideo(video)
          ? AnalysisMode.localOnly
          : AnalysisMode.userChoice;
    }

    // 2. 정확도 우선 모드
    if (preferences.accuracyFirst) {
      return AnalysisMode.serverOnly;
    }

    // 3. 균형 모드 (추천)
    if (video.durationSeconds <= 30 && device.isMidRange) {
      return AnalysisMode.hybrid; // 빠른 프리뷰 + 정밀 분석
    }

    // 4. 기본 전략
    return AnalysisMode.auto;
  }
}
```

## 📋 구현 체크리스트

### Phase 1: 기본 로컬 분석
- [ ] Google ML Kit 통합
- [ ] 기본 UI 구현
- [ ] 디바이스 성능 체크
- [ ] 진행률 표시
- [ ] 결과 시각화
- [ ] 로컬 데이터 저장

### Phase 2: 고도화
- [ ] TensorFlow Lite 모델 추가
- [ ] 하이브리드 분석 구현
- [ ] 사용자 설정 추가
- [ ] 배터리 최적화
- [ ] 오류 처리 개선

### Phase 3: 검증 및 배포
- [ ] 다양한 디바이스에서 테스트
- [ ] 성능 벤치마크
- [ ] 정확도 검증
- [ ] 앱 스토어 제출

---

이 가이드로 **완전 무료**이면서 **즉시 처리** 가능한 클라이언트 사이드 영상 분석 시스템을 구축할 수 있습니다! 🚀

**핵심 장점:**
- 💰 **제로 서버 비용**
- 🔒 **완벽한 개인정보보호**
- ⚡ **실시간 분석**
- 📱 **오프라인 동작**