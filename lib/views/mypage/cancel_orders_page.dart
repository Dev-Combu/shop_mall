import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';

/// 취소/반품/교환 내역 화면 (취소·환불 상태 주문만 표시)
class CancelOrdersPage extends ConsumerWidget {
  const CancelOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref
        .watch(orderProvider)
        .where((o) => o.status == OrderDeliveryStatus.cancelled)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('취소/반품/교환 내역',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.primary, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              context.push(
                '/web?title=${Uri.encodeQueryComponent('취소/반품/교환 조회')}&path=${Uri.encodeQueryComponent('/myshop/order/list.html')}',
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
      body: RefreshIndicator(
        onRefresh: () => ref.read(orderProvider.notifier).syncWithCafe24(),
        child: orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Icon(Icons.inventory_2_outlined,
                      size: 56, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 12),
                  Center(
                    child: Text('취소/반품/교환 내역이 없습니다.',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  final first = o.items.isNotEmpty ? o.items.first : null;
                  final summary = first == null
                      ? '주문 상품 없음'
                      : (o.items.length > 1
                          ? '${first.product.name} 외 ${o.items.length - 1}건'
                          : first.product.name);
                  final d = o.orderedAt;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/orders/${o.orderId}'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF94A3B8)),
                              ),
                              const Spacer(),
                              Text(o.status.label,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.point)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(summary,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('주문번호 ${o.orderId}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
