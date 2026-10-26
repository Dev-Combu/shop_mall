import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';

/// BottomNavigationBar가 항상 유지되는 Shell 레이아웃
class ScaffoldShellLayout extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldShellLayout({
    super.key,
    required this.navigationShell,
  });

  static const List<_NavItem> _navItems = [
    _NavItem(label: '홈',       icon: Icons.home_outlined,     activeIcon: Icons.home,           path: '/'),
    _NavItem(label: '카테고리', icon: Icons.category_outlined,  activeIcon: Icons.category,       path: '/category'),
    _NavItem(label: '장바구니', icon: Icons.shopping_cart_outlined, activeIcon: Icons.shopping_cart, path: '/cart'),
    _NavItem(label: '마이페이지', icon: Icons.person_outline,   activeIcon: Icons.person,         path: '/mypage'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(bottomNavProvider, (previous, next) {
      if (next != navigationShell.currentIndex) {
        navigationShell.goBranch(
          next,
          initialLocation: next == navigationShell.currentIndex,
        );
      }
    });

    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => _onTap(context, ref, index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: const Color(0xFF94A3B8),
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
    ref.read(bottomNavProvider.notifier).setIndex(index);
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

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
