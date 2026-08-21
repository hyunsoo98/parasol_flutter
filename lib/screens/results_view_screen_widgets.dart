import 'package:flutter/material.dart';
import '../models/analysis_models.dart';

/// [ResultsViewScreen]의 프레젠테이션 위젯들. 순수 표시용이며, 상태는 전부 생성자로 받는다.

/// label: value 한 줄. 상세 결과 카드들이 공유해서 쓰는 행 위젯.
class MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isImportant;

  const MetricRow(this.label, this.value, {Key? key, this.isImportant = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: isImportant ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: isImportant ? FontWeight.bold : null,
                color: isImportant ? Theme.of(context).primaryColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시선추적 분석 상세 카드.
class EyeTrackingResultsCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final Map<String, dynamic> summary;

  const EyeTrackingResultsCard({Key? key, required this.result, required this.summary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '시선 추적 분석 상세',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            if (summary['vertical_range'] != null)
              MetricRow(
                '수직 움직임 범위',
                '${(summary['vertical_range'] as double).toStringAsFixed(3)}',
                isImportant: true,
              ),

            if (summary['test_duration'] != null)
              MetricRow('테스트 시간', '${summary['test_duration']}초'),

            if (summary['total_frames'] != null)
              MetricRow('분석 프레임 수', '${summary['total_frames']}'),

            if (summary['blink_count'] != null)
              MetricRow('눈 깜박임 횟수', '${summary['blink_count']}회'),

            if (result['psp_detected'] != null) ...[
              const Divider(),
              MetricRow(
                'PSP 징후',
                result['psp_detected'] ? '감지됨' : '감지되지 않음',
                isImportant: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 손가락 탭핑 분석 상세 카드.
class FingerTappingResultsCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final Map<String, dynamic> summary;

  const FingerTappingResultsCard({Key? key, required this.result, required this.summary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '손가락 탭핑 분석 상세',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            if (summary['probability'] != null)
              MetricRow(
                '파킨슨병 확률',
                '${(summary['probability'] as double * 100).toStringAsFixed(1)}%',
                isImportant: true,
              ),

            if (result['duration_sec'] != null)
              MetricRow('분석 시간', '${result['duration_sec']}초'),

            if (result['tap_counts'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '손별 탭핑 횟수',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ...((result['tap_counts'] as Map<String, dynamic>).entries.map((entry) =>
                MetricRow('${entry.key} 손', '${entry.value}회'))),
            ],

            if (result['hand_predictions'] != null) ...[
              const Divider(),
              Text(
                '손별 분석 결과',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...((result['hand_predictions'] as List<dynamic>).map((hand) =>
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.grey[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${hand['hand']} 손',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        MetricRow('진단', hand['label'] ?? '분석불가'),
                        MetricRow('확률', '${((hand['probability'] ?? 0.0) * 100).toStringAsFixed(1)}%'),
                        MetricRow('탭핑 횟수', '${hand['tap_count'] ?? 0}회'),
                      ],
                    ),
                  ),
                ))),
            ],
          ],
        ),
      ),
    );
  }
}

/// 다운로드 섹션 — 결과물별 다운로드 버튼 목록.
class ResultsDownloadSection extends StatelessWidget {
  final List<DownloadUrl> downloadUrls;
  final bool isDownloading;
  final Future<void> Function(DownloadUrl) onDownload;

  const ResultsDownloadSection({
    Key? key,
    required this.downloadUrls,
    required this.isDownloading,
    required this.onDownload,
  }) : super(key: key);

  IconData _getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'csv':
        return Icons.table_chart;
      case 'json':
        return Icons.code;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'video':
      case 'mp4':
        return Icons.video_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _getFileTypeDisplayName(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'csv':
        return 'CSV 데이터 파일';
      case 'json':
        return 'JSON 결과 파일';
      case 'pdf':
        return 'PDF 리포트';
      case 'video':
      case 'mp4':
        return '분석 영상';
      default:
        return fileType.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '다운로드',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...downloadUrls.map((downloadUrl) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_getFileIcon(downloadUrl.type)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getFileTypeDisplayName(downloadUrl.type),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (downloadUrl.fileSize != null)
                          Text(
                            '크기: ${(downloadUrl.fileSize! / (1024 * 1024)).toStringAsFixed(1)}MB',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isDownloading ? null : () => onDownload(downloadUrl),
                    icon: isDownloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text(isDownloading ? '다운로드 중' : '다운로드'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
