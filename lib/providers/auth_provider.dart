// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';

// AuthProvider 클래스 이름 충돌 방지를 위해 별칭 사용
class CustomAuthProvider with ChangeNotifier {
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;

  // Getters
  String? get userId => _userId;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  // Firebase User 호환성을 위한 임시 getter
  Map<String, dynamic>? get user => _isAuthenticated ? {'uid': _userId} : null;

  CustomAuthProvider() {
    // 초기화 로직
    _checkAuthStatus();
  }

  // 인증 상태 확인
  void _checkAuthStatus() {
    // TODO: SharedPreferences 또는 기타 방식으로 로그인 상태 확인
    _isAuthenticated = false; // 임시로 false
    notifyListeners();
  }

  // 로그인 (임시 구현)
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: AWS Cognito 대신 다른 인증 방식 구현
      await Future.delayed(Duration(seconds: 1)); // 시뮬레이션
      
      _userId = email; // 임시로 email을 ID로 사용
      _isAuthenticated = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _isAuthenticated = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  // 구글 로그인 (비활성화)
  Future<void> signInWithGoogle() async {
    _errorMessage = 'Google 로그인은 현재 지원되지 않습니다.';
    notifyListeners();
  }

  // 회원가입 (임시 구현)
  Future<void> createUserWithEmailAndPassword(String email, String password, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: 실제 회원가입 로직 구현
      await Future.delayed(Duration(seconds: 1)); // 시뮬레이션
      
      _userId = email;
      _isAuthenticated = true;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 로그아웃
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      _userId = null;
      _isAuthenticated = false;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 비밀번호 재설정 (비활성화)
  Future<void> sendPasswordResetEmail(String email) async {
    _errorMessage = '비밀번호 재설정은 현재 지원되지 않습니다.';
    notifyListeners();
  }

  // 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // 호환성을 위한 기존 메서드들
  Future<void> login(String email, String password) async {
    await signInWithEmailAndPassword(email, password);
  }

  Future<void> logout() async {
    await signOut();
  }
}