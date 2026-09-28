import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/user.dart';

class AuthViewModel extends Notifier<User?> {
  @override
  User? build() {
    // 초기 상태: 로그인 상태로 테스트 (기본 샘플 유저)
    return User(
      id: '1',
      name: '홍길동',
      email: 'hong@example.com',
      points: 2500,
      coupons: 3,
      orders: 2,
    );
  }

  void login() {
    state = User(
      id: '1',
      name: '홍길동',
      email: 'hong@example.com',
      points: 2500,
      coupons: 3,
      orders: 2,
    );
  }

  void logout() {
    state = null;
  }

  void toggleAuth() {
    if (state == null) {
      login();
    } else {
      logout();
    }
  }
}

final authProvider = NotifierProvider<AuthViewModel, User?>(
  AuthViewModel.new,
);
