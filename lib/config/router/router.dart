import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/views/cart.dart';
import 'package:shopmall/views/category.dart';
import 'package:shopmall/views/category_products.dart';
import 'package:shopmall/views/home.dart';
import 'package:shopmall/views/login.dart';
import 'package:shopmall/views/my_page.dart';
import 'package:shopmall/views/product.dart';
import 'package:shopmall/views/profile.dart';
import 'package:shopmall/views/share/scaffold_shell_layout.dart';
import 'package:shopmall/views/search.dart';
import 'package:shopmall/views/signup.dart';
import 'package:shopmall/views/withdrawal.dart';

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

        // ── Branch 2: 장바구니 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cart',
              name: 'cart',
              builder: (context, state) => const CartPage(),
            ),
          ],
        ),

        // ── Branch 3: 마이페이지 ──
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
    // (예: 검색, 상품 상세, 로그인, 회원가입 등 전체화면)
    // ──────────────────────────────────────────────────────────
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/category/products',
      name: 'category-products',
      builder: (context, state) {
        final name = state.uri.queryParameters['name'] ?? '전체보기';
        final noStr = state.uri.queryParameters['no'];
        final categoryNo = noStr != null ? int.tryParse(noStr) : null;
        return CategoryProductsPage(
          categoryName: name,
          categoryNo: categoryNo,
        );
      },
    ),
    GoRoute(
      path: '/products/:id',
      name: 'product-detail',
      builder: (context, state) {
        final productId = state.pathParameters['id']!;
        final product = state.extra as Product?;
        return ProductPage(productId: productId, initialProduct: product);
      },
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const SignUpPage(),
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/withdrawal',
      name: 'withdrawal',
      builder: (context, state) => const WithdrawalPage(),
    ),
  ],

  // 에러 화면
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('페이지를 찾을 수 없습니다: ${state.error}'),
    ),
  ),
);
