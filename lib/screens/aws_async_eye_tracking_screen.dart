import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../services/aws_async_eye_tracking_service.dart';
import '../services/permission_service.dart';

class AwsAsyncEyeTrackingScreen extends StatefulWidget {
  const AwsAsyncEyeTrackingScreen({Key? key}) : super(key: key);

  @override
  State<AwsAsyncEyeTrackingScreen> createState() => _AwsAsyncEyeTrackingScreenState();
}

class _AwsAsyncEyeTrackingScreenState extends State<AwsAsyncEyeTrackingScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isRecording = false;
  
  String? _recordedVideoPath;
  String? _currentAnalysisId;
  
  // 분석 상태
  AnalysisPhase _analysisPhase = AnalysisPhase.idle;
  int _progress = 0;
  String _statusMessage = '';
  AnalysisResult? _analysisResult;
  
  // 사용자 ID (실제 앱에서는 인증 시스템에서 가져옴)
  final String _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await PermissionService.requestCameraPermission();
      _cameras = await availableCameras();
      
      if (_cameras!.isNotEmpty) {
        // 전면 카메라 찾기
        CameraDescription frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );
        
        _controller = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        
        await _controller!.initialize();
        
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '카메라 초기화 실패: $e';
      });
    }
  }

  Future<void> _startRecording() async {
    if (!_controller!.value.isInitialized || _isRecording) return;

    try {
      setState(() {
        _isRecording = true;
        _statusMessage = '녹화 중... (15초)';
        _analysisResult = null;
        _analysisPhase = AnalysisPhase.recording;
      });

      await _controller!.startVideoRecording();

      // 15초 후 자동 중지
      Future.delayed(const Duration(seconds: 15), () {
        if (_isRecording) {
          _stopRecording();
        }
      });

    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusMessage = '녹화 시작 실패: $e';
        _analysisPhase = AnalysisPhase.idle;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final XFile videoFile = await _controller!.stopVideoRecording();
      
      setState(() {
        _isRecording = false;
        _recordedVideoPath = videoFile.path;
        _statusMessage = '녹화 완료. AWS에서 분석하시겠습니까?';
        _analysisPhase = AnalysisPhase.recorded;
      });

    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusMessage = '녹화 중지 실패: $e';
        _analysisPhase = AnalysisPhase.idle;
      });
    }
  }

  Future<void> _startAwsAnalysis() async {
    if (_recordedVideoPath == null || _analysisPhase == AnalysisPhase.analyzing) return;

    setState(() {
      _analysisPhase = AnalysisPhase.analyzing;
      _progress = 0;
      _statusMessage = 'AWS Lambda에 분석 요청 중...';
    });

    try {
      final File videoFile = File(_recordedVideoPath!);

      // AWS 비동기 분석 시작
      final result = await AwsAsyncEyeTrackingService.analyzeVideoComplete(
        videoFile: videoFile,
        userId: _userId,
        step: 1,
        vppThresh: 0.06,
        blinkThresh: 0.18,
        maxFrames: 12000,
        timeout: const Duration(minutes: 20),
        onProgress: (phase, progress, message) {
          setState(() {
            _progress = progress;
            _statusMessage = '$phase: $message';
          });
        },
      );

      setState(() {
        _analysisResult = result;
        _analysisPhase = AnalysisPhase.completed;
        _progress = 100;
        _statusMessage = '분석 완료!';
      });

    } catch (e) {
      setState(() {
        _analysisPhase = AnalysisPhase.error;
        _statusMessage = 'AWS 분석 실패: $e';
        _progress = 0;
      });
    }
  }

  Future<void> _checkAnalysisStatus() async {
    if (_currentAnalysisId == null) return;

    try {
      final status = await AwsAsyncEyeTrackingService.getAnalysisStatus(
        analysisId: _currentAnalysisId!,
        includeResult: true,
      );

      setState(() {
        _progress = status.progress;
        _statusMessage = status.progressMessage ?? 'Processing...';
        
        if (status.status == AnalysisStatusEnum.completed && status.result != null) {
          _analysisResult = status.result;
          _analysisPhase = AnalysisPhase.completed;
        } else if (status.status == AnalysisStatusEnum.failed) {
          _analysisPhase = AnalysisPhase.error;
          _statusMessage = status.error ?? 'Analysis failed';
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '상태 확인 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('AWS 비동기 Eye Tracking'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 카메라 프리뷰
          Expanded(
            flex: 3,
            child: _buildCameraPreview(),
          ),
          
          // 상태 표시
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatusIndicator(),
                const SizedBox(height: 8),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // 컨트롤 버튼들
          Container(
            padding: const EdgeInsets.all(16),
            child: _buildControlButtons(),
          ),
          
          // 분석 결과
          if (_analysisResult != null)
            Expanded(
              flex: 2,
              child: _buildAnalysisResults(),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    Color borderColor;
    switch (_analysisPhase) {
      case AnalysisPhase.recording:
        borderColor = Colors.red;
        break;
      case AnalysisPhase.analyzing:
        borderColor = Colors.orange;
        break;
      case AnalysisPhase.completed:
        borderColor = Colors.green;
        break;
      case AnalysisPhase.error:
        borderColor = Colors.red;
        break;
      default:
        borderColor = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CameraPreview(_controller!),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    switch (_analysisPhase) {
      case AnalysisPhase.analyzing:
        return Column(
          children: [
            LinearProgressIndicator(
              value: _progress / 100,
              backgroundColor: Colors.grey[700],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 8),
            Text(
              '$_progress%',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        );
      case AnalysisPhase.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 32);
      case AnalysisPhase.error:
        return const Icon(Icons.error, color: Colors.red, size: 32);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                _isRecording ? '녹화 중지' : '녹화 시작',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: (_recordedVideoPath != null && _analysisPhase != AnalysisPhase.analyzing) 
                  ? _startAwsAnalysis 
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: _analysisPhase == AnalysisPhase.analyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'AWS 분석',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
        if (_currentAnalysisId != null) ...[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _checkAnalysisStatus,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            ),
            child: const Text(
              '상태 확인',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnalysisResults() {
    if (_analysisResult == null) return Container();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 AWS 분석 결과',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildResultRow('처리된 프레임', '${_analysisResult!.framesProcessed}개'),
            _buildResultRow('분석 시간', '${_analysisResult!.durationSec.toStringAsFixed(1)}초'),
            _buildResultRow('비디오 해상도', '${_analysisResult!.videoMeta.width}x${_analysisResult!.videoMeta.height}'),
            
            const SizedBox(height: 12),
            const Text(
              '👁️ 수직 움직임',
              style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('표준편차', _analysisResult!.verticalMovement.std.toStringAsFixed(3)),
            _buildResultRow('Peak-to-Peak', _analysisResult!.verticalMovement.peakToPeak.toStringAsFixed(3)),
            
            const SizedBox(height: 12),
            const Text(
              '👀 블링크 분석',
              style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('블링크 횟수', '${_analysisResult!.blinkAnalysis.count}회'),
            _buildResultRow('분당 블링크', '${_analysisResult!.blinkAnalysis.ratePerMinute.toStringAsFixed(1)}회'),
            
            const SizedBox(height: 12),
            const Text(
              '🏥 PSP 스크리닝',
              style: TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('PSP 의심', _analysisResult!.pspScreening.suspected ? 'Yes' : 'No'),
            _buildResultRow('측정값', _analysisResult!.pspScreening.verticalPtpMeasured.toStringAsFixed(3)),
            _buildResultRow('임계값', _analysisResult!.pspScreening.thresholdUsed.toStringAsFixed(3)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

enum AnalysisPhase {
  idle,
  recording,
  recorded,
  analyzing,
  completed,
  error,
}