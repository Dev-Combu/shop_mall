import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 바텀 네비게이션 탭 인덱스 상수 (검색 탭 제외: 홈, 카테고리, 장바구니, 마이페이지)
class BottomNavIndex {
  static const int home = 0;
  static const int category = 1;
  static const int cart = 2;
  static const int myPage = 3;
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
