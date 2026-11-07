import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';
import 'package:shopmall/views/share/delivery_tracking_sheet.dart';

/// 주문 및 배달 현황 조회 목록 페이지
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(orderProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '주문 / 배송 조회',
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
        actions: [
          TextButton.icon(
            onPressed: () {
              context.push(
                '/web?title=${Uri.encodeQueryComponent('쇼핑몰 주문/배송 조회')}&path=${Uri.encodeQueryComponent('/myshop/order/list.html')}',
              );
            },
            icon: const Icon(Icons.open_in_browser, size: 16, color: AppTheme.primary),
            label: const Text(
              '쇼핑몰 내역',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: orders.isEmpty
          ? _buildEmptyState(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  _buildStatusOverview(orders),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (ctx, index) {
                      final order = orders[index];
                      return _OrderCard(order: order);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// 상단 단계별 배송 통계 카드
  Widget _buildStatusOverview(List<OrderRecord> orders) {
    int preparingCount = 0;
    int shippingCount = 0;
    int deliveredCount = 0;

    for (final o in orders) {
      if (o.status == OrderDeliveryStatus.pending ||
          o.status == OrderDeliveryStatus.preparing ||
          o.status == OrderDeliveryStatus.shippingReady) {
        preparingCount++;
      } else if (o.status == OrderDeliveryStatus.shipping) {
        shippingCount++;
      } else if (o.status == OrderDeliveryStatus.delivered) {
        deliveredCount++;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStepItem('상품준비중', preparingCount, Icons.inventory_2_outlined),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFCBD5E1)),
          _buildStepItem('배송중', shippingCount, Icons.local_shipping_outlined, isHighlight: true),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFCBD5E1)),
          _buildStepItem('배송완료', deliveredCount, Icons.check_circle_outline),
        ],
      ),
    );
  }

  Widget _buildStepItem(String title, int count, IconData icon, {bool isHighlight = false}) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: isHighlight ? AppTheme.point : (count > 0 ? AppTheme.primary : const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
            color: isHighlight ? AppTheme.point : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppTheme.point : AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                size: 40,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '주문 및 배송 내역이 없습니다',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '수지씨앤엘의 다양한 상품을 쇼핑하고\n실시간 배송 현황을 확인해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    context.push(
                      '/web?title=${Uri.encodeQueryComponent('쇼핑몰 주문/배송 조회')}&path=${Uri.encodeQueryComponent('/myshop/order/list.html')}',
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('쇼핑몰 웹 내역 확인'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('쇼핑하러 가기', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderRecord order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasTracking = order.trackingNo != null && order.trackingNo!.isNotEmpty;
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final itemExtraCount = order.items.length - 1;

    String itemTitle = '주문 상품 정보 없음';
    if (firstItem != null) {
      itemTitle = firstItem.product.name;
      if (itemExtraCount > 0) {
        itemTitle += ' 외 $itemExtraCount건';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/orders/${order.orderId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 주문 상단 헤더 (주문일자, 주문번호, 상세 화살표)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.orderedAt.year}.${order.orderedAt.month.toString().padLeft(2, '0')}.${order.orderedAt.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '주문번호 ${order.orderId}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    _buildStatusBadge(order.status),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),

                // 상품 요약 정보
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (firstItem != null && (firstItem.product.imageUrl?.isNotEmpty ?? false))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          firstItem.product.imageUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.image_not_supported, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF94A3B8)),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '결제금액: ${CartSummary.format(order.finalPaidAmount)}원',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (hasTracking) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${order.carrierName ?? 'CJ대한통운'} · ${order.trackingNo}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 하단 버튼들: [배송조회] & [주문상세보기]
                Row(
                  children: [
                    if (hasTracking)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            DeliveryTrackingSheet.show(
                              context,
                              carrierName: order.carrierName ?? 'CJ대한통운',
                              trackingNo: order.trackingNo!,
                              customTrackingUrl: order.trackingUrl,
                            );
                          },
                          icon: const Icon(Icons.location_searching, size: 16),
                          label: const Text(
                            '실시간 배송조회',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.point,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    if (hasTracking) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/orders/${order.orderId}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          '주문 상세보기',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderDeliveryStatus status) {
    Color bg;
    Color fg;

    switch (status) {
      case OrderDeliveryStatus.pending:
      case OrderDeliveryStatus.preparing:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        break;
      case OrderDeliveryStatus.shippingReady:
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF16A34A);
        break;
      case OrderDeliveryStatus.shipping:
        bg = AppTheme.point.withValues(alpha: 0.12);
        fg = AppTheme.point;
        break;
      case OrderDeliveryStatus.delivered:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        break;
      case OrderDeliveryStatus.cancelled:
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}
