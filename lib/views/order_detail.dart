import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';
import 'package:shopmall/views/share/delivery_tracking_sheet.dart';

/// 주문 상세 정보 및 배송 타임라인 화면
class OrderDetailPage extends ConsumerWidget {
  final String orderId;

  const OrderDetailPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider.notifier).getOrderById(orderId);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('주문 상세')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('주문 정보를 찾을 수 없습니다.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    final hasTracking = order.trackingNo != null && order.trackingNo!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '주문 상세 내역',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.primary, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 배송 현황 타임라인 카드
            _buildDeliveryProgressCard(context, order),
            const SizedBox(height: 16),

            // 2. 주문 상품 목록 카드
            _buildOrderedItemsCard(order),
            const SizedBox(height: 16),

            // 3. 배송지 정보 카드
            _buildShippingInfoCard(order),
            const SizedBox(height: 16),

            // 4. 결제 금액 정보 카드
            _buildPaymentInfoCard(order),
            const SizedBox(height: 24),

            // 실시간 배송조회 버튼 (송장 존재 시)
            if (hasTracking)
              ElevatedButton.icon(
                onPressed: () {
                  DeliveryTrackingSheet.show(
                    context,
                    carrierName: order.carrierName ?? 'CJ대한통운',
                    trackingNo: order.trackingNo!,
                    customTrackingUrl: order.trackingUrl,
                  );
                },
                icon: const Icon(Icons.local_shipping, size: 18),
                label: const Text(
                  '택배사 실시간 배송조회 바로가기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.point,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),

            // 주문 취소 버튼 (결제완료/상품준비중 상태일 때 제공)
            if (order.status == OrderDeliveryStatus.pending ||
                order.status == OrderDeliveryStatus.preparing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmCancelOrder(context, ref, order),
                icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFEF4444)),
                label: const Text(
                  '주문 취소하기',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  backgroundColor: const Color(0xFFFEF2F2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelOrder(
    BuildContext context,
    WidgetRef ref,
    OrderRecord order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('주문을 취소하시겠습니까?', style: TextStyle(fontSize: 16)),
        content: const Text(
          '주문을 취소하시면 즉시 결제 취소 또는 환불 절차가 진행됩니다.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('취소 확인', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(orderProvider.notifier).cancelOrder(order.orderId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('주문이 정상적으로 취소되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 실시간 배송 현황 및 4단계 진행 타임라인
  Widget _buildDeliveryProgressCard(BuildContext context, OrderRecord order) {
    int activeStep = 0;
    switch (order.status) {
      case OrderDeliveryStatus.pending:
        activeStep = 0;
        break;
      case OrderDeliveryStatus.preparing:
        activeStep = 1;
        break;
      case OrderDeliveryStatus.shippingReady:
      case OrderDeliveryStatus.shipping:
        activeStep = 2;
        break;
      case OrderDeliveryStatus.delivered:
        activeStep = 3;
        break;
      case OrderDeliveryStatus.cancelled:
        activeStep = -1;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '배송 현황 (${order.status.label})',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              if (order.trackingNo != null)
                InkWell(
                  onTap: () {
                    DeliveryTrackingSheet.show(
                      context,
                      carrierName: order.carrierName ?? 'CJ대한통운',
                      trackingNo: order.trackingNo!,
                      customTrackingUrl: order.trackingUrl,
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.point.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '실시간 조회 >',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.point,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            order.status.description,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),

          // 4단계 스텝 인디케이터
          Row(
            children: [
              _buildStepNode('결제완료', 0, activeStep),
              _buildStepLine(0, activeStep),
              _buildStepNode('상품준비', 1, activeStep),
              _buildStepLine(1, activeStep),
              _buildStepNode('배송중', 2, activeStep),
              _buildStepLine(2, activeStep),
              _buildStepNode('배송완료', 3, activeStep),
            ],
          ),

          if (order.trackingNo != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${order.carrierName ?? 'CJ대한통운'} [${order.trackingNo}]',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepNode(String label, int stepIndex, int currentActive) {
    final isPassed = currentActive >= stepIndex;
    final isCurrent = currentActive == stepIndex;

    Color nodeColor = const Color(0xFFCBD5E1);
    if (isCurrent) {
      nodeColor = AppTheme.point;
    } else if (isPassed) {
      nodeColor = AppTheme.primary;
    }

    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: nodeColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              isPassed ? Icons.check : Icons.circle,
              size: 13,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? AppTheme.point : (isPassed ? AppTheme.primary : const Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int startStep, int currentActive) {
    final isPassed = currentActive > startStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: isPassed ? AppTheme.primary : const Color(0xFFE2E8F0),
      ),
    );
  }

  /// 주문 상품 목록 카드
  Widget _buildOrderedItemsCard(OrderRecord order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '주문 상품 (${order.items.length}건)',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            separatorBuilder: (_, __) => const Divider(height: 18, color: Color(0xFFF1F5F9)),
            itemBuilder: (ctx, idx) {
              final item = order.items[idx];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: (item.product.imageUrl != null && item.product.imageUrl!.isNotEmpty)
                        ? Image.network(
                            item.product.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.image_not_supported, color: Color(0xFF94A3B8), size: 20),
                            ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.image_not_supported, color: Color(0xFF94A3B8), size: 20),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${CartSummary.format(item.product.salePrice)}원 · ${item.quantity}개',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${CartSummary.format(item.totalPrice)}원',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 배송지 정보 카드
  Widget _buildShippingInfoCard(OrderRecord order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '배송지 정보',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('받는 분', '${order.recipientName} (${order.recipientPhone})'),
          const SizedBox(height: 8),
          _buildInfoRow('배송 주소', order.address),
          const SizedBox(height: 8),
          _buildInfoRow('배송 요청사항', order.deliveryMemo.isNotEmpty ? order.deliveryMemo : '요청사항 없음'),
        ],
      ),
    );
  }

  /// 결제 금액 정보 카드
  Widget _buildPaymentInfoCard(OrderRecord order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '결제 정보',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('결제 수단', order.paymentMethod),
          const SizedBox(height: 8),
          _buildInfoRow('배송비', '${CartSummary.format(order.shippingFee)}원'),
          if (order.usedPoints > 0) ...[
            const SizedBox(height: 8),
            _buildInfoRow('포인트 사용', '-${CartSummary.format(order.usedPoints)}P'),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '최종 결제 금액',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              Text(
                '${CartSummary.format(order.finalPaidAmount)}원',
                style: const TextStyle(
                  fontSize: 16.5,
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
