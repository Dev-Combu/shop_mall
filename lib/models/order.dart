import 'package:shopmall/models/cart_item.dart';

/// 주문서(CheckoutPage)로 전달할 주문 요청 데이터
class CheckoutArgs {
  /// 주문할 상품 및 수량 목록
  final List<CartItem> items;

  /// 장바구니에서 넘어온 주문인지 여부
  /// - `true`: 주문 완료 시 장바구니에서 해당 선택 상품들을 자동 제거
  /// - `false`: 상품 상세에서 '바로 구매'로 진입한 단건 주문 (장바구니 유지)
  final bool fromCart;

  const CheckoutArgs({
    required this.items,
    required this.fromCart,
  });

  int get totalOriginalPrice =>
      items.fold(0, (sum, item) => sum + item.totalOriginalPrice);

  int get totalSalePrice =>
      items.fold(0, (sum, item) => sum + item.totalPrice);

  int get totalDiscount => totalOriginalPrice - totalSalePrice;

  int get shippingFee =>
      (totalSalePrice >= 30000 || items.isEmpty) ? 0 : 3000;

  int get finalPrice => totalSalePrice + shippingFee;
}

/// 주문/배송 처리 상태
enum OrderDeliveryStatus {
  /// 결제/주문 접수 완료
  pending('결제완료', '주문이 정상 접수되었습니다.'),

  /// 상품 준비 중 (포장 및 출고 검수)
  preparing('상품준비중', '상품 포장 및 출고를 준비 중입니다.'),

  /// 배송 준비 중 (송장 출력/집하 대기)
  shippingReady('배송준비중', '송장이 출력되어 택배사 인계를 대기 중입니다.'),

  /// 배송 중 (택배사 인계 후 이동 중)
  shipping('배송중', '택배사로 인계되어 배송 중입니다.'),

  /// 배송 완료
  delivered('배송완료', '상품이 고객님께 전달되었습니다.'),

  /// 취소/반품
  cancelled('취소/환불', '주문이 취소되었습니다.');

  final String label;
  final String description;

  const OrderDeliveryStatus(this.label, this.description);

  static OrderDeliveryStatus fromString(String? val) {
    if (val == null) return OrderDeliveryStatus.pending;
    return OrderDeliveryStatus.values.firstWhere(
      (e) => e.name == val || e.label == val,
      orElse: () => OrderDeliveryStatus.pending,
    );
  }

  /// Cafe24 주문상태 코드(order_status) -> 앱 배송 상태 변환
  /// - N00: 입금전 / N10: 상품준비중 / N20: 배송준비중 / N21: 배송대기 / N22: 배송보류
  /// - N30: 배송중 / N40: 배송완료 / C**: 취소 / R**: 반품 / E**: 교환
  static OrderDeliveryStatus fromCafe24Code(String? code) {
    final c = (code ?? '').toUpperCase().trim();
    if (c.isEmpty) return OrderDeliveryStatus.pending;
    if (c.startsWith('C') || c.startsWith('R')) {
      return OrderDeliveryStatus.cancelled;
    }
    switch (c) {
      case 'N00':
        return OrderDeliveryStatus.pending;
      case 'N10':
        return OrderDeliveryStatus.preparing;
      case 'N20':
      case 'N21':
      case 'N22':
        return OrderDeliveryStatus.shippingReady;
      case 'N30':
        return OrderDeliveryStatus.shipping;
      case 'N40':
        return OrderDeliveryStatus.delivered;
      default:
        return OrderDeliveryStatus.preparing;
    }
  }
}

/// 주문 완료 내역 모델
class OrderRecord {
  final String orderId;
  final DateTime orderedAt;
  final List<CartItem> items;
  final String recipientName;
  final String recipientPhone;
  final String address;
  final String deliveryMemo;
  final String paymentMethod;
  final int usedPoints;
  final int shippingFee;
  final int finalPaidAmount;

