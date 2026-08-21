// lib/screens/results_view_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/analysis_models.dart';
import '../services/aws_integration_service.dart';
import 'results_view_screen_widgets.dart';

class ResultsViewScreen extends StatefulWidget {
  final String analysisId;
  final String analysisType;

  const ResultsViewScreen({
    super.key,
    required this.analysisId,
    required this.analysisType,
  });

  @override
  State<ResultsViewScreen> createState() => _ResultsViewScreenState();
}

class _ResultsViewScreenState extends State<ResultsViewScreen> {
  final AwsIntegrationService _awsService = AwsIntegrationService();

  AnalysisResult? _result;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  Future<void> _loadResult() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await _awsService.getAnalysisResult(
        widget.analysisId,
        analysisType: widget.analysisType,
        generateDownloadUrl: true,
      );

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadFile(DownloadUrl downloadUrl) async {
    if (downloadUrl.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다운로드 링크가 만료되었습니다. 새로고침해주세요.')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${widget.analysisType}_${widget.analysisId}_${DateTime.now().millisecondsSinceEpoch}.${downloadUrl.type}';
      final localPath = '${directory.path}/$fileName';

      await _awsService.downloadFile(downloadUrl.url, localPath);

      setState(() {
        _isDownloading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('파일이 다운로드되었습니다: $fileName'),
          action: SnackBarAction(
            label: '확인',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다운로드 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 결과'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadResult,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _result != null ? () => _shareResult() : null,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState()
                : _result != null
                    ? _buildResultContent()
                    : const Center(child: Text('결과를 가져올 수 없습니다.')),
      ),
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
              '결과를 가져올 수 없습니다',
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
              onPressed: _loadResult,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    final result = _result!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 분석 정보 헤더
          _buildAnalysisHeader(),
          const SizedBox(height: 16),

          // 결과 요약
          _buildSummaryCard(),
          const SizedBox(height: 16),

          // 분석 타입별 상세 결과
          if (widget.analysisType.toLowerCase().contains('eye-tracking'))
            _buildEyeTrackingResults()
          else if (widget.analysisType.toLowerCase().contains('finger-tapping'))
            _buildFingerTappingResults()
          else if (widget.analysisType.toLowerCase().contains('voice'))
            _buildVoiceAnalysisResults(),

          const SizedBox(height: 16),

          // 다운로드 섹션
          if (result.downloadUrls.isNotEmpty) _buildDownloadSection(),

          const SizedBox(height: 16),

          // 원시 데이터 (개발용)
          if (result.result.isNotEmpty) _buildRawDataSection(),
        ],
      ),
    );
  }

  Widget _buildAnalysisHeader() {
    final result = _result!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getAnalysisIcon(),
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getAnalysisTypeDisplayName(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '분석 ID: ${result.analysisId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('완료 시간', _formatDateTime(result.completedAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _result!.summary;

    if (summary.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      color: _getDiagnosisColor(summary['diagnosis']),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getDiagnosisIcon(summary['diagnosis']),
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '진단 결과',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              summary['diagnosis'] ?? '분석불가',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (summary['confidence'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '신뢰도: ${_getConfidenceText(summary['confidence'])}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEyeTrackingResults() {
    return EyeTrackingResultsCard(result: _result!.result, summary: _result!.summary);
  }

  Widget _buildFingerTappingResults() {
    return FingerTappingResultsCard(result: _result!.result, summary: _result!.summary);
  }

  Widget _buildVoiceAnalysisResults() {
    final result = _result!.result;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '음성 분석 상세',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '음성 분석 결과가 여기에 표시됩니다.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            // TODO: 음성 분석 결과 구조에 따라 구현
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSection() {
    return ResultsDownloadSection(
      downloadUrls: _result!.downloadUrls,
      isDownloading: _isDownloading,
      onDownload: _downloadFile,
    );
  }

  Widget _buildRawDataSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '원시 데이터',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _showRawDataDialog(),
                  child: const Text('전체 보기'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _result!.result.toString().length > 200
                    ? '${_result!.result.toString().substring(0, 200)}...'
                    : _result!.result.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  void _showRawDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('원시 데이터'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              _result!.result.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _shareResult() {
    final summary = _result!.summary;
    final diagnosis = summary['diagnosis'] ?? '분석불가';
    final confidence = summary['confidence'];

    String shareText = '파킨슨병 ${_getAnalysisTypeDisplayName()} 결과\n\n';
    shareText += '진단: $diagnosis\n';
    if (confidence != null) {
      shareText += '신뢰도: ${_getConfidenceText(confidence)}\n';
    }
    shareText += '분석 일시: ${_formatDateTime(_result!.completedAt)}\n';
    shareText += '분석 ID: ${_result!.analysisId}';

    // 실제 구현에서는 share_plus 패키지 사용
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('공유 기능: $shareText')),
    );
  }

  // Helper methods
  IconData _getAnalysisIcon() {
    switch (widget.analysisType.toLowerCase()) {
      case 'finger-tapping':
        return Icons.touch_app;
      case 'voice-analysis':
        return Icons.mic;
      case 'eye-tracking':
      case 'eye-tracking-results':
        return Icons.visibility;
      default:
        return Icons.analytics;
    }
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

  Color _getDiagnosisColor(String? diagnosis) {
    if (diagnosis == null) return Colors.grey;

    if (diagnosis.contains('정상') || diagnosis.contains('HC')) {
      return Colors.green;
    } else if (diagnosis.contains('파킨슨') || diagnosis.contains('PD') || diagnosis.contains('의심')) {
      return Colors.red;
    } else {
      return Colors.orange;
    }
  }

  IconData _getDiagnosisIcon(String? diagnosis) {
    if (diagnosis == null) return Icons.help;

    if (diagnosis.contains('정상') || diagnosis.contains('HC')) {
      return Icons.check_circle;
    } else if (diagnosis.contains('파킨슨') || diagnosis.contains('PD') || diagnosis.contains('의심')) {
      return Icons.warning;
    } else {
      return Icons.info;
    }
  }

  String _getConfidenceText(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return '높음';
      case 'medium':
        return '보통';
      case 'low':
        return '낮음';
      case 'very_low':
        return '매우 낮음';
      default:
        return confidence;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}