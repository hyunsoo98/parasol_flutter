// lib/services/auth_service.dart
// Firebase 기반 인증 서비스를 AWS Cognito/Parasol 기반으로 대체

import 'dart:async';
import 'parasol_auth_service.dart';

class AuthService {
  // ParasolAuthService 인스턴스 사용
  final ParasolAuthService _parasolAuth = parasolAuth;

  // 현재 사용자 스트림 (ParasolAuthService의 상태 변경을 스트림으로 감싸기)
  Stream<String?> get authStateChanges async* {
    yield _parasolAuth.currentUserId;
    // 실제 상태 변경 감지를 위해서는 ParasolAuthService에 StreamController를 추가해야 함
  }

  // 현재 사용자 ID
  String? get currentUserId => _parasolAuth.currentUserId;

  // 로그인 상태 확인
  Future<bool> isLoggedIn() async {
    return _parasolAuth.isLoggedIn;
  }

  // 이메일/비밀번호 로그인
  Future<Map<String, dynamic>> signInWithEmailAndPassword(String email, String password) async {
    try {
      final result = await _parasolAuth.login(email: email, password: password);
      if (result['success'] == true) {
        return result;
      } else {
        throw Exception(result['error'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('로그인 실패: ${e.toString()}');
    }
  }

  // 이메일/비밀번호 회원가입
  Future<Map<String, dynamic>> createUserWithEmailAndPassword(String email, String password, String name) async {
    try {
      final result = await _parasolAuth.register(email: email, password: password, name: name);
      if (result['success'] == true) {
        return result;
      } else {
        throw Exception(result['error'] ?? 'Registration failed');
      }
    } catch (e) {
      throw Exception('회원가입 실패: ${e.toString()}');
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      await _parasolAuth.logout();
    } catch (e) {
      throw Exception('로그아웃 실패: ${e.toString()}');
    }
  }

  // JWT 토큰 가져오기
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      return _parasolAuth.accessToken;
    } catch (e) {
      throw Exception('토큰 가져오기 실패: ${e.toString()}');
    }
  }

  // 토큰과 함께 사용할 헤더 생성
  Future<Map<String, String>> getAuthHeaders() async {
    return _parasolAuth.getAuthenticatedHeaders();
  }

  // 사용자 정보
  Map<String, dynamic>? get userInfo => _parasolAuth.userInfo;

  // 비밀번호 재설정 (미구현 - 필요시 API 추가)
  Future<void> sendPasswordResetEmail(String email) async {
    throw Exception('비밀번호 재설정은 현재 지원되지 않습니다.');
  }

  // 사용자 프로필 업데이트 (미구현 - 필요시 API 추가)
  Future<void> updateUserProfile({String? displayName, String? photoURL}) async {
    throw Exception('프로필 업데이트는 현재 지원되지 않습니다.');
  }

  // Google 로그인 (미구현 - 필요시 OAuth 추가)
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    throw Exception('Google 로그인은 현재 지원되지 않습니다.');
  }
}