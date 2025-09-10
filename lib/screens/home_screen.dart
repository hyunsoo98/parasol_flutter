// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as local_auth;
import 'phone_mount_guide_screen.dart';
import '../services/diagnosis_flow_service.dart';
import 'my_page_screen.dart';

class HomeScreen extends StatelessWidget {
      const HomeScreen({Key? key}) : super(key: key);

      @override
      Widget build(BuildContext context) {
            return Consumer<local_auth.CustomAuthProvider>(
                  builder: (context, authProvider, child) {
                        final user = authProvider.user;

                        return Scaffold(
                              appBar: AppBar(
                                    title: const Text('파라솔'),
                                    backgroundColor: const Color(0xFF2F3DA3),
                                    foregroundColor: Colors.white,
                                    actions: [
                                          IconButton(
                                                icon: const Icon(Icons.logout),
                                                onPressed: () {
                                                      _showLogoutDialog(context);
                                                },
                                          ),
                                    ],
                              ),
                              body: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                                // 사용자 환영 메시지
                                                Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.all(16),
                                                      decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                                  colors: [const Color(0xFF2F3DA3).withOpacity(0.3), const Color(0xFF2F3DA3).withOpacity(0.1)],
                                                                  begin: Alignment.topLeft,
                                                                  end: Alignment.bottomRight,
                                                            ),
                                                            borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Row(
                                                            children: [
                                                                  InkWell(
                                                                        onTap: () {
                                                                              Navigator.push(
                                                                                    context,
                                                                                    MaterialPageRoute(
                                                                                          builder: (context) => const MyPageScreen(),
                                                                                    ),
                                                                              );
                                                                        },
                                                                        borderRadius: BorderRadius.circular(30),
                                                                        child: CircleAvatar(
                                                                              radius: 30,
                                                                              backgroundColor: const Color(0xFF2F3DA3),
                                                                              backgroundImage: user?['photoURL'] != null
                                                                                  ? NetworkImage(user!['photoURL']!)
                                                                                  : null,
                                                                              child: user?['photoURL'] == null
                                                                                  ? Text(
                                                                                    _getUserInitial(user),
                                                                                    style: const TextStyle(
                                                                                          color: Colors.white,
                                                                                          fontSize: 24,
                                                                                          fontWeight: FontWeight.bold,
                                                                                    ),
                                                                              )
                                                                                  : null,
                                                                        ),
                                                                  ),
                                                                  const SizedBox(width: 16),
                                                                  Expanded(
                                                                        child: Column(
                                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                                              children: [
                                                                                    Text(
                                                                                          '안녕하세요, ${_getUserDisplayName(user)}님!',
                                                                                          style: const TextStyle(
                                                                                                fontSize: 20,
                                                                                                fontWeight: FontWeight.bold,
                                                                                                color: const Color(0xFF2F3DA3),
                                                                                          ),
                                                                                    ),
                                                                                    const SizedBox(height: 4),
                                                                                    Text(
                                                                                          user?['email'] ?? '',
                                                                                          style: TextStyle(
                                                                                                fontSize: 14,
                                                                                                color: Colors.grey[600],
                                                                                          ),
                                                                                    ),
                                                                                    const SizedBox(height: 4),
                                                                                    const Text(
                                                                                          '오늘도 건강한 하루 되세요!',
                                                                                          style: TextStyle(
                                                                                                fontSize: 16,
                                                                                                color: Colors.black87,
                                                                                          ),
                                                                                    ),
                                                                              ],
                                                                        ),
                                                                  ),
                                                            ],
                                                      ),
                                                ),
                                                const SizedBox(height: 32),

                                                const Text(
                                                      '주요 기능',
                                                      style: TextStyle(
                                                            fontSize: 22,
                                                            fontWeight: FontWeight.bold,
                                                      ),
                                                ),
                                                const SizedBox(height: 16),
                                                // 통합 진단 버튼 (메인)
                                                Container(
                                                      width: double.infinity,
                                                      child: _buildMainDiagnosisCard(context),
                                                ),
                                          ],
                                    ),
                              ),
                        );
                  },
            );
      }

      Widget _buildMainDiagnosisCard(BuildContext context) {
            return Card(
                  elevation: 8,
                  child: InkWell(
                        onTap: () {
                              Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                          builder: (context) => const PhoneMountGuideScreen(
                                                nextStep: TestStep.EYE_TRACKING,
                                          ),
                                    ),
                              );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                          colors: [
                                                const Color(0xFF2F3DA3),
                                                const Color(0xFF2F3DA3).withOpacity(0.8),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                    ),
                              ),
                              child: Column(
                                    children: [
                                          Row(
                                                children: [
                                                      Container(
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                                  color: Colors.white.withOpacity(0.2),
                                                                  borderRadius: BorderRadius.circular(12),
                                                            ),
                                                            child: const Icon(
                                                                  Icons.medical_services,
                                                                  size: 32,
                                                                  color: Colors.white,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                            child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                        const Text(
                                                                              '종합 건강 검사',
                                                                              style: TextStyle(
                                                                                    fontSize: 20,
                                                                                    fontWeight: FontWeight.bold,
                                                                                    color: Colors.white,
                                                                              ),
                                                                        ),
                                                                        const SizedBox(height: 4),
                                                                        Text(
                                                                              'AI 기반 파킨슨병 진단',
                                                                              style: TextStyle(
                                                                                    fontSize: 14,
                                                                                    color: Colors.white.withOpacity(0.9),
                                                                              ),
                                                                        ),
                                                                  ],
                                                            ),
                                                      ),
                                                      const Icon(
                                                            Icons.arrow_forward_ios,
                                                            color: Colors.white,
                                                            size: 16,
                                                      ),
                                                ],
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                            Icon(Icons.timer, color: Colors.white, size: 16),
                                                            SizedBox(width: 6),
                                                            Text(
                                                                  '약 5-10분 소요',
                                                                  style: TextStyle(
                                                                        color: Colors.white,
                                                                        fontSize: 12,
                                                                        fontWeight: FontWeight.w500,
                                                                  ),
                                                            ),
                                                      ],
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                                '손가락 움직임 → 음성 분석 → 시선 추적',
                                                style: TextStyle(
                                                      color: Colors.white.withOpacity(0.8),
                                                      fontSize: 12,
                                                ),
                                                textAlign: TextAlign.center,
                                          ),
                                    ],
                              ),
                        ),
                  ),
            );
      }


      void _showLogoutDialog(BuildContext context) {
            showDialog(
                  context: context,
                  builder: (BuildContext context) {
                        return AlertDialog(
                              title: const Text('로그아웃'),
                              content: const Text('정말 로그아웃하시겠습니까?'),
                              actions: [
                                    TextButton(
                                          onPressed: () {
                                                Navigator.of(context).pop();
                                          },
                                          child: const Text('취소'),
                                    ),
                                    TextButton(
                                          onPressed: () {
                                                Navigator.of(context).pop();
                                                Provider.of<local_auth.CustomAuthProvider>(context, listen: false).signOut();
                                          },
                                          child: const Text('로그아웃'),
                                    ),
                              ],
                        );
                  },
            );
      }

      // 안전한 사용자 표시 이름 가져오기
      String _getUserDisplayName(user) {
        if (user?.displayName != null && user!.displayName!.isNotEmpty) {
          return user.displayName!;
        }
        
        if (user?['email'] != null && user!.email!.isNotEmpty) {
          final emailParts = user.email!.split('@');
          if (emailParts.isNotEmpty && emailParts[0].isNotEmpty) {
            return emailParts[0];
          }
        }
        
        return '사용자';
      }

      // 안전한 사용자 이니셜 가져오기
      String _getUserInitial(user) {
        if (user?.displayName != null && user!.displayName!.isNotEmpty) {
          return user.displayName![0].toUpperCase();
        }
        
        if (user?['email'] != null && user!.email!.isNotEmpty) {
          return user.email![0].toUpperCase();
        }
        
        return 'U';
      }
}