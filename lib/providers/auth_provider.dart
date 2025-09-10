// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _initAuthListener();
  }

  // Firebase Auth 상태 변화 리스너
  void _initAuthListener() {
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  // 이메일/비밀번호 로그인
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signInWithEmailAndPassword(email, password);
      // 사용자는 authStateChanges 리스너를 통해 자동으로 업데이트됨
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Google 로그인
  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.signInWithGoogle();
      if (result == null) {
        _errorMessage = '로그인이 취소되었습니다.';
      }
      // 사용자는 authStateChanges 리스너를 통해 자동으로 업데이트됨
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 회원가입
  Future<void> createUserWithEmailAndPassword(String email, String password, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.createUserWithEmailAndPassword(email, password);

      // 사용자 이름 업데이트
      if (name.isNotEmpty) {
        await _authService.updateUserProfile(displayName: name);
      }

      // 사용자는 authStateChanges 리스너를 통해 자동으로 업데이트됨
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
      await _authService.signOut();
      // 사용자는 authStateChanges 리스너를 통해 자동으로 업데이트됨
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 비밀번호 재설정
  Future<void> sendPasswordResetEmail(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendPasswordResetEmail(email);
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
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