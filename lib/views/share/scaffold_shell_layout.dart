import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';

/// BottomNavigationBar가 항상 유지되는 Shell 레이아웃
/// StatefulShellRoute의 builder로 사용됨
class ScaffoldShellLayout extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldShellLayout({
    super.key,
    required this.navigationShell,
  });

  // 탭 인덱스 ↔ 경로 매핑
  static const List<_NavItem> _navItems = [
    _NavItem(label: '홈',       icon: Icons.home_outlined,     activeIcon: Icons.home,           path: '/'),
    _NavItem(label: '카테고리', icon: Icons.category_outlined,  activeIcon: Icons.category,       path: '/category'),
    _NavItem(label: '검색',     icon: Icons.search_outlined,    activeIcon: Icons.search,         path: '/search'),
    _NavItem(label: '장바구니', icon: Icons.shopping_cart_outlined, activeIcon: Icons.shopping_cart, path: '/cart'),
    _NavItem(label: '마이페이지', icon: Icons.person_outline,   activeIcon: Icons.person,         path: '/mypage'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ViewModel에서 현재 탭 인덱스 읽기
    final currentIndex = ref.watch(bottomNavProvider);

    return Scaffold(
      // 각 탭의 실제 화면 (StatefulShellRoute가 관리)
      body: navigationShell,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => _onTap(context, ref, index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF4CAF50),
        unselectedItemColor: const Color(0xFF9E9E9E),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        backgroundColor: Colors.white,
        elevation: 8,
        items: _navItems
            .map(
              (item) => BottomNavigationBarItem(
                icon: Icon(item.icon),
                activeIcon: Icon(item.activeIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref, int index) {
    // ViewModel 상태 업데이트
    ref.read(bottomNavProvider.notifier).setIndex(index);

    // StatefulShellRoute로 탭 전환 (브랜치 네비게이션 스택 유지)
    navigationShell.goBranch(
      index,
      // 같은 탭을 다시 누르면 해당 탭의 루트로 이동
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// 네비게이션 아이템 모델
class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
  });
}
