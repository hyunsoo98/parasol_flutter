// Flutter 간단한 인증 서비스

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SimpleAuthService {
  static const String baseUrl = 'https://YOUR_API_ID.execute-api.us-west-1.amazonaws.com/prod';

  // 회원가입
  Future<AuthResult> register({
    required String email,
    required String password,
    String? phone,
    String? name,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'phone': phone ?? '',
        'name': name ?? '',
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);

      // 세션 토큰 저장
      await _saveUserSession(
        result['userId'],
        result['email'],
        result['name'] ?? '',
        result['sessionToken'],
      );

      return AuthResult(
        success: true,
        userId: result['userId'],
        email: result['email'],
        name: result['name'],
        message: result['message'],
      );
    } else {
      final error = jsonDecode(response.body);
      return AuthResult(
        success: false,
        message: error['error'],
      );
    }
  }

  // 로그인
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);

      // 세션 토큰 저장
      await _saveUserSession(
        result['userId'],
        result['email'],
        result['name'] ?? '',
        result['sessionToken'],
      );

      return AuthResult(
        success: true,
        userId: result['userId'],
        email: result['email'],
        name: result['name'],
        message: result['message'],
      );
    } else {
      final error = jsonDecode(response.body);
      return AuthResult(
        success: false,
        message: error['error'],
      );
    }
  }

  // 세션 저장
  Future<void> _saveUserSession(String userId, String email, String name, String sessionToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    await prefs.setString('email', email);
    await prefs.setString('name', name);
    await prefs.setString('sessionToken', sessionToken);
    await prefs.setBool('isLoggedIn', true);
  }

  // 현재 로그인 상태 확인
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  // 현재 사용자 정보
  Future<UserInfo?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();

    if (!await isLoggedIn()) return null;

    return UserInfo(
      userId: prefs.getString('userId') ?? '',
      email: prefs.getString('email') ?? '',
      name: prefs.getString('name') ?? '',
    );
  }

  // 로그아웃
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // API 호출용 헤더 (세션 토큰 포함)
  Future<Map<String, String>> getApiHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('sessionToken') ?? '';

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $sessionToken',
    };
  }
}

// 인증 결과 클래스
class AuthResult {
  final bool success;
  final String? userId;
  final String? email;
  final String? name;
  final String message;

  AuthResult({
    required this.success,
    this.userId,
    this.email,
    this.name,
    required this.message,
  });
}

// 사용자 정보 클래스
class UserInfo {
  final String userId;
  final String email;
  final String name;

  UserInfo({
    required this.userId,
    required this.email,
    required this.name,
  });
}

// 사용 예시
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = SimpleAuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isLoading = false;

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);

    try {
      AuthResult result;

      if (_isRegisterMode) {
        // 회원가입
        result = await _authService.register(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text.isNotEmpty ? _nameController.text : null,
        );
      } else {
        // 로그인
        result = await _authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      if (result.success) {
        // 성공 - 메인 화면으로 이동
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        // 실패 - 에러 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? '회원가입' : '로그인'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: '이메일'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
            if (_isRegisterMode)
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: '이름 (선택)'),
              ),
            SizedBox(height: 20),

            if (_isLoading)
              CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _handleAuth,
                child: Text(_isRegisterMode ? '회원가입' : '로그인'),
              ),

            TextButton(
              onPressed: () {
                setState(() => _isRegisterMode = !_isRegisterMode);
              },
              child: Text(_isRegisterMode ? '로그인으로 돌아가기' : '회원가입'),
            ),
          ],
        ),
      ),
    );
  }
}