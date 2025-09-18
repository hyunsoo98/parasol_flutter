// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../services/parasol_auth_service.dart';

// Amplify 사용 여부에 따라 선택적 import
// import '../services/amplify_api_service.dart';

// AuthProvider 클래스 이름 충돌 방지를 위해 별칭 사용
class CustomAuthProvider with ChangeNotifier {
  String? _userId;
  String? _email;
  String? _name;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;

  // Getters
  String? get userId => _userId;
  String? get email => _email;
  String? get name => _name;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Firebase User 호환성을 위한 getter (displayName 지원)
  ParasolUser? get user => _isAuthenticated ? ParasolUser(
    uid: _userId!,
    email: _email!,
    displayName: _name,
  ) : null;

  CustomAuthProvider() {
    // 초기화 로직
    _initializeAuth();
  }

  // 인증 초기화
  Future<void> _initializeAuth() async {
    await parasolAuth.initialize();
    _updateAuthState();

    // 인증 상태 변경 리스너
    parasolAuth.authStateChanges.listen((_) {
      _updateAuthState();
    });
  }

  // 인증 상태 업데이트
  void _updateAuthState() {
    _isAuthenticated = parasolAuth.isLoggedIn;
    _userId = parasolAuth.currentUserId;
    _email = parasolAuth.currentEmail;
    _name = parasolAuth.currentName;
    notifyListeners();
  }

  // 로그인
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await parasolAuth.login(
        email: email,
        password: password,
      );

      if (result['success'] == true) {
        _updateAuthState();
      } else {
        _errorMessage = result['error'];
        _isAuthenticated = false;
      }
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

  // 회원가입
  Future<void> createUserWithEmailAndPassword(String email, String password, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await parasolAuth.register(
        email: email,
        password: password,
        name: name,
      );

      if (result['success'] == true) {
        // 회원가입 성공 - 자동 로그인 하지 않음
        _errorMessage = null;
      } else {
        _errorMessage = result['error'];
      }
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
      await parasolAuth.logout();
      _updateAuthState();
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