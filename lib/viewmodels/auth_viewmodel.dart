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
  Future<void> setAuthenticatedUser(User user, {String? password}) async {
    if (password != null && password.isNotEmpty) {
      await _authService.saveMemberPassword(user.id, password);
    }
    final merged = await _authService.saveSession(user);
    state = merged;
  }

  /// Cafe24 AuthSSL 회원정보 수정(memberEditAction)을 위한 회원 비밀번호 조회
  Future<String?> getMemberPassword(String memberId) {
    return _authService.getMemberPassword(memberId);
  }

  /// Cafe24 AuthSSL 회원정보 수정(memberEditAction)을 위한 회원 비밀번호 저장
  Future<void> saveMemberPassword(String memberId, String password) {
    return _authService.saveMemberPassword(memberId, password);
  }

  /// 주문서 또는 회원정보 화면에서 사용자가 입력/수정한 배송지 주소를 로컬 회원 프로필에 안전하게 저장
  Future<void> updateMemberAddress({
    required String zipCode,
    required String address1,
    required String address2,
    String? phone,
  }) async {
    final current = state;
    if (current == null) return;
    final cleanZip = zipCode.trim();
    final cleanAddr1 = address1.trim();
    final cleanAddr2 = address2.trim();
    final cleanPhone = (phone != null && phone.trim().isNotEmpty)
        ? phone.trim()
        : (current.phone ?? '');

    final updated = current.copyWith(
      zipCode: cleanZip.isNotEmpty ? cleanZip : current.zipCode,
      address1: cleanAddr1.isNotEmpty ? cleanAddr1 : current.address1,
      address2: cleanAddr2.isNotEmpty ? cleanAddr2 : current.address2,
      phone: cleanPhone.isNotEmpty ? cleanPhone : current.phone,
    );
    final saved = await _authService.saveSession(updated);
    state = saved;
  }

  /// 1초 데모 로그인 (테스트용)
  Future<void> loginWithDemo() async {
    final user = await _authService.loginWithDemoAccount();
    state = user;
  }

  /// 주문 완료 시 마이페이지 통계(주문건수 증가) 실시간 업데이트
  Future<void> recordCompletedOrder() async {
    final current = state;
    if (current == null) return;
    final updated = current.copyWith(orders: current.orders + 1);
    final saved = await _authService.saveSession(updated);
    state = saved;
  }

  /// 회원탈퇴 완료 후 로컬 보안 세션 및 쿠키 완전 파기
  Future<void> withdrawAccount() async {
    await _authService.clearSession();
    state = null;
  }

  /// 로그아웃 (보안 저장소 세션 및 WebKit 쿠키 삭제)
  Future<void> logout() async {
    await _authService.clearSession();
    state = null;
  }
}

final authProvider = NotifierProvider<AuthViewModel, User?>(AuthViewModel.new);
