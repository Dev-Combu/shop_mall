import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';

/// 주문 내역 관리 및 Cafe24 주문/배송 상태 동기화 ViewModel
class OrderViewModel extends Notifier<List<OrderRecord>> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Cafe24ApiService _api;
  String? _memberId;

  /// 마지막 Cafe24 동기화 실패 사유 (권한 부족 등)
  String? lastSyncError;

  String get _storageKey =>
      (_memberId != null && _memberId!.isNotEmpty)
          ? 'cafe24_orders_${_memberId!}'
          : 'cafe24_orders_guest';

  bool get _canSyncWithCafe24 =>
      _memberId != null && _memberId!.isNotEmpty && _memberId != 'suzicnl1';

  @override
  List<OrderRecord> build() {
    _api = ref.watch(cafe24ApiServiceProvider);
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
              // 이전 버전의 앱 내부 시뮬레이션 주문(Cafe24에 존재하지 않는 주문)은 제외 (단, 테스트 주문은 유지)
              .where((o) =>
                  _isCafe24OrderId(o.orderId) ||
                  o.orderId.startsWith('TEST-') ||
                  o.orderId.startsWith('DEMO-') ||
                  !_canSyncWithCafe24)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[OrderViewModel] 주문 내역 복원 실패: $e');
    }
    if (_canSyncWithCafe24) {
      await syncWithCafe24();
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

  /// Cafe24 주문번호 형식(YYYYMMDD-NNNNNNN) 여부
  static bool _isCafe24OrderId(String id) =>
      RegExp(r'^\d{8}-\d{7}$').hasMatch(id);

  /// 특정 주문건 단건 조회
  OrderRecord? getOrderById(String orderId) {
    for (final o in state) {
      if (o.orderId == orderId) return o;
    }
    return null;
  }

  /// Cafe24 Admin API에서 회원 주문 목록 + 배송상태(송장번호/택배사)를 가져와 병합
  /// - Cafe24 웹사이트에서 직접 주문한 내역도 함께 표시됩니다.
  Future<void> syncWithCafe24() async {
    if (!_canSyncWithCafe24) return;

    final remote = await _api.fetchMemberOrders(_memberId!);
    lastSyncError = _api.lastOrderSyncError;
    if (remote.isEmpty) return;

    final localById = {for (final o in state) o.orderId: o};
    final merged = <OrderRecord>[];

    for (final r in remote) {
      final local = localById.remove(r.orderId);
      // 서버 품목에는 이미지가 없으므로 앱에서 주문한 품목 정보(이미지 포함)가 있으면 유지
      merged.add(
        local != null && local.items.isNotEmpty
            ? r.copyWith(items: local.items)
            : r,
      );
    }
    // 서버 조회 기간 밖의 로컬 주문은 그대로 유지
    merged.addAll(localById.values);
    merged.sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

    state = merged;
    await _persistOrders();
  }

  /// 단일 주문의 최신 배송 상태를 Cafe24에서 갱신
  Future<void> refreshOrderStatus(String orderId) async {
    if (!_canSyncWithCafe24 || !_isCafe24OrderId(orderId)) return;
    final remote = await _api.fetchOrderDetail(orderId);
    if (remote == null) return;

    state = state.map((o) {
      if (o.orderId != orderId) return o;
      return remote.copyWith(items: o.items.isNotEmpty ? o.items : remote.items);
    }).toList();
    await _persistOrders();
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
      finalPaidAmount: args.finalPrice,
      status: OrderDeliveryStatus.pending,
    );

    state = [record, ...state.where((o) => o.orderId != cafe24OrderId)];
    await _persistOrders();

    // Cafe24 주문서에서 주문된 장바구니 상품은 Cafe24 장바구니에서 이미 제거되므로 앱 장바구니도 정리
    if (args.fromCart) {
      final cartNotifier = ref.read(cartProvider.notifier);
      for (final orderedItem in args.items) {
        await cartNotifier.removeItem(orderedItem.product.id);
      }
    }

    await ref.read(authProvider.notifier).recordCompletedOrder();

    // 실제 결제금액/결제수단/주문상태를 서버 기준으로 즉시 보정
    await refreshOrderStatus(cafe24OrderId);
    return getOrderById(cafe24OrderId) ?? record;
  }

  /// 테스트(모의 승인) 결제 및 데모 계정 로컬 주문 처리
  /// - 실제 결제 승인 없이 테스트용 주문번호로 주문 데이터를 생성하여 배송/주문 흐름을 검증할 수 있습니다.
  Future<OrderRecord> placeDemoOrder({
    required CheckoutArgs args,
    required String recipientName,
    required String recipientPhone,
    required String address,
    required String deliveryMemo,
    String paymentMethod = '테스트 결제 (가상 승인)',
  }) async {
    final now = DateTime.now();
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randSeq =
        (now.millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    final orderId = 'TEST-$ymd-$randSeq';

    final record = OrderRecord(
      orderId: orderId,
      orderedAt: now,
      items: args.items,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      address: address,
      deliveryMemo: deliveryMemo,
      paymentMethod: paymentMethod,
      usedPoints: 0,
      shippingFee: args.shippingFee,
      finalPaidAmount: args.finalPrice,
      status: OrderDeliveryStatus.pending,
    );

    state = [record, ...state];
    await _persistOrders();

    if (args.fromCart) {
      final cartNotifier = ref.read(cartProvider.notifier);
      for (final orderedItem in args.items) {
        await cartNotifier.removeItem(orderedItem.product.id);
      }
    }
    await ref.read(authProvider.notifier).recordCompletedOrder();
    return record;
  }

  /// [mall.write_order] 주문 취소 처리 (Cafe24 서버 취소 요청 + 로컬 상태 반영)
  Future<bool> cancelOrder(String orderId, {String reason = '고객 직접 취소'}) async {
    if (_isCafe24OrderId(orderId)) {
      try {
        await _api.cancelOrder(orderId, reason: reason);
      } catch (e) {
        debugPrint('[OrderViewModel] Cafe24 주문 취소 API 호출 참고: $e');
      }
    }

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
