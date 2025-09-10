import 'package:flutter/material.dart';
import '../services/diagnosis_flow_service.dart';
import 'finger_tapping_guide_screen.dart';
import 'voice_analysis_screen.dart';
import 'camera_setup_screen.dart';

class PhoneMountGuideScreen extends StatefulWidget {
  final TestStep nextStep;
  
  const PhoneMountGuideScreen({
    Key? key,
    required this.nextStep,
  }) : super(key: key);

  @override
  State<PhoneMountGuideScreen> createState() => _PhoneMountGuideScreenState();
}

class _PhoneMountGuideScreenState extends State<PhoneMountGuideScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late PageController _pageController;
  int _currentStep = 0;

  final List<MountStep> _steps = [
    MountStep(
      title: '안녕하세요!',
      subtitle: '폰 거치 안내를 시작하겠습니다',
      description: '정확한 검사를 위해\n휴대폰을 올바르게 설치하는\n방법을 안내해드리겠습니다.',
      icon: Icons.waving_hand,
      color: Color(0xFF2F3DA3),
      image: 'assets/images/greeting.png',
    ),
    MountStep(
      title: '휴대폰 거치',
      subtitle: '휴대폰을 거치대에 올려주세요',
      description: '휴대폰을 거치대에 수평으로 놓고\n카메라가 정면을 향하도록\n각도를 조정해주세요.',
      icon: Icons.phone_iphone,
      color: Color(0xFF4CAF50),
      image: 'assets/images/phone.png',
    ),
    MountStep(
      title: '거리 조정',
      subtitle: '적정 거리를 맞춰주세요',
      description: '휴대폰과 얼굴 사이의 거리를\n약 30-50cm로 유지하고\n눈높이에 맞춰주세요.',
      icon: Icons.straighten,
      color: Color(0xFFFF9800),
      image: 'assets/images/distance.png',
    ),
    MountStep(
      title: '머리 고정',
      subtitle: '머리를 고정하고 정면을 봐주세요',
      description: '머리를 움직이지 않고\n화면을 정면으로 바라보며\n안정적인 자세를 유지해주세요.',
      icon: Icons.face,
      color: Color(0xFF9C27B0),
      image: 'assets/images/head.png',
    ),
    MountStep(
      title: '준비 완료',
      subtitle: '테스트를 시작할 준비가 되었습니다',
      description: '모든 설정이 완료되었습니다.\n안정적인 자세로 테스트를\n시작해주세요.',
      icon: Icons.check_circle,
      color: Color(0xFF4CAF50),
      image: 'assets/images/ready.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _navigateToNextScreen();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            _buildHeader(),
            
            // 진행 표시줄
            _buildProgressBar(),
            
            // 메인 콘텐츠
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildContent(_steps[index]);
                },
              ),
            ),
            
            // 하단 버튼
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2F3DA3), Color(0xFF4A5FD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Expanded(
            child: Text(
              '폰 거치 가이드',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const CameraSetupScreen(),
              ),
            ),
            child: const Text(
              '건너뛰기',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: List.generate(
          _steps.length,
          (index) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < _steps.length - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? _steps[_currentStep].color
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(MountStep step) {
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // 단계 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: step.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: step.color.withOpacity(0.3),
              ),
            ),
            child: Text(
              '${_steps.indexOf(step) + 1} / ${_steps.length}',
              style: TextStyle(
                color: step.color,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 메인 이미지 영역
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 배경 그라데이션
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        step.color.withOpacity(0.1),
                        step.color.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                
                // 이미지
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: Image.asset(
                      step.image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                step.color.withOpacity(0.3),
                                step.color.withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: step.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(40),
                                border: Border.all(
                                  color: step.color.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                step.icon,
                                size: 40,
                                color: step.color,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
              ],
            ),
          ),
          const SizedBox(height: 30),

          // 제목
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          // 부제목
          Text(
            step.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: step.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),

          // 설명
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }


  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          // 이전 버튼
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2F3DA3),
                  side: const BorderSide(color: Color(0xFF2F3DA3)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '이전',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),

          // 다음/완료 버튼
          Expanded(
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: _steps[_currentStep].color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                _currentStep == _steps.length - 1 ? '완료' : '다음',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _navigateToNextScreen() {
    switch (widget.nextStep) {
      case TestStep.EYE_TRACKING:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const CameraSetupScreen(),
          ),
        );
        break;
      case TestStep.FINGER_TAPPING_GUIDE:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const FingerTappingGuideScreen(),
          ),
        );
        break;
      case TestStep.VOICE_ANALYSIS:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const VoiceAnalysisScreen(),
          ),
        );
        break;
      default:
        Navigator.of(context).pop();
    }
  }
}

class MountStep {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final String image;

  MountStep({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.image,
  });
}
