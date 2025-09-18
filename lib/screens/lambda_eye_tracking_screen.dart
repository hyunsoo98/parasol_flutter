import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../services/lambda_eye_tracking_service.dart';
import '../services/permission_service.dart';

class LambdaEyeTrackingScreen extends StatefulWidget {
  const LambdaEyeTrackingScreen({Key? key}) : super(key: key);

  @override
  State<LambdaEyeTrackingScreen> createState() => _LambdaEyeTrackingScreenState();
}

class _LambdaEyeTrackingScreenState extends State<LambdaEyeTrackingScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  
  String? _recordedVideoPath;
  Map<String, dynamic>? _analysisResult;
  String _statusMessage = '';

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
          enableAudio: false, // 눈 추적에는 오디오 불필요
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
      });

      // 임시 디렉토리에 비디오 저장
      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String videoPath = '${tempDir.path}/eye_tracking_$timestamp.mp4';

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
        _statusMessage = '녹화 완료. 분석을 시작하세요.';
      });

    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusMessage = '녹화 중지 실패: $e';
      });
    }
  }

  Future<void> _analyzeVideo() async {
    if (_recordedVideoPath == null || _isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'AWS Lambda에서 분석 중...';
    });

    try {
      final File videoFile = File(_recordedVideoPath!);
      final String userId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      // Lambda 서비스 호출
      final result = await LambdaEyeTrackingService.analyzeVideo(
        videoFile: videoFile,
        userId: userId,
        step: 1,
        vppThresh: 0.06,
        blinkThresh: 0.18,
        maxFrames: 12000,
      );

      if (result['success']) {
        final parsedResult = LambdaEyeTrackingService.parseAnalysisResult(result['data']);
        
        setState(() {
          _analysisResult = parsedResult;
          _statusMessage = '분석 완료!';
        });
      } else {
        setState(() {
          _statusMessage = LambdaEyeTrackingService.getLocalizedError(result['error']);
        });
      }

    } catch (e) {
      setState(() {
        _statusMessage = '분석 실패: $e';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('AWS Lambda 눈 추적 분석'),
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
          
          // 상태 메시지
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          
          // 컨트롤 버튼들
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _isRecording ? _stopRecording : _startRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red : Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: Text(
                        _isRecording ? '녹화 중지' : '녹화 시작',
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: (_recordedVideoPath != null && !_isAnalyzing) 
                          ? _analyzeVideo 
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: _isAnalyzing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Lambda 분석',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                    ),
                  ],
                ),
              ],
            ),
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

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording ? Colors.red : Colors.blue,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CameraPreview(_controller!),
      ),
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
              '📊 분석 결과',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildResultRow('처리된 프레임', '${_analysisResult!['frames_processed']}개'),
            _buildResultRow('분석 시간', '${_analysisResult!['duration_sec']?.toStringAsFixed(1)}초'),
            
            const SizedBox(height: 12),
            const Text(
              '👁️ 수직 움직임',
              style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('표준편차', 
                '${(_analysisResult!['vertical_movement']['std'] ?? 0).toStringAsFixed(3)}'),
            _buildResultRow('Peak-to-Peak', 
                '${(_analysisResult!['vertical_movement']['peak_to_peak'] ?? 0).toStringAsFixed(3)}'),
            
            const SizedBox(height: 12),
            const Text(
              '👀 블링크 분석',
              style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('블링크 횟수', '${_analysisResult!['blink_analysis']['count']}회'),
            _buildResultRow('분당 블링크', 
                '${(_analysisResult!['blink_analysis']['rate_per_minute'] ?? 0).toStringAsFixed(1)}회'),
            
            const SizedBox(height: 12),
            const Text(
              '🏥 PSP 스크리닝',
              style: TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _buildResultRow('PSP 의심', 
                _analysisResult!['psp_screening']['suspected'] ? 'Yes' : 'No'),
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