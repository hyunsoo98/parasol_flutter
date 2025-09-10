// lib/services/amplify_auth_service.dart
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class AmplifyAuthService {
  static AmplifyAuthService? _instance;
  AmplifyAuthService._internal();
  factory AmplifyAuthService() {
    _instance ??= AmplifyAuthService._internal();
    return _instance!;
  }

  /// 사용자 회원가입
  Future<SignUpResult> signUp({
    required String username,
    required String password,
    required String email,
    String? phoneNumber,
  }) async {
    try {
      final userAttributes = <AuthUserAttributeKey, String>{
        AuthUserAttributeKey.email: email,
        if (phoneNumber != null) AuthUserAttributeKey.phoneNumber: phoneNumber,
      };

      final result = await Amplify.Auth.signUp(
        username: username,
        password: password,
        options: SignUpOptions(
          userAttributes: userAttributes,
        ),
      );

      return result;
    } on AuthException catch (e) {
      safePrint('Sign up failed: ${e.message}');
      rethrow;
    }
  }

  /// 이메일 인증 확인
  Future<SignUpResult> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    try {
      final result = await Amplify.Auth.confirmSignUp(
        username: username,
        confirmationCode: confirmationCode,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Confirm sign up failed: ${e.message}');
      rethrow;
    }
  }

  /// 로그인
  Future<SignInResult> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final result = await Amplify.Auth.signIn(
        username: username,
        password: password,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Sign in failed: ${e.message}');
      rethrow;
    }
  }

  /// Google 소셜 로그인
  Future<SignInResult> signInWithGoogle() async {
    try {
      final result = await Amplify.Auth.signInWithWebUI(
        provider: AuthProvider.google,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Google sign in failed: ${e.message}');
      rethrow;
    }
  }

  /// 로그아웃
  Future<SignOutResult> signOut() async {
    try {
      final result = await Amplify.Auth.signOut();
      return result;
    } on AuthException catch (e) {
      safePrint('Sign out failed: ${e.message}');
      rethrow;
    }
  }

  /// 현재 사용자 정보 조회
  Future<AuthUser> getCurrentUser() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user;
    } on AuthException catch (e) {
      safePrint('Get current user failed: ${e.message}');
      rethrow;
    }
  }

  /// 사용자 속성 조회
  Future<List<AuthUserAttribute>> fetchUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return attributes;
    } on AuthException catch (e) {
      safePrint('Fetch user attributes failed: ${e.message}');
      rethrow;
    }
  }

  /// 사용자 속성 업데이트
  Future<Map<AuthUserAttributeKey, UpdateUserAttributeResult>>
      updateUserAttributes({
    required Map<AuthUserAttributeKey, String> attributes,
  }) async {
    try {
      final result = await Amplify.Auth.updateUserAttributes(
        attributes: attributes,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Update user attributes failed: ${e.message}');
      rethrow;
    }
  }

  /// 비밀번호 재설정 요청
  Future<ResetPasswordResult> resetPassword({
    required String username,
  }) async {
    try {
      final result = await Amplify.Auth.resetPassword(username: username);
      return result;
    } on AuthException catch (e) {
      safePrint('Reset password failed: ${e.message}');
      rethrow;
    }
  }

  /// 비밀번호 재설정 확인
  Future<ResetPasswordResult> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) async {
    try {
      final result = await Amplify.Auth.confirmResetPassword(
        username: username,
        newPassword: newPassword,
        confirmationCode: confirmationCode,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Confirm reset password failed: ${e.message}');
      rethrow;
    }
  }

  /// 현재 로그인 상태 확인
  Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } on AuthException catch (e) {
      safePrint('Check sign in status failed: ${e.message}');
      return false;
    }
  }

  /// 사용자 세션 정보 조회
  Future<AuthSession> fetchAuthSession() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session;
    } on AuthException catch (e) {
      safePrint('Fetch auth session failed: ${e.message}');
      rethrow;
    }
  }

  /// Cognito 사용자 세션 정보 조회 (토큰 포함)
  Future<CognitoAuthSession> fetchCognitoAuthSession() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession(
        options: const CognitoSessionOptions(
          getAWSCredentials: true,
        ),
      ) as CognitoAuthSession;
      return session;
    } on AuthException catch (e) {
      safePrint('Fetch cognito auth session failed: ${e.message}');
      rethrow;
    }
  }

  /// 인증 상태 변화 스트림
  Stream<AuthHubEvent> get authStateChanges {
    return Amplify.Hub.listen(HubChannel.Auth);
  }
}