import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/user.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cafe24CustomerAuthService 전역 Provider
final cafe24CustomerAuthServiceProvider =
    Provider<Cafe24CustomerAuthService>((ref) {
  return Cafe24CustomerAuthService();
});

/// 수지씨앤엘 쇼핑몰(suzicnl.com) 백그라운드 AuthSSL 세션 인증 및 고객 연동 서비스
class Cafe24CustomerAuthService {
  final FlutterSecureStorage _storage;

  static const _keySessionUser = 'cafe24_customer_session_user';
  static const _keyMemberDirectory = 'cafe24_member_directory';
  static const _keyMemberPasswords = 'cafe24_member_passwords';

  Cafe24CustomerAuthService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  String get mallDomain => 'suzicnl.com';
  String get mallId => dotenv.env['Mall_ID']?.trim() ?? 'suzicnl1';

  /// 테스트용 데모 계정 로그인
  Future<User> loginWithDemoAccount() async {
    const demoUser = User(
      id: 'suzicnl1',
      name: '수지씨앤엘(테스트)',
      email: 'suzicnl1@suzicnl.com',
      phone: '010-5283-3266',
      zipCode: '12285',
      address1: '경기도 남양주시 진건읍 진건오남로 632-24',
      address2: '수지씨앤엘 물류센터 1층',
      groupName: '수지씨앤엘 정회원',
      points: 3500,
      coupons: 3,
      orders: 2,
      isCafe24Member: true,
    );
    await saveSession(demoUser);
    return demoUser;
  }

  String? _sanitizePhone(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 11) return null;
    return raw.trim();
  }

  /// 세션 영구 저장 (기존에 저장된 전화번호/주소/이메일/이름이 있으면 누락 방지 병합)
  Future<User> saveSession(User user) async {
    User mergedUser = user.copyWith(phone: _sanitizePhone(user.phone));
    try {
      final dirRaw = await _storage.read(key: _keyMemberDirectory);
      final Map<String, dynamic> dir = dirRaw != null && dirRaw.isNotEmpty
          ? (jsonDecode(dirRaw) as Map<String, dynamic>)
          : <String, dynamic>{};

      final prevMap = dir[user.id];
      if (prevMap is Map<String, dynamic>) {
        final prevUser = User.fromJson(prevMap);
        final validNewPhone = _sanitizePhone(user.phone);
        final validPrevPhone = _sanitizePhone(prevUser.phone);
        mergedUser = user.copyWith(
          phone: validNewPhone ?? validPrevPhone,
          zipCode: (user.zipCode != null && user.zipCode!.trim().isNotEmpty)
              ? user.zipCode
              : prevUser.zipCode,
          address1: (user.address1 != null && user.address1!.trim().isNotEmpty)
              ? user.address1
              : prevUser.address1,
          address2: (user.address2 != null && user.address2!.trim().isNotEmpty)
              ? user.address2
              : prevUser.address2,
          email: (user.email.isNotEmpty && !user.email.endsWith('@suzicnl.com'))
              ? user.email
              : (prevUser.email.isNotEmpty ? prevUser.email : user.email),
          name: (user.name.isNotEmpty && user.name != user.id)
              ? user.name
              : (prevUser.name.isNotEmpty ? prevUser.name : user.name),
        );
      }

      final jsonMap = mergedUser.toJson();
      if (_sanitizePhone(mergedUser.phone) == null) {
        jsonMap['phone'] = null;
      }
      dir[mergedUser.id] = jsonMap;
      await _storage.write(
        key: _keyMemberDirectory,
        value: jsonEncode(dir),
      );
      await _storage.write(
        key: _keySessionUser,
        value: jsonEncode(jsonMap),
      );
    } catch (_) {}
    return mergedUser;
  }

  /// 저장된 로그인 세션 복원 (자동 로그인)
  Future<User?> restoreSession() async {
    try {
      final raw = await _storage.read(key: _keySessionUser);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (_sanitizePhone(decoded['phone']?.toString()) == null) {
            decoded['phone'] = null;
          }
          return User.fromJson(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Cafe24 AuthSSL 회원정보 수정(memberEditAction)에 필요한 비밀번호 암호화 보관
  Future<void> saveMemberPassword(String memberId, String password) async {
    if (memberId.trim().isEmpty || password.isEmpty) return;
    try {
      final raw = await _storage.read(key: _keyMemberPasswords);
      final Map<String, dynamic> map = raw != null && raw.isNotEmpty
          ? (jsonDecode(raw) as Map<String, dynamic>)
          : <String, dynamic>{};
      map[memberId.trim()] = password;
      await _storage.write(
        key: _keyMemberPasswords,
        value: jsonEncode(map),
      );
    } catch (_) {}
  }

  /// 저장된 회원 비밀번호 조회 (AuthSSL /member/modify.html 자동 제출용)
  Future<String?> getMemberPassword(String memberId) async {
    if (memberId.trim().isEmpty) return null;
    try {
      final raw = await _storage.read(key: _keyMemberPasswords);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final pw = map[memberId.trim()]?.toString();
        if (pw != null && pw.isNotEmpty) return pw;
      }
    } catch (_) {}
    return null;
  }

  /// 세션 삭제 (로그아웃 및 백그라운드 WebKit 쿠키 초기화)
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _keySessionUser);
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
  }
}
