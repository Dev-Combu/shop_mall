import 'package:shopmall/models/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final bool isSelected;
  final int? basketProductNo;
  final String? optionId;

  /// 사용자가 선택한 옵션 명칭 목록 (예: ['구름_차콜', '고정테이프 추가'])
  final List<String> selectedOptions;

  /// 옵션으로 인한 추가 금액 (개당 추가 금액, 원)
  final int optionAdditionalAmount;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.isSelected = true,
    this.basketProductNo,
    this.optionId,
    this.selectedOptions = const [],
    this.optionAdditionalAmount = 0,
  });

  CartItem copyWith({
    Product? product,
    int? quantity,
    bool? isSelected,
    int? basketProductNo,
    String? optionId,
    List<String>? selectedOptions,
    int? optionAdditionalAmount,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      isSelected: isSelected ?? this.isSelected,
      basketProductNo: basketProductNo ?? this.basketProductNo,
      optionId: optionId ?? this.optionId,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      optionAdditionalAmount:
          optionAdditionalAmount ?? this.optionAdditionalAmount,
    );
  }

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'isSelected': isSelected,
        'basketProductNo': basketProductNo,
        'optionId': optionId,
        'selectedOptions': selectedOptions,
        'optionAdditionalAmount': optionAdditionalAmount,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(
          (json['product'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        ),
        quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
        isSelected: json['isSelected'] as bool? ?? true,
        basketProductNo:
            int.tryParse(json['basketProductNo']?.toString() ?? ''),
        optionId: json['optionId']?.toString(),
        selectedOptions: (json['selectedOptions'] is List)
            ? (json['selectedOptions'] as List).map((e) => e.toString()).toList()
            : const [],
        optionAdditionalAmount:
            int.tryParse(json['optionAdditionalAmount']?.toString() ?? '0') ??
                0,
      );

  int get unitSalePrice => product.salePrice + optionAdditionalAmount;
  int get unitOriginalPrice => product.originalPrice + optionAdditionalAmount;

  int get totalPrice => unitSalePrice * quantity;
  int get totalOriginalPrice => unitOriginalPrice * quantity;
  int get totalDiscount => (unitOriginalPrice - unitSalePrice) * quantity;

  String get formattedOptionsText {
    if (selectedOptions.isEmpty) return '';
    return selectedOptions.map((opt) {
      var s = opt.trim();
      while (s.startsWith('[') && s.endsWith(']') && s.length >= 2) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.startsWith('옵션:') || s.startsWith('옵션 :')) {
        s = s.substring(s.indexOf(':') + 1).trim();
      }
      return s;
    }).join(' / ');
  }
}