  /// 주문 및 배달 상태
  final OrderDeliveryStatus status;

  /// 택배사명 (예: CJ대한통운, 우체국택배 등)
  final String? carrierName;

  /// 택배사 코드
  final String? carrierCode;

  /// 운송장 번호
  final String? trackingNo;

  /// 택배사 실시간 배송추적 URL
  final String? trackingUrl;

  const OrderRecord({
    required this.orderId,
    required this.orderedAt,
    required this.items,
    required this.recipientName,
    required this.recipientPhone,
    required this.address,
    required this.deliveryMemo,
    required this.paymentMethod,
    required this.usedPoints,
    required this.shippingFee,
    required this.finalPaidAmount,
    this.status = OrderDeliveryStatus.preparing,
    this.carrierName,
    this.carrierCode,
    this.trackingNo,
    this.trackingUrl,
  });

  /// 상태 업데이트를 위한 copyWith
  OrderRecord copyWith({
    String? orderId,
    DateTime? orderedAt,
    List<CartItem>? items,
    String? recipientName,
    String? recipientPhone,
    String? address,
    String? deliveryMemo,
    String? paymentMethod,
    int? usedPoints,
    int? shippingFee,
    int? finalPaidAmount,
    OrderDeliveryStatus? status,
    String? carrierName,
    String? carrierCode,
    String? trackingNo,
    String? trackingUrl,
  }) {
    return OrderRecord(
      orderId: orderId ?? this.orderId,
      orderedAt: orderedAt ?? this.orderedAt,
      items: items ?? this.items,
      recipientName: recipientName ?? this.recipientName,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      address: address ?? this.address,
      deliveryMemo: deliveryMemo ?? this.deliveryMemo,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      usedPoints: usedPoints ?? this.usedPoints,
      shippingFee: shippingFee ?? this.shippingFee,
      finalPaidAmount: finalPaidAmount ?? this.finalPaidAmount,
      status: status ?? this.status,
      carrierName: carrierName ?? this.carrierName,
      carrierCode: carrierCode ?? this.carrierCode,
      trackingNo: trackingNo ?? this.trackingNo,
      trackingUrl: trackingUrl ?? this.trackingUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderedAt': orderedAt.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        'address': address,
        'deliveryMemo': deliveryMemo,
        'paymentMethod': paymentMethod,
        'usedPoints': usedPoints,
        'shippingFee': shippingFee,
        'finalPaidAmount': finalPaidAmount,
        'status': status.name,
        'carrierName': carrierName,
        'carrierCode': carrierCode,
        'trackingNo': trackingNo,
        'trackingUrl': trackingUrl,
      };

  factory OrderRecord.fromJson(Map<String, dynamic> json) => OrderRecord(
        orderId: json['orderId']?.toString() ?? '',
        orderedAt: DateTime.tryParse(json['orderedAt']?.toString() ?? '') ??
            DateTime.now(),
        items: (json['items'] is List)
            ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map((e) => CartItem.fromJson(e))
                .toList()
            : const [],
        recipientName: json['recipientName']?.toString() ?? '',
        recipientPhone: json['recipientPhone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        deliveryMemo: json['deliveryMemo']?.toString() ?? '',
        paymentMethod: json['paymentMethod']?.toString() ?? '신용/체크카드',
        usedPoints: int.tryParse(json['usedPoints']?.toString() ?? '0') ?? 0,
        shippingFee: int.tryParse(json['shippingFee']?.toString() ?? '0') ?? 0,
        finalPaidAmount:
            int.tryParse(json['finalPaidAmount']?.toString() ?? '0') ?? 0,
        status: OrderDeliveryStatus.fromString(json['status']?.toString()),
        carrierName: json['carrierName']?.toString(),
        carrierCode: json['carrierCode']?.toString(),
        trackingNo: json['trackingNo']?.toString(),
        trackingUrl: json['trackingUrl']?.toString(),
      );
}

