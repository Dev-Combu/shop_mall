import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/views/cart.dart';
import 'package:shopmall/views/category.dart';
import 'package:shopmall/views/home.dart';
import 'package:shopmall/views/my_page.dart';
import 'package:shopmall/views/product.dart';
import 'package:shopmall/views/scaffold_shell_layout.dart';
import 'package:shopmall/views/search.dart';

/// 앱 전체 라우터 설정
///
/// [StatefulShellRoute.indexedStack]를 사용하여
/// 각 탭(branch)의 네비게이션 스택을 독립적으로 유지하면서
/// BottomNavigationBar가 모든 탭에서 항상 보이도록 구성합니다.
final router = GoRouter(
  initialLocation: '/',

  routes: [
    // ──────────────────────────────────────────────────────────
    // StatefulShellRoute: BottomNavBar 항상 유지
    // ──────────────────────────────────────────────────────────
    StatefulShellRoute.indexedStack(
      // ScaffoldShellLayout이 navigationShell을 받아 바텀바를 렌더링
      builder: (context, state, navigationShell) => ScaffoldShellLayout(
        navigationShell: navigationShell,
      ),

      branches: [
        // ── Branch 0: 홈 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const Home(),
            ),
          ],
        ),

        // ── Branch 1: 카테고리 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/category',
              name: 'category',
              builder: (context, state) => const CategoryPage(),
            ),
          ],
        ),

        // ── Branch 2: 검색 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              name: 'search',
              builder: (context, state) => const SearchPage(),
            ),
          ],
        ),

        // ── Branch 3: 장바구니 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cart',
              name: 'cart',
              builder: (context, state) => const CartPage(),
            ),
          ],
        ),

        // ── Branch 4: 마이페이지 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/mypage',
              name: 'mypage',
              builder: (context, state) => const MyPage(),
            ),
          ],
        ),
      ],
    ),

    // ──────────────────────────────────────────────────────────
    // Shell 밖 라우트: BottomNavBar가 표시되지 않는 화면
    // (예: 상품 상세, 주문 완료 등 전체화면)
    // ──────────────────────────────────────────────────────────
    GoRoute(
      path: '/products/:id',
      name: 'product-detail',
      builder: (context, state) {
        final productId = state.pathParameters['id']!;
        return ProductPage(productId: productId);
      },
    ),
  ],

  // 에러 화면
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('페이지를 찾을 수 없습니다: ${state.error}'),
    ),
  ),
);
