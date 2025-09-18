// lib/services/parasol_auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/aws_config.dart';

// Firebase User와 호환되는 클래스
class ParasolUser {
  final String uid;
  final String email;
  final String? displayName;

  ParasolUser({
    required this.uid,
    required this.email,
    this.displayName,
  });
}

class ParasolAuthService {
  static const String _sessionTokenKey = 'parasol_session_token';
  static const String _userIdKey = 'parasol_user_id';
  static const String _emailKey = 'parasol_email';
  static const String _nameKey = 'parasol_name';

  // 현재 로그인된 사용자 정보
  String? _sessionToken;
  String? _userId;
  String? _email;
  String? _name;

  // 인증 상태 스트림 컨트롤러
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateChanges => _authStateController.stream;

  // 현재 사용자 정보 getter
  String? get currentUserId => _userId;
  String? get currentEmail => _email;
  String? get currentName => _name;
  String? get sessionToken => _sessionToken;

  // 로그인 상태 확인
  bool get isLoggedIn => _sessionToken != null && _userId != null;

  // 초기화 - 저장된 세션 토큰 로드
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString(_sessionTokenKey);
    _userId = prefs.getString(_userIdKey);
    _email = prefs.getString(_emailKey);
    _name = prefs.getString(_nameKey);

    // 세션이 유효한지 확인 (선택사항)
    if (_sessionToken != null) {
      _authStateController.add(true);
    }
  }

  // 회원가입
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(AWSConfig.getRegisterUrl()),
        headers: AWSConfig.defaultHeaders,
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // 회원가입 성공
        return {
          'success': true,
          'message': responseData['message'] ?? '회원가입이 완료되었습니다.',
          'user_id': responseData['user_id'],
        };
      } else {
        // 회원가입 실패
        return {
          'success': false,
          'error': responseData['error'] ?? '회원가입에 실패했습니다.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '네트워크 오류가 발생했습니다: ${e.toString()}',
      };
    }
  }

  // 로그인
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(AWSConfig.getLoginUrl()),
        headers: AWSConfig.defaultHeaders,
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // 로그인 성공
        _sessionToken = responseData['session_token'];
        _userId = responseData['user_id'];
        _email = email;
        _name = responseData['name'];

        // 로컬 저장소에 저장
        await _saveSession();

        // 인증 상태 변경 알림
        _authStateController.add(true);

        return {
          'success': true,
          'message': '로그인 성공',
          'user_id': _userId,
          'session_token': _sessionToken,
          'name': _name,
        };
      } else {
        // 로그인 실패
        return {
          'success': false,
          'error': responseData['error'] ?? '로그인에 실패했습니다.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '네트워크 오류가 발생했습니다: ${e.toString()}',
      };
    }
  }

  // 로그아웃
  Future<void> logout() async {
    _sessionToken = null;
    _userId = null;
    _email = null;
    _name = null;

    // 로컬 저장소에서 삭제
    await _clearSession();

    // 인증 상태 변경 알림
    _authStateController.add(false);
  }

  // 세션 저장
  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessionToken != null) await prefs.setString(_sessionTokenKey, _sessionToken!);
    if (_userId != null) await prefs.setString(_userIdKey, _userId!);
    if (_email != null) await prefs.setString(_emailKey, _email!);
    if (_name != null) await prefs.setString(_nameKey, _name!);
  }

  // 세션 삭제
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_nameKey);
  }

  // 인증 헤더 생성
  Map<String, String> getAuthHeaders() {
    final headers = Map<String, String>.from(AWSConfig.defaultHeaders);
    if (_sessionToken != null) {
      headers['Authorization'] = 'Bearer $_sessionToken';
    }
    return headers;
  }

  // 인증이 필요한 API 호출을 위한 헤더
  Map<String, String> getAuthenticatedHeaders() {
    if (!isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }
    return getAuthHeaders();
  }

  // 세션 토큰 유효성 검증 (선택사항)
  Future<bool> validateSession() async {
    if (!isLoggedIn) return false;

    try {
      // 간단한 API 호출로 세션 유효성 확인
      // 예: 사용자 정보 조회 등
      // 현재는 기본적으로 true 반환
      return true;
    } catch (e) {
      // 세션이 무효하면 로그아웃
      await logout();
      return false;
    }
  }

  // 리소스 정리
  void dispose() {
    _authStateController.close();
  }

  // 사용자 정보 업데이트 (로컬만)
  Future<void> updateUserInfo({String? name}) async {
    if (name != null) {
      _name = name;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
    }
  }

  // 현재 사용자 정보 맵으로 반환
  Map<String, String?> getCurrentUserInfo() {
    return {
      'user_id': _userId,
      'email': _email,
      'name': _name,
      'session_token': _sessionToken,
    };
  }
}

// 싱글톤 인스턴스
final parasolAuth = ParasolAuthService();