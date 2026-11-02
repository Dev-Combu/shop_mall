import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/services/cafe24_web_cart_service.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';
import 'package:shopmall/views/cafe24_order_webview.dart';
import 'package:shopmall/views/share/kakao_sync_auth_sheet.dart';
import 'package:shopmall/views/share/naver_auth_sheet.dart';
import 'package:shopmall/views/share/order_complete_dialog.dart';

/// 주문서 진입 및 장바구니 재연결 전 Cafe24 웹뷰 회원 로그인 세션을 검증·복구하는 공통 헬퍼
/// - 1순위: 백그라운드 무자각 자동 복구(카카오/네이버 OAuth 302 또는 AuthSSL ID/PW)
/// - 2순위: OAuth 쿠키 만료·수동 로그아웃 시 해당 계정 방식의 인증 모달/로그인 화면 호출
Future<bool> ensureCheckoutWebSession(
  BuildContext context,
  WidgetRef ref,
) async {
  final user = ref.read(authProvider);
  if (user == null || user.id.isEmpty || user.id == 'suzicnl1') {
    return true;
  }

  final webCartService = ref.read(cafe24WebCartServiceProvider);

  // 이미 웹뷰 로그인 세션이 유효한 경우 즉시 통과
  final alreadyLoggedIn = await webCartService.isWebSessionLoggedIn();
  if (alreadyLoggedIn) {
    if (ref.read(webSessionDisconnectedProvider)) {
      await ref.read(cartProvider.notifier).onWebSessionRestored();
    }
    return true;
  }

  if (!context.mounted) return false;

  // 1단계: 백그라운드 무자각 세션 복구 시도 (로딩 오버레이 표시)
  bool dialogOpen = true;
  BuildContext? dialogCtx;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.primary,
                    ),
                  ),
                  SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      '쇼핑몰 로그인 세션을 확인하고 있습니다...',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      dialogOpen = false;
    }),
  );

  bool recovered = false;
  try {
    final pw = await ref.read(authProvider.notifier).getMemberPassword(user.id);
    recovered = await webCartService.ensureMemberSession(
      user: user,
      password: pw,
      forceSilentAttempt: true,
    );
    if (recovered) {
      await ref.read(cartProvider.notifier).onWebSessionRestored();
    }
  } finally {
    if (dialogOpen && dialogCtx != null && dialogCtx!.mounted) {
      Navigator.of(dialogCtx!).pop();
    } else if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  if (recovered) {
    return true;
  }

  if (!context.mounted) return false;

  // 2단계: 무자각 복구 불가 시(카카오/네이버 웹 쿠키 만료 또는 웹뷰 내 수동 로그아웃) 대화형 재인증 진행
  if (user.id.endsWith('@k')) {
    final reUser = await KakaoSyncAuthSheet.show(context);
    if (reUser != null) {
      await ref.read(authProvider.notifier).setAuthenticatedUser(reUser);
      await ref.read(cartProvider.notifier).onWebSessionRestored();
      return true;
    }
    return false;
  }

  if (user.id.endsWith('@n')) {
    final reUser = await NaverAuthSheet.show(context);
    if (reUser != null) {
      await ref.read(authProvider.notifier).setAuthenticatedUser(reUser);
      await ref.read(cartProvider.notifier).onWebSessionRestored();
      return true;
    }
    return false;
  }

  // 일반 ID/PW 회원: 로그인 페이지에서 재인증 유도
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('쇼핑몰 웹 세션이 만료되어 재로그인이 필요합니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await context.push('/login');
  }

  final nowLoggedIn = await webCartService.isWebSessionLoggedIn();
  if (nowLoggedIn) {
    await ref.read(cartProvider.notifier).onWebSessionRestored();
    return true;
  }
  return false;
}

/// 앱 내 중복 입력 없이 Cafe24 공식 결제창으로 바로 연결하고 완료 시 주문을 기록하는 통합 런처
Future<void> launchCafe24Checkout({
  required BuildContext context,
  required WidgetRef ref,
  required CheckoutArgs args,
}) async {
  if (args.items.isEmpty) return;

  // 주문서 웹뷰 진입 전 Cafe24 회원 웹뷰 세션 유효성 검증 및 자동 복구
  final sessionReady = await ensureCheckoutWebSession(context, ref);
  if (!sessionReady || !context.mounted) return;

  final user = ref.read(authProvider);

  // 세션 복구 과정에서 갱신된 최신 장바구니 품목(basketProductNo 포함) 반영
  CheckoutArgs effectiveArgs = args;
  if (args.fromCart) {
    final selectedIds = {for (final it in args.items) it.product.id};
    final refreshedItems = ref
        .read(cartProvider)
        .where((it) => selectedIds.contains(it.product.id))
        .toList();
    if (refreshedItems.isNotEmpty) {
      effectiveArgs = CheckoutArgs(items: refreshedItems, fromCart: true);
    }
  }

  final prefill = Cafe24OrderPrefill(
    recipientName: user?.name ?? '',
    recipientPhone: user?.phone ?? '',
    zipCode: user?.zipCode ?? '',
    address1: user?.address1 ?? '',
    address2: user?.address2 ?? '',
    deliveryMemo: '문 앞에 놓아주세요',
    paymentMethod: '신용/체크카드',
  );

  final result = await Cafe24OrderWebViewPage.open(
    context,
    args: effectiveArgs,
    prefill: prefill,
  );

  if (!context.mounted) return;

  // 사용자가 결제를 취소했거나 뒤로가기로 닫은 경우에도 웹뷰 세션 및 장바구니 상태 즉시 동기화
  if (result == null || result.isCanceled) {
    unawaited(ref.read(cartProvider.notifier).refreshFromCafe24());
    if (result?.message != null && result!.message!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message!),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  // 결제 승인 실패 또는 시스템 거부
  if (result.isFailure) {
    unawaited(ref.read(cartProvider.notifier).refreshFromCafe24());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('결제 실패: ${result.message ?? '결제 과정에서 오류가 발생했습니다.'}'),
        backgroundColor: AppTheme.point,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final cafe24OrderId = result.orderId!;

  // 주문 기록 저장 및 장바구니 정리
  final orderRecord = await ref.read(orderProvider.notifier).recordCafe24Order(
        cafe24OrderId: cafe24OrderId,
        args: effectiveArgs,
        recipientName: user?.name ?? '고객',
        recipientPhone: user?.phone ?? '',
        address: '${user?.address1 ?? ''} ${user?.address2 ?? ''}'.trim(),
        deliveryMemo: '문 앞에 놓아주세요',
        paymentMethod: 'Cafe24 결제',
      );

  if (context.mounted) {
    await showOrderCompleteDialog(context, ref, orderRecord);
  }
}
