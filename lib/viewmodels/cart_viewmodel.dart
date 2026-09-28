import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';

class CartViewModel extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    // 샘플 장바구니 데이터 (p001, p005)
    final p1 = ProductDataService.findById('p001');
    final p2 = ProductDataService.findById('p005');
    final p3 = ProductDataService.findById('p002');

    return [
      if (p1 != null) CartItem(product: p1, quantity: 1, isSelected: true),
      if (p2 != null) CartItem(product: p2, quantity: 2, isSelected: true),
      if (p3 != null) CartItem(product: p3, quantity: 1, isSelected: false),
    ];
  }

  /// 상품 추가
  void addProduct(Product product, {int quantity = 1}) {
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final existing = state[index];
      final updated = existing.copyWith(
        quantity: existing.quantity + quantity,
        isSelected: true,
      );
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index) updated else state[i]
      ];
    } else {
      state = [
        ...state,
        CartItem(product: product, quantity: quantity, isSelected: true)
      ];
    }
  }

  /// 수량 변경
  void updateQuantity(String productId, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(productId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.copyWith(quantity: newQuantity)
        else
          item
    ];
  }

  /// 선택 상태 토글
  void toggleSelection(String productId) {
    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.copyWith(isSelected: !item.isSelected)
        else
          item
    ];
  }

  /// 전체 선택 / 해제
  void toggleAllSelection(bool selectAll) {
    state = [
      for (final item in state) item.copyWith(isSelected: selectAll)
    ];
  }

  /// 아이템 삭제
  void removeItem(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  /// 선택된 아이템들 삭제
  void removeSelected() {
    state = state.where((item) => !item.isSelected).toList();
  }

  /// 전체 비우기
  void clear() {
    state = [];
  }
}

final cartProvider = NotifierProvider<CartViewModel, List<CartItem>>(
  CartViewModel.new,
);

/// 계산 유틸리티를 위한 계산 결과 Provider
final cartSummaryProvider = Provider((ref) {
  final items = ref.watch(cartProvider);
  final selectedItems = items.where((item) => item.isSelected).toList();

  final int totalOriginalPrice = selectedItems.fold(
      0, (sum, item) => sum + item.totalOriginalPrice);
  final int totalSalePrice =
      selectedItems.fold(0, (sum, item) => sum + item.totalPrice);
  final int totalDiscount = totalOriginalPrice - totalSalePrice;

  // 무료배송 기준: 30,000원 이상 시 무료배송, 이하 3,000원
  final int freeShippingThreshold = 30000;
  final int shippingFee = (totalSalePrice >= freeShippingThreshold || selectedItems.isEmpty)
      ? 0
      : 3000;
  final int finalPrice = totalSalePrice + shippingFee;

  final bool isAllSelected = items.isNotEmpty && items.every((item) => item.isSelected);

  return CartSummary(
    totalCount: items.length,
    selectedCount: selectedItems.length,
    totalOriginalPrice: totalOriginalPrice,
    totalSalePrice: totalSalePrice,
    totalDiscount: totalDiscount,
    shippingFee: shippingFee,
    freeShippingThreshold: freeShippingThreshold,
    finalPrice: finalPrice,
    isAllSelected: isAllSelected,
  );
});

class CartSummary {
  final int totalCount;
  final int selectedCount;
  final int totalOriginalPrice;
  final int totalSalePrice;
  final int totalDiscount;
  final int shippingFee;
  final int freeShippingThreshold;
  final int finalPrice;
  final bool isAllSelected;

  CartSummary({
    required this.totalCount,
    required this.selectedCount,
    required this.totalOriginalPrice,
    required this.totalSalePrice,
    required this.totalDiscount,
    required this.shippingFee,
    required this.freeShippingThreshold,
    required this.finalPrice,
    required this.isAllSelected,
  });

  /// 숫자를 세 자릿수 콤마 포맷으로 변환
  static String format(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
