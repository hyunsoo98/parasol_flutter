// lib/screens/voice_test_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';

class VoiceTestScreen extends StatefulWidget {
  const VoiceTestScreen({Key? key}) : super(key: key);

  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;
  
  bool _isRecording = false;
  int _countdown = 3;
  int _recordingDuration = 0;
  Timer? _timer;
  Timer? _countdownTimer;
  final int _maxDuration = 15; // 15초간 녹음

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: Duration(seconds: _maxDuration),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.linear,
    ));
    
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        _countdownTimer?.cancel();
        _startRecording();
      }
    });
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _countdown = 0;
    });
    
    _pulseController.repeat(reverse: true);
    _progressController.forward();
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
      
      if (_recordingDuration >= _maxDuration) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    _pulseController.stop();
    _progressController.stop();
    
    setState(() {
      _isRecording = false;
    });
    
    // 결과 화면으로 이동
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const ResultScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // 상단 여백
              const SizedBox(height: 40),
              
              // 제목
              const Text(
                'voice 테스트',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 60),
              
              // 메인 컨텐츠
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 카운트다운 또는 진행률 표시
                    if (_countdown > 0)
                      Column(
                        children: [
                          Text(
                            '$_countdown',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2F3DA3),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '곧 시작됩니다...',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      // 마이크 아이콘 (펄스 애니메이션)
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isRecording ? _pulseAnimation.value : 1.0,
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRecording 
                                  ? const Color(0xFFFF6B6B).withOpacity(0.1)
                                  : const Color(0xFF2F3DA3).withOpacity(0.1),
                                border: Border.all(
                                  color: _isRecording 
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFF2F3DA3),
                                  width: 4,
                                ),
                              ),
                              child: Icon(
                                Icons.mic,
                                size: 80,
                                color: _isRecording 
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFF2F3DA3),
                              ),
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // 진행률 바
                      if (_isRecording)
                        Column(
                          children: [
                            Container(
                              width: 200,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: AnimatedBuilder(
                                animation: _progressAnimation,
                                builder: (context, child) {
                                  return FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: _progressAnimation.value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF6B6B),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '$_recordingDuration / $_maxDuration 초',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      
                      const SizedBox(height: 60),
                      
                      // 안내 텍스트
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _isRecording 
                                ? "'아''아''아' 를 계속해서\n소리내보세요"
                                : "준비하세요",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: _isRecording ? 20 : 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[800],
                                height: 1.4,
                              ),
                            ),
                            if (_isRecording) ...[
                              const SizedBox(height: 12),
                              Text(
                                '일정한 크기로 계속 발음해주세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // 하단 버튼 (수동 중지)
              if (_isRecording)
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextButton(
                    onPressed: _stopRecording,
                    child: const Text(
                      '중지하기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}