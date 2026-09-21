import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 바텀 네비게이션 탭 인덱스 상수
class BottomNavIndex {
  static const int home = 0;
  static const int category = 1;
  static const int search = 2;
  static const int cart = 3;
  static const int myPage = 4;
}

/// 바텀 네비게이션 상태 관리 ViewModel
class BottomNavViewModel extends Notifier<int> {
  @override
  int build() => BottomNavIndex.home; // 초기 탭: 홈

  /// 탭 변경
  void setIndex(int index) {
    state = index;
  }
}

/// 전역 Provider
final bottomNavProvider = NotifierProvider<BottomNavViewModel, int>(
  BottomNavViewModel.new,
);
