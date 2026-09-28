import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';

class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final summary = ref.watch(cartSummaryProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          '장바구니 (${cartItems.length})',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                _showClearConfirmDialog(context, ref);
              },
              child: const Text(
                '전체 비우기',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: cartItems.isEmpty
          ? _buildEmptyState(context, ref)
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildFreeShippingBar(summary),
                        _buildSelectionHeader(ref, summary),
                        _buildItemList(context, ref, cartItems),
                        const SizedBox(height: 12),
                        _buildPaymentSummaryCard(summary),
                        const SizedBox(height: 16),
                        _buildNoticeSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                _buildStickyBottomBar(context, ref, summary),
              ],
            ),
    );
  }

  // ─── 무료 배송 혜택 진행 바 (소프트 그린 틴트로 편안하게) ───
  Widget _buildFreeShippingBar(CartSummary summary) {
    final remainingForFree = summary.freeShippingThreshold - summary.totalSalePrice;
    final isFree = remainingForFree <= 0 || summary.selectedCount == 0;
    final double progress = summary.selectedCount == 0
        ? 0
        : (summary.totalSalePrice / summary.freeShippingThreshold).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      color: AppTheme.successLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 18, color: AppTheme.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                    children: [
                      if (summary.selectedCount == 0)
                        const TextSpan(text: '상품을 선택하면 배송비를 확인하실 수 있습니다.')
                      else if (isFree)
                        const TextSpan(
                          text: '🎉 축하합니다! 무료 배송 혜택 적용 중입니다.',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success),
                        )
                      else ...[
                        TextSpan(
                          text: '${CartSummary.format(remainingForFree)}원',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success),
                        ),
                        const TextSpan(text: ' 더 담으면 '),
                        const TextSpan(
                          text: '무료 배송!',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFA7F3D0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader(WidgetRef ref, CartSummary summary) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Checkbox(
                value: summary.isAllSelected,
                activeColor: AppTheme.primary,
                onChanged: (val) {
                  ref.read(cartProvider.notifier).toggleAllSelection(val ?? false);
                },
              ),
              Text(
                '전체선택 (${summary.selectedCount}/${summary.totalCount})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: summary.selectedCount > 0
                ? () {
                    ref.read(cartProvider.notifier).removeSelected();
                  }
                : null,
            child: Text(
              '선택삭제',
              style: TextStyle(
                fontSize: 13,
                color: summary.selectedCount > 0 ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(BuildContext context, WidgetRef ref, List<CartItem> items) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final product = item.product;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: item.isSelected,
                    activeColor: AppTheme.primary,
                    onChanged: (val) {
                      ref.read(cartProvider.notifier).toggleSelection(product.id);
                    },
                  ),
                  GestureDetector(
                    onTap: () => context.push('/products/${product.id}'),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppTheme.chipBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(product.icon, size: 40, color: const Color(0xFF94A3B8)),
                          ),
                          if (product.discountRate > 0)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.point,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '-${product.discountRate}%',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/products/${product.id}'),
                                child: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                ref.read(cartProvider.notifier).removeItem(product.id);
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (product.discountRate > 0) ...[
                              Text(
                                product.formattedOriginalPrice,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              product.formattedSalePrice,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      ref.read(cartProvider.notifier).updateQuantity(
                                            product.id,
                                            item.quantity - 1,
                                          );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.remove, size: 16, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  Container(
                                    width: 32,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      ref.read(cartProvider.notifier).updateQuantity(
                                            product.id,
                                            item.quantity + 1,
                                          );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.add, size: 16, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              CartSummary.format(item.totalPrice) + '원',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentSummaryCard(CartSummary summary) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '결제 예정 금액',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow(
            '총 상품금액',
            '${CartSummary.format(summary.totalOriginalPrice)}원',
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            '상품 할인금액',
            '-${CartSummary.format(summary.totalDiscount)}원',
            valueColor: AppTheme.point,
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            '배송비',
            summary.shippingFee == 0
                ? '0원 (무료배송)'
                : '+${CartSummary.format(summary.shippingFee)}원',
            valueColor: summary.shippingFee == 0 ? AppTheme.success : null,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '총 결제예정금액',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                '${CartSummary.format(summary.finalPrice)}원',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.point,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '• 장바구니에 담긴 상품은 최대 30일간 보관됩니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          SizedBox(height: 4),
          Text(
            '• 판매 종료되거나 품절된 상품은 주문 시 자동 제외될 수 있습니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(BuildContext context, WidgetRef ref, CartSummary summary) {
    final isEnabled = summary.selectedCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isEnabled
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${summary.selectedCount}개 상품 (${CartSummary.format(summary.finalPrice)}원) 주문 단계로 이동합니다.',
                        ),
                        backgroundColor: AppTheme.point,
                      ),
                    );
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.point,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              isEnabled
                  ? '총 ${summary.selectedCount}개 · ${CartSummary.format(summary.finalPrice)}원 주문하기'
                  : '상품을 선택해주세요',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: AppTheme.chipBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 48,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '장바구니에 담긴 상품이 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '원하는 상품을 담아 편리하게 주문해 보세요.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.home);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '쇼핑하러 가기',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('장바구니 비우기'),
        content: const Text('장바구니의 모든 상품을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.pop(context);
            },
            child: const Text('확인', style: TextStyle(color: AppTheme.point)),
          ),
        ],
      ),
    );
  }
}
