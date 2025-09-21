// lib/screens/analysis_status_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_compatibility_service.dart';
import '../services/api_service.dart';

class AnalysisStatusScreen extends StatefulWidget {
  final String sessionId;
  final String userId;

  const AnalysisStatusScreen({
    super.key,
    required this.sessionId,
    required this.userId,
  });

  @override
  State<AnalysisStatusScreen> createState() => _AnalysisStatusScreenState();
}

class _AnalysisStatusScreenState extends State<AnalysisStatusScreen>
    with TickerProviderStateMixin {
  late final ServerCompatibilityService _serverCompatibility;

  Map<String, dynamic>? _analysisStatus;
  Map<String, dynamic>? _analysisResults;
  Timer? _pollingTimer;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _serverCompatibility = ServerCompatibilityService(ApiService());
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _loadStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final status = _analysisStatus?['status'];
      if (status == 'completed' || status == 'failed') {
        timer.cancel();
        return;
      }
      _loadStatus();
    });
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await _serverCompatibility.checkAnalysisStatus(widget.sessionId);
      setState(() {
        _analysisStatus = status;
      });

      // 분석이 완료된 경우 결과도 가져오기
      if (status['status'] == 'completed') {
        final results = await _serverCompatibility.getAnalysisResults(widget.sessionId);
        setState(() {
          _analysisResults = results;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 상태'),
        backgroundColor: const Color(0xFF2F3DA3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('분석 상태를 확인 중...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('오류: $_errorMessage'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStatus,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          if (_analysisResults != null) ...[
            _buildResultsCard(),
            const SizedBox(height: 16),
          ],
          _buildActionsCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _analysisStatus?['status'] ?? 'unknown';
    final progress = _analysisStatus?['progress'] ?? 0.0;
    final message = _analysisStatus?['message'] ?? '';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'pending_analysis':
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        statusText = '분석 대기 중';
        break;
      case 'processing':
        statusColor = Colors.blue;
        statusIcon = Icons.analytics;
        statusText = '분석 진행 중';
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = '분석 완료';
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = '분석 실패';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = '상태 불명';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (message.isNotEmpty)
                        Text(
                          message,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (status == 'processing' && progress > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress / 100.0,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
              const SizedBox(height: 8),
              Text(
                '진행률: ${progress.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    final results = _analysisResults!;
    final eyeData = results['eye_analysis'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.visibility, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '시선 추적 분석 결과',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildResultItem('수직 시선 범위', '${eyeData['vertical_range']?.toStringAsFixed(3) ?? '0.000'}'),
            _buildResultItem('평균 시선 속도', '${eyeData['average_gaze_velocity']?.toStringAsFixed(3) ?? '0.000'} px/s'),
            _buildResultItem('최대 시선 속도', '${eyeData['max_gaze_velocity']?.toStringAsFixed(3) ?? '0.000'} px/s'),
            _buildResultItem('깜박임 횟수', '${eyeData['blink_count'] ?? 0}회'),
            _buildResultItem('검사 시간', '${eyeData['test_duration']?.toStringAsFixed(1) ?? '0.0'}초'),
            _buildResultItem('분석된 프레임', '${eyeData['total_frames'] ?? 0}개'),
            const SizedBox(height: 12),
            if (eyeData['psp_risk_score'] != null) ...[
              const Divider(),
              const SizedBox(height: 8),
              _buildRiskScoreItem(
                'PSP 위험도',
                eyeData['psp_risk_score']?.toDouble() ?? 0.0,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskScoreItem(String label, double score) {
    Color scoreColor = score < 0.3 ? Colors.green : score < 0.7 ? Colors.orange : Colors.red;
    String riskLevel = score < 0.3 ? '낮음' : score < 0.7 ? '중간' : '높음';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scoreColor),
              ),
              child: Text(
                riskLevel,
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: score,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
        ),
        const SizedBox(height: 4),
        Text(
          '점수: ${(score * 100).toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildActionsCard() {
    final status = _analysisStatus?['status'] ?? 'unknown';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '작업',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (status == 'completed') ...[
              ElevatedButton.icon(
                onPressed: () {
                  // 손가락 태핑 테스트로 이동
                  Navigator.of(context).pushReplacementNamed('/finger-tapping', arguments: {
                    'sessionId': widget.sessionId,
                    'userId': widget.userId,
                    'eyeResults': _analysisResults,
                  });
                },
                icon: const Icon(Icons.touch_app),
                label: const Text('손가락 태핑 테스트 시작'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F3DA3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('상태 새로고침'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/home',
                  (route) => false,
                );
              },
              icon: const Icon(Icons.home),
              label: const Text('홈으로 돌아가기'),
            ),
          ],
        ),
      ),
    );
  }

}

