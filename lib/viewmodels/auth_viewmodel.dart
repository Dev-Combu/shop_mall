import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/services/cafe24_customer_auth_service.dart';

class AuthViewModel extends Notifier<User?> {
  late final Cafe24CustomerAuthService _authService;

  @override
  User? build() {
    _authService = ref.watch(cafe24CustomerAuthServiceProvider);
    // 앱 시작 시 저장된 수지씨앤엘 세션 자동 복원
    _restoreSession();
    return null;
  }

  Future<void> _restoreSession() async {
    final storedUser = await _authService.restoreSession();
    if (storedUser != null) {
      state = storedUser;
    }
  }

  /// 수지씨앤엘 쇼핑몰 인증(로그인/회원가입) 완료 후 사용자 세션 반영
  Future<void> setAuthenticatedUser(User user) async {
    final merged = await _authService.saveSession(user);
    state = merged;
  }

  /// 1초 데모 로그인 (테스트용)
  Future<void> loginWithDemo() async {
    final user = await _authService.loginWithDemoAccount();
    state = user;
  }

  /// 로그아웃 및 세션 제거
  Future<void> logout() async {
    await _authService.clearSession();
    state = null;
  }

  /// 회원탈퇴 완료 후 로컬 보안 세션 및 쿠키 완전 파기
  Future<void> withdrawAccount() async {
    await _authService.clearSession();
    state = null;
  }
}

final authProvider = NotifierProvider<AuthViewModel, User?>(
  AuthViewModel.new,
);
