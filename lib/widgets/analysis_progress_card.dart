// lib/widgets/analysis_progress_card.dart
import 'package:flutter/material.dart';
import '../services/analysis_polling_service.dart';

class AnalysisProgressCard extends StatelessWidget {
  final AnalysisProgress progress;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;

  const AnalysisProgressCard({
    super.key,
    required this.progress,
    this.onTap,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                children: [
                  _buildStatusIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getAnalysisTypeDisplayName(),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          progress.analysisId,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onCancel != null && !progress.isFinished)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onCancel,
                      iconSize: 20,
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // 진행률 표시
              if (!progress.isFinished) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress.progress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getProgressColor(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${progress.progress}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // 상태 메시지
              Text(
                _getStatusMessage(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _getStatusColor(),
                ),
              ),

              // 오류 메시지
              if (progress.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red[600], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          progress.error!,
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 완료된 경우 결과 표시
              if (progress.isCompleted && progress.results != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '분석이 완료되었습니다. 탭하여 결과를 확인하세요.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green[600]),
                    ],
                  ),
                ),
              ],

              // 타임스탬프
              const SizedBox(height: 8),
              Text(
                '업데이트: ${_formatTimestamp(progress.timestamp)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData iconData;
    Color color;

    switch (progress.status) {
      case AnalysisStatus.uploaded:
        iconData = Icons.upload_file;
        color = Colors.blue;
        break;
      case AnalysisStatus.processing:
        iconData = Icons.hourglass_empty;
        color = Colors.orange;
        break;
      case AnalysisStatus.completed:
        iconData = Icons.check_circle;
        color = Colors.green;
        break;
      case AnalysisStatus.failed:
        iconData = Icons.error;
        color = Colors.red;
        break;
      default:
        iconData = Icons.help;
        color = Colors.grey;
    }

    return Icon(iconData, color: color, size: 24);
  }

  String _getAnalysisTypeDisplayName() {
    switch (progress.analysisType.toLowerCase()) {
      case 'eye-tracking':
        return '안구 추적 분석';
      case 'finger-tapping':
        return '손가락 태핑 분석';
      case 'voice-analysis':
        return '음성 분석';
      default:
        return '분석';
    }
  }

  String _getStatusMessage() {
    if (progress.message != null && progress.message!.isNotEmpty) {
      return progress.message!;
    }

    switch (progress.status) {
      case AnalysisStatus.uploaded:
        return '업로드 완료, 처리 대기 중...';
      case AnalysisStatus.processing:
        return '분석 진행 중...';
      case AnalysisStatus.completed:
        return '분석 완료';
      case AnalysisStatus.failed:
        return '분석 실패';
      default:
        return '상태 확인 중...';
    }
  }

  Color _getStatusColor() {
    switch (progress.status) {
      case AnalysisStatus.uploaded:
        return Colors.blue;
      case AnalysisStatus.processing:
        return Colors.orange;
      case AnalysisStatus.completed:
        return Colors.green;
      case AnalysisStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getProgressColor() {
    switch (progress.status) {
      case AnalysisStatus.processing:
        return Colors.orange;
      case AnalysisStatus.completed:
        return Colors.green;
      case AnalysisStatus.failed:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}

// 여러 분석의 종합 진행률을 표시하는 위젯
class MultiAnalysisProgressCard extends StatelessWidget {
  final Map<String, AnalysisProgress> progressMap;
  final VoidCallback? onTap;

  const MultiAnalysisProgressCard({
    super.key,
    required this.progressMap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalAnalyses = progressMap.length;
    final completedAnalyses = progressMap.values.where((p) => p.isCompleted).length;
    final failedAnalyses = progressMap.values.where((p) => p.isFailed).length;
    final processingAnalyses = progressMap.values.where((p) => p.status == AnalysisStatus.processing).length;

    final overallProgress = totalAnalyses > 0 ? (completedAnalyses / totalAnalyses * 100).round() : 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '종합 진단 진행률',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // 전체 진행률
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: overallProgress / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        failedAnalyses > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$overallProgress%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 개별 분석 상태
              ...progressMap.entries.map((entry) {
                final progress = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _getStatusIcon(progress.status),
                        size: 16,
                        color: _getStatusColor(progress.status),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getAnalysisDisplayName(progress.analysisType),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        _getStatusText(progress.status),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _getStatusColor(progress.status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),

              const SizedBox(height: 12),

              // 요약 정보
              Text(
                '완료: $completedAnalyses, 진행 중: $processingAnalyses, 실패: $failedAnalyses',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon(AnalysisStatus status) {
    switch (status) {
      case AnalysisStatus.completed:
        return Icons.check_circle;
      case AnalysisStatus.processing:
        return Icons.hourglass_empty;
      case AnalysisStatus.failed:
        return Icons.error;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _getStatusColor(AnalysisStatus status) {
    switch (status) {
      case AnalysisStatus.completed:
        return Colors.green;
      case AnalysisStatus.processing:
        return Colors.orange;
      case AnalysisStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(AnalysisStatus status) {
    switch (status) {
      case AnalysisStatus.completed:
        return '완료';
      case AnalysisStatus.processing:
        return '진행 중';
      case AnalysisStatus.failed:
        return '실패';
      default:
        return '대기';
    }
  }

  String _getAnalysisDisplayName(String analysisType) {
    switch (analysisType.toLowerCase()) {
      case 'eye-tracking':
        return '안구 추적';
      case 'finger-tapping':
        return '손가락 태핑';
      case 'voice-analysis':
        return '음성 분석';
      default:
        return analysisType;
    }
  }
}