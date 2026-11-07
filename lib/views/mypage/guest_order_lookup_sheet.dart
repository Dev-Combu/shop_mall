import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';
import 'package:shopmall/views/mypage/mall_web_page.dart';

/// 비회원 주문 조회 바텀시트
class GuestOrderLookupSheet extends ConsumerStatefulWidget {
  const GuestOrderLookupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GuestOrderLookupSheet(),
    );
  }

  @override
  ConsumerState<GuestOrderLookupSheet> createState() =>
      _GuestOrderLookupSheetState();
}

class _GuestOrderLookupSheetState extends ConsumerState<GuestOrderLookupSheet> {
  final TextEditingController _orderIdController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _orderIdController.dispose();
    super.dispose();
  }

  void _lookupOrder(List<OrderRecord> orders) {
    final input = _orderIdController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = '주문번호를 입력해주세요.';
      });
      return;
    }

    final matched = orders.where((o) {
      final id = o.orderId.trim();
      return id.toLowerCase() == input.toLowerCase() ||
          id.replaceAll('-', '').toLowerCase() ==
              input.replaceAll('-', '').toLowerCase();
    }).firstOrNull;

    if (matched != null) {
      Navigator.of(context).pop();
      context.push('/orders/${matched.orderId}');
    } else {
      setState(() {
        _errorMessage = null;
      });
      _showNotFoundDialog(input);
    }
  }

  void _showNotFoundDialog(String inputOrderId) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.search_off_rounded, color: AppTheme.point, size: 22),
            SizedBox(width: 8),
            Text(
              '주문 내역 없음',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        content: Text(
          '앱 내 저장된 비회원 주문 목록에서 [$inputOrderId] 건을 찾을 수 없습니다.\n\n쇼핑몰 웹사이트에서 주문하셨다면 공식 비회원 주문조회 페이지로 이동하시겠습니까?',
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('취소', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop();
              context.push(
                '/web?title=${Uri.encodeQueryComponent('비회원 주문 조회')}&path=${Uri.encodeQueryComponent(MallPages.guestOrder)}',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('웹에서 조회'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final guestOrders = ref.watch(orderProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 핸들 바
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '비회원 주문 조회',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '주문 시 발급된 주문번호를 입력해 주세요.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 주문번호 입력창
            TextField(
              controller: _orderIdController,
              decoration: InputDecoration(
                hintText: '예: 20261104-0000001',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.receipt_long_outlined, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                errorText: _errorMessage,
              ),
              onSubmitted: (_) => _lookupOrder(guestOrders),
            ),
            const SizedBox(height: 12),

            // 조회 버튼
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => _lookupOrder(guestOrders),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  '주문 조회하기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 이 기기에서 주문한 최근 비회원 주문 목록
            if (guestOrders.isNotEmpty) ...[
              const Text(
                '이 기기에서 주문한 최근 내역',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...guestOrders.take(3).map((order) {
                final firstItem = order.items.isNotEmpty ? order.items.first : null;
                final itemName = firstItem == null
                    ? '상품 정보 없음'
                    : (order.items.length > 1
                        ? '${firstItem.product.name} 외 ${order.items.length - 1}건'
                        : firstItem.product.name);

                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/orders/${order.orderId}');
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 20,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${order.orderId} · ${order.status.label}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // 쇼핑몰 웹 비회원 조회 바로가기
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(
                    '/web?title=${Uri.encodeQueryComponent('비회원 주문 조회')}&path=${Uri.encodeQueryComponent(MallPages.guestOrder)}',
                  );
                },
                icon: const Icon(Icons.open_in_browser, size: 16, color: Color(0xFF64748B)),
                label: const Text(
                  '쇼핑몰 웹사이트에서 비회원 주문 조회',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

