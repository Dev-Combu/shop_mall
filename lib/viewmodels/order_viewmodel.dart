import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';

/// 주문 내역 관리 ViewModel (안전한 로컬 보안 저장소 기반)
class OrderViewModel extends Notifier<List<OrderRecord>> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _memberId;

  String? lastSyncError;

  String get _storageKey =>
      (_memberId != null && _memberId!.isNotEmpty)
          ? 'cafe24_orders_${_memberId!}'
          : 'cafe24_orders_guest';

  @override
  List<OrderRecord> build() {
    final user = ref.watch(authProvider);
    _memberId = user?.id;
    _loadOrders();
    return [];
  }

  Future<void> _loadOrders() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          state = decoded
              .whereType<Map<String, dynamic>>()
              .map((json) => OrderRecord.fromJson(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[OrderViewModel] 주문 내역 복원 실패: $e');
    }
  }

  Future<void> _persistOrders() async {
    try {
      final encoded = jsonEncode(state.map((e) => e.toJson()).toList());
      await _storage.write(key: _storageKey, value: encoded);
    } catch (e) {
      debugPrint('[OrderViewModel] 주문 내역 저장 실패: $e');
    }
  }

  /// 특정 주문건 단건 조회
  OrderRecord? getOrderById(String orderId) {
    for (final o in state) {
      if (o.orderId == orderId) return o;
    }
    return null;
  }

  /// 주문 목록 새로고침 (로컬 저장소 최신화)
  Future<void> syncWithCafe24() async {
    await _loadOrders();
  }

  /// 단일 주문의 배송 상태 확인 (로컬 갱신)
  Future<void> refreshOrderStatus(String orderId) async {
    await _loadOrders();
  }

  /// Cafe24 결제 완료(/order/order_result.html) 후 실제 Cafe24 주문번호로 주문 기록
  Future<OrderRecord> recordCafe24Order({
    required String cafe24OrderId,
    required CheckoutArgs args,
    required String recipientName,
    required String recipientPhone,
    required String address,
    required String deliveryMemo,
    String paymentMethod = 'Cafe24 결제',
    int usedPoints = 0,
  }) async {
    final record = OrderRecord(
      orderId: cafe24OrderId,
      orderedAt: DateTime.now(),
      items: args.items,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      address: address,
      deliveryMemo: deliveryMemo,
      paymentMethod: paymentMethod,
      usedPoints: usedPoints,
      shippingFee: args.shippingFee,
      finalPaidAmount: (args.finalPrice - usedPoints).clamp(0, 999999999),
      status: OrderDeliveryStatus.preparing,
    );

    state = [record, ...state.where((o) => o.orderId != cafe24OrderId)];
    await _persistOrders();

    // 장바구니에서 주문한 건인 경우 로컬 및 서버 장바구니 품목 정리
    if (args.fromCart) {
      final cartNotifier = ref.read(cartProvider.notifier);
      for (final item in args.items) {
        await cartNotifier.removeItem(item.product.id);
      }
    }

    // 마이페이지 통계 실시간 반영
    await ref.read(authProvider.notifier).recordCompletedOrder();

    return record;
  }

  /// 테스트/데모 결제 모드 (실제 Cafe24 PG를 호출하지 않고 앱 내 기록만 생성)
  Future<OrderRecord> placeDemoOrder({
    required CheckoutArgs args,
    required String recipientName,
    required String recipientPhone,
    required String address,
    required String deliveryMemo,
    required String paymentMethod,
    int usedPoints = 0,
  }) async {
    final demoOrderId =
        'TEST-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    final record = OrderRecord(
      orderId: demoOrderId,
      orderedAt: DateTime.now(),
      items: args.items,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      address: address,
      deliveryMemo: deliveryMemo,
      paymentMethod: paymentMethod,
      usedPoints: usedPoints,
      shippingFee: args.shippingFee,
      finalPaidAmount: (args.finalPrice - usedPoints).clamp(0, 999999999),
      status: OrderDeliveryStatus.preparing,
    );

    state = [record, ...state];
    await _persistOrders();

    if (args.fromCart) {
      final cartNotifier = ref.read(cartProvider.notifier);
      for (final item in args.items) {
        await cartNotifier.removeItem(item.product.id);
      }
    }

    await ref.read(authProvider.notifier).recordCompletedOrder();

    return record;
  }

  /// 특정 주문 취소 처리
  Future<bool> cancelOrder(String orderId) async {
    final target = getOrderById(orderId);
    if (target == null) return false;

    state = state.map((o) {
      if (o.orderId != orderId) return o;
      return o.copyWith(status: OrderDeliveryStatus.cancelled);
    }).toList();
    await _persistOrders();
    return true;
  }
}

final orderProvider = NotifierProvider<OrderViewModel, List<OrderRecord>>(
  OrderViewModel.new,
);
