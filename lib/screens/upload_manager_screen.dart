// lib/screens/upload_manager_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/analysis_models.dart';
import '../services/aws_integration_service.dart';
import '../providers/auth_provider.dart';
import 'analysis_status_screen.dart';

class UploadManagerScreen extends StatefulWidget {
  final String analysisType;
  final File? mediaFile;
  final Map<String, dynamic>? parameters;

  const UploadManagerScreen({
    super.key,
    required this.analysisType,
    this.mediaFile,
    this.parameters,
  });

  @override
  State<UploadManagerScreen> createState() => _UploadManagerScreenState();
}

class _UploadManagerScreenState extends State<UploadManagerScreen> {
  final AwsIntegrationService _awsService = AwsIntegrationService();

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadMessage = '';
  String? _errorMessage;
  UploadResponse? _uploadResult;

  @override
  void initState() {
    super.initState();

    // 파일이 이미 제공된 경우 자동으로 업로드 시작
    if (widget.mediaFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startUpload();
      });
    }
  }

  Future<void> _startUpload() async {
    if (widget.mediaFile == null) {
      setState(() {
        _errorMessage = '업로드할 파일이 없습니다.';
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.email ?? 'guest';

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadMessage = '파일 업로드 준비 중...';
      _errorMessage = null;
    });

    try {
      // 파일 크기 확인
      final fileSize = await widget.mediaFile!.length();
      final fileSizeMB = fileSize / (1024 * 1024);

      setState(() {
        _uploadMessage = '파일 크기: ${fileSizeMB.toStringAsFixed(1)}MB';
        _uploadProgress = 0.1;
      });

      // 업로드 시작
      setState(() {
        _uploadMessage = '서버로 업로드 중...';
        _uploadProgress = 0.3;
      });

      final result = await _awsService.uploadFile(
        file: widget.mediaFile!,
        analysisType: widget.analysisType,
        userId: userId,
        parameters: widget.parameters,
      );

      setState(() {
        _uploadProgress = 1.0;
        _uploadMessage = '업로드 완료! 분석을 시작합니다.';
        _uploadResult = result;
        _isUploading = false;
      });

      // 2초 후 상태 모니터링 화면으로 이동
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AnalysisStatusScreen(
              analysisId: result.analysisId,
              analysisType: result.analysisType,
            ),
          ),
        );
      }

    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = e.toString();
        _uploadMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAnalysisTypeDisplayName()),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 분석 타입 정보
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '분석 타입',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getAnalysisTypeDisplayName(),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (widget.parameters != null && widget.parameters!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '분석 설정',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...widget.parameters!.entries.map((entry) => Text(
                          '${entry.key}: ${entry.value}',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 파일 정보
              if (widget.mediaFile != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '선택된 파일',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.mediaFile!.path.split('/').last,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<int>(
                          future: widget.mediaFile!.length(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              final sizeMB = snapshot.data! / (1024 * 1024);
                              return Text(
                                '크기: ${sizeMB.toStringAsFixed(1)}MB',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            }
                            return const Text('크기 계산 중...');
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // 업로드 진행 상황
              if (_isUploading || _uploadResult != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '업로드 진행 상황',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _uploadProgress >= 1.0 ? Colors.green : Theme.of(context).primaryColor,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _uploadMessage,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),

                        if (_uploadProgress >= 1.0 && _uploadResult != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '분석 ID: ${_uploadResult!.analysisId}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // 에러 메시지
              if (_errorMessage != null)
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(
                              '업로드 실패',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.red[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _startUpload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                ),

              const Spacer(),

              // 하단 버튼들
              if (!_isUploading && widget.mediaFile != null && _uploadResult == null && _errorMessage == null)
                ElevatedButton(
                  onPressed: _startUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '업로드 시작',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

              if (widget.mediaFile == null)
                ElevatedButton(
                  onPressed: () {
                    // 파일 선택 화면으로 이동 또는 파일 피커 열기
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('파일 선택 기능을 구현해주세요')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '파일 선택',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

              const SizedBox(height: 8),

              if (_uploadResult != null)
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => AnalysisStatusScreen(
                          analysisId: _uploadResult!.analysisId,
                          analysisType: _uploadResult!.analysisType,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '분석 상태 확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

              if (!_isUploading)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAnalysisTypeDisplayName() {
    switch (widget.analysisType.toLowerCase()) {
      case 'finger-tapping':
        return '손가락 탭핑 분석';
      case 'voice-analysis':
        return '음성 분석';
      case 'eye-tracking':
      case 'eye-tracking-results':
        return '시선 추적 분석';
      default:
        return widget.analysisType;
    }
  }
}