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
      groupName: '수지씨앤엘 정회원',
      points: 3500,
      coupons: 3,
      orders: 2,
      isCafe24Member: true,
    );
    await saveSession(demoUser);
    return demoUser;
  }

  /// 세션 영구 저장 (기존에 저장된 전화번호/이메일/이름이 있으면 누락 방지 병합)
  Future<User> saveSession(User user) async {
    User mergedUser = user;
    try {
      final dirRaw = await _storage.read(key: _keyMemberDirectory);
      final Map<String, dynamic> dir = dirRaw != null && dirRaw.isNotEmpty
          ? (jsonDecode(dirRaw) as Map<String, dynamic>)
          : <String, dynamic>{};

      final prevMap = dir[user.id];
      if (prevMap is Map<String, dynamic>) {
        final prevUser = User.fromJson(prevMap);
        mergedUser = user.copyWith(
          phone: (user.phone != null && user.phone!.trim().isNotEmpty)
              ? user.phone
              : prevUser.phone,
          email: (user.email.isNotEmpty && !user.email.endsWith('@suzicnl.com'))
              ? user.email
              : (prevUser.email.isNotEmpty ? prevUser.email : user.email),
          name: (user.name.isNotEmpty && user.name != user.id)
              ? user.name
              : (prevUser.name.isNotEmpty ? prevUser.name : user.name),
        );
      }

      dir[mergedUser.id] = mergedUser.toJson();
      await _storage.write(
        key: _keyMemberDirectory,
        value: jsonEncode(dir),
      );
      await _storage.write(
        key: _keySessionUser,
        value: jsonEncode(mergedUser.toJson()),
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
          return User.fromJson(decoded);
        }
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
