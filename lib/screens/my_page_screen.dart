import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as local_auth;

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<local_auth.CustomAuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text('마이페이지'),
            backgroundColor: const Color(0xFF2F3DA3),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 프로필 섹션
                _buildProfileSection(user),
                const SizedBox(height: 24),

                // 검사 기록 섹션
                _buildSectionCard(
                  title: '검사 기록',
                  icon: Icons.history,
                  children: [
                    _buildMenuItem(
                      icon: Icons.assessment,
                      title: '최근 검사 결과',
                      subtitle: '지난 검사 결과를 확인하세요',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.trending_up,
                      title: '검사 통계',
                      subtitle: '검사 기록 및 변화 추이',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 설정 섹션
                _buildSectionCard(
                  title: '설정',
                  icon: Icons.settings,
                  children: [
                    _buildMenuItem(
                      icon: Icons.notifications,
                      title: '알림 설정',
                      subtitle: '검사 알림 및 리마인더 설정',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.privacy_tip,
                      title: '개인정보 관리',
                      subtitle: '개인정보 수정 및 관리',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.help,
                      title: '도움말',
                      subtitle: '사용법 및 자주 묻는 질문',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 기타 섹션
                _buildSectionCard(
                  title: '기타',
                  icon: Icons.more_horiz,
                  children: [
                    _buildMenuItem(
                      icon: Icons.info,
                      title: '앱 정보',
                      subtitle: '버전 정보 및 라이센스',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.feedback,
                      title: '문의하기',
                      subtitle: '궁금한 점이나 문의사항',
                      onTap: () {
                        // 기능 미구현
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 로그아웃 버튼
                _buildLogoutButton(context, authProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileSection(user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFF2F3DA3),
            backgroundImage: user?.photoURL != null
                ? NetworkImage(user!.photoURL!)
                : null,
            child: user?.photoURL == null
                ? Text(
                    _getUserInitial(user),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            _getUserDisplayName(user),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user?.email ?? '',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2F3DA3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '건강한 일상을 함께해요!',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF2F3DA3),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F3DA3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF2F3DA3),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, local_auth.CustomAuthProvider authProvider) {
    return Container(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          _showLogoutDialog(context, authProvider);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout, size: 20),
            SizedBox(width: 8),
            Text(
              '로그아웃',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, local_auth.CustomAuthProvider authProvider) {
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
                Navigator.of(context).pop(); // 마이페이지에서 뒤로가기
                authProvider.signOut();
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
    
    if (user?.email != null && user!.email!.isNotEmpty) {
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
    
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email![0].toUpperCase();
    }
    
    return 'U';
  }
}