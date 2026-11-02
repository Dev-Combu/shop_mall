import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/cafe24_customer_auth_service.dart';

class AuthViewModel extends Notifier<User?> {
  late final Cafe24CustomerAuthService _authService;
  late final Cafe24ApiService _apiService;

  @override
  User? build() {
    _authService = ref.watch(cafe24CustomerAuthServiceProvider);
    _apiService = ref.watch(cafe24ApiServiceProvider);
    // 앱 시작 시 저장된 수지씨앤엘 세션 자동 복원
    _restoreSession();
    return null;
  }

  Future<void> _restoreSession() async {
    final storedUser = await _authService.restoreSession();
    if (storedUser != null) {
      state = storedUser;
      _enrichUserAddressFromCafe24(storedUser);
    }
  }

  /// 수지씨앤엘 쇼핑몰 인증(로그인/회원가입) 완료 후 사용자 세션 반영
  Future<void> setAuthenticatedUser(User user, {String? password}) async {
    if (password != null && password.isNotEmpty) {
      await _authService.saveMemberPassword(user.id, password);
    }
    final merged = await _authService.saveSession(user);
    state = merged;
    _enrichUserAddressFromCafe24(merged);
  }

  /// Cafe24 AuthSSL 회원정보 수정(memberEditAction)을 위한 회원 비밀번호 조회
  Future<String?> getMemberPassword(String memberId) {
    return _authService.getMemberPassword(memberId);
  }

  /// Cafe24 AuthSSL 회원정보 수정(memberEditAction)을 위한 회원 비밀번호 저장
  Future<void> saveMemberPassword(String memberId, String password) {
    return _authService.saveMemberPassword(memberId, password);
  }

  /// Cafe24 Admin API(/customers, /shippingaddresses)에서 회원의 주소 정보가 있으면 보강
  Future<void> _enrichUserAddressFromCafe24(User user) async {
    if (user.id.isEmpty || user.id == 'suzicnl1') return;
    try {
      final info = await _apiService.fetchCustomerAddressInfo(user.id);
      if (info != null) {
        final current = state ?? user;
        final updated = current.copyWith(
          zipCode: (info.zipCode != null && info.zipCode!.isNotEmpty)
              ? info.zipCode
              : current.zipCode,
          address1: (info.address1 != null && info.address1!.isNotEmpty)
              ? info.address1
              : current.address1,
          address2: (info.address2 != null && info.address2!.isNotEmpty)
              ? info.address2
              : current.address2,
          phone: (info.phone != null && info.phone!.isNotEmpty)
              ? info.phone
              : current.phone,
          name: (info.name != null && info.name!.isNotEmpty)
              ? info.name
              : current.name,
        );
        final saved = await _authService.saveSession(updated);
        state = saved;
      }
    } catch (_) {}
  }

  /// 주문서 또는 회원정보 화면에서 사용자가 입력/수정한 배송지 주소를 회원 프로필 및 Cafe24 서버 DB에 저장
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

    // Cafe24 서버 회원 배송지 주소록 DB에도 비동기 반영
    if (saved.id.isNotEmpty && saved.id != 'suzicnl1') {
      await _apiService.upsertCustomerShippingAddress(
        memberId: saved.id,
        recipientName: saved.name,
        phone: cleanPhone,
        zipCode: cleanZip,
        address1: cleanAddr1,
        address2: cleanAddr2,
      );
    }
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

  /// 주문 완료 시 주문 건수 증가 및 사용한 포인트 차감 반영
  Future<void> recordCompletedOrder({int usedPoints = 0}) async {
    final current = state;
    if (current == null) return;
    final nextPoints = (current.points - usedPoints).clamp(0, 999999999);
    final updated = current.copyWith(
      orders: current.orders + 1,
      points: nextPoints,
    );
    await _authService.saveSession(updated);
    state = updated;
  }
}

final authProvider = NotifierProvider<AuthViewModel, User?>(
  AuthViewModel.new,
);
