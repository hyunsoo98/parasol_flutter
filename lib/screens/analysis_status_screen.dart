// lib/screens/analysis_status_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/analysis_models.dart';
import '../services/aws_integration_service.dart';
import 'results_view_screen.dart';

class AnalysisStatusScreen extends StatefulWidget {
  final String analysisId;
  final String analysisType;

  const AnalysisStatusScreen({
    super.key,
    required this.analysisId,
    required this.analysisType,
  });

  @override
  State<AnalysisStatusScreen> createState() => _AnalysisStatusScreenState();
}

class _AnalysisStatusScreenState extends State<AnalysisStatusScreen>
    with TickerProviderStateMixin {
  final AwsIntegrationService _awsService = AwsIntegrationService();

  AnalysisStatus? _currentStatus;
  Timer? _pollingTimer;
  String? _errorMessage;
  bool _isLoading = true;

  late AnimationController _progressAnimationController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressAnimationController, curve: Curves.easeInOut),
    );

    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _progressAnimationController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _loadStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_currentStatus?.isCompleted == true || _currentStatus?.isFailed == true) {
        timer.cancel();
        return;
      }
      _loadStatus();
    });
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _awsService.getAnalysisStatus(
        widget.analysisId,
        analysisType: widget.analysisType,
      );

      setState(() {
        _currentStatus = status;
        _errorMessage = null;
        _isLoading = false;
      });

      // 진행률 애니메이션 업데이트
      _progressAnimationController.animateTo(status.progress / 100.0);

      // 완료된 경우 자동으로 결과 화면으로 이동
      if (status.isCompleted) {
        _pollingTimer?.cancel();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ResultsViewScreen(
                analysisId: widget.analysisId,
                analysisType: widget.analysisType,
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 진행 상황'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading && _currentStatus == null
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_currentStatus == null) {
      return const Center(child: Text('분석 상태를 가져올 수 없습니다.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 분석 정보 카드
          _buildAnalysisInfoCard(),
          const SizedBox(height: 16),

          // 진행 상태 카드
          _buildProgressCard(),
          const SizedBox(height: 16),

          // 상태별 세부 정보
          if (_currentStatus!.isProcessing) _buildProcessingInfo(),
          if (_currentStatus!.isCompleted) _buildCompletedInfo(),
          if (_currentStatus!.isFailed) _buildFailedInfo(),

          const SizedBox(height: 24),

          // 액션 버튼들
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildAnalysisInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '분석 정보',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('분석 ID', _currentStatus!.analysisId),
            _buildInfoRow('분석 타입', _getAnalysisTypeDisplayName()),
            _buildInfoRow('시작 시간', _formatDateTime(_currentStatus!.timestamp)),
            if (_currentStatus!.fileInfo != null)
              _buildInfoRow(
                '파일 크기',
                '${((_currentStatus!.fileInfo!['size'] ?? 0) / (1024 * 1024)).toStringAsFixed(1)}MB',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final status = _currentStatus!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.displayStatus,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(),
                        ),
                      ),
                      if (status.progressMessage.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          status.progressMessage,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${status.progress}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: _progressAnimation.value * (status.progress / 100.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                  minHeight: 8,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingInfo() {
    final status = _currentStatus!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '처리 중',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 12),
            if (status.estimatedCompletion != null) ...[
              Row(
                children: [
                  Icon(Icons.access_time, size: 20, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    '예상 완료 시간: ${_formatDuration(status.estimatedCompletion!)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '분석이 진행 중입니다. 잠시만 기다려주세요.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedInfo() {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  '분석 완료',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentStatus!.completedAt != null)
              _buildInfoRow(
                '완료 시간',
                _formatDateTime(_currentStatus!.completedAt!),
              ),
            const SizedBox(height: 8),
            Text(
              '분석이 성공적으로 완료되었습니다. 결과를 확인하세요.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedInfo() {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  '분석 실패',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentStatus!.failedAt != null)
              _buildInfoRow(
                '실패 시간',
                _formatDateTime(_currentStatus!.failedAt!),
              ),
            if (_currentStatus!.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '오류 메시지:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentStatus!.errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.red[700],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final status = _currentStatus!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.isCompleted)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ResultsViewScreen(
                    analysisId: widget.analysisId,
                    analysisType: widget.analysisType,
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
              '결과 확인',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

        if (status.isFailed) ...[
          ElevatedButton(
            onPressed: () async {
              try {
                await _awsService.retryAnalysis(widget.analysisId);
                _startPolling();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('재시도 실패: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              '다시 시도',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (status.isProcessing)
          ElevatedButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('분석 취소'),
                  content: const Text('정말로 분석을 취소하시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('아니오'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('예'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                try {
                  await _awsService.cancelAnalysis(widget.analysisId);
                  Navigator.of(context).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('취소 실패: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              '분석 취소',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('뒤로가기'),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[700]),
            const SizedBox(height: 16),
            Text(
              '상태를 가져올 수 없습니다',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadStatus,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final status = _currentStatus!;

    if (status.isCompleted) {
      return Icon(Icons.check_circle, color: Colors.green[700], size: 32);
    } else if (status.isFailed) {
      return Icon(Icons.error, color: Colors.red[700], size: 32);
    } else if (status.isProcessing) {
      return SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[700]!),
        ),
      );
    } else {
      return Icon(Icons.upload, color: Colors.blue[700], size: 32);
    }
  }

  Color _getStatusColor() {
    final status = _currentStatus!;

    if (status.isCompleted) {
      return Colors.green[700]!;
    } else if (status.isFailed) {
      return Colors.red[700]!;
    } else if (status.isProcessing) {
      return Colors.orange[700]!;
    } else {
      return Colors.blue[700]!;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
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

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}초';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '${minutes}분 ${remainingSeconds}초';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}시간 ${minutes}분';
    }
  }
}