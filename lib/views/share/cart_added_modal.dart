import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';

/// 상품을 장바구니에 담고, 장바구니로 이동할지 묻는 모달 다이얼로그를 표시하는 공통 헬퍼
Future<void> addProductToCartWithModal(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  int quantity = 1,
  List<String> selectedOptions = const [],
  int optionAdditionalAmount = 0,
}) async {
  // 1. 장바구니 상태에 상품 추가
  ref.read(cartProvider.notifier).addProduct(
        product,
        quantity: quantity,
        selectedOptions: selectedOptions,
        optionAdditionalAmount: optionAdditionalAmount,
      );

  if (!context.mounted) return;

  // 2. 장바구니로 이동할지 묻는 모달 표시
  final shouldGoToCart = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 상단 체크 아이콘
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppTheme.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_shopping_cart_rounded,
                  color: AppTheme.success,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '장바구니에 상품을 담았습니다',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '장바구니로 이동하시겠습니까?',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),

              // 담은 상품 요약 카드
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 48,
                        height: 48,
                        color: Colors.white,
                        child: hasImage
                            ? Image.network(
                                product.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  product.icon,
                                  size: 24,
                                  color: const Color(0xFF94A3B8),
                                ),
                              )
                            : Icon(
                                product.icon,
                                size: 24,
                                color: const Color(0xFF94A3B8),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '수량 ${quantity}개 · ${product.formattedTotalPrice(quantity)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 하단 액션 버튼 (쇼핑 계속하기 / 장바구니 이동)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '쇼핑 계속하기',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '장바구니 이동',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  // 3. '장바구니 이동'을 선택한 경우 장바구니 탭으로 전환 및 이동
  if (shouldGoToCart == true && context.mounted) {
    ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.cart);
    context.go('/cart');
  }
}

