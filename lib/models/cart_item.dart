import 'package:shopmall/models/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final bool isSelected;
  final int? basketProductNo;
  final String? optionId;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.isSelected = true,
    this.basketProductNo,
    this.optionId,
  });

  CartItem copyWith({
    Product? product,
    int? quantity,
    bool? isSelected,
    int? basketProductNo,
    String? optionId,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      isSelected: isSelected ?? this.isSelected,
      basketProductNo: basketProductNo ?? this.basketProductNo,
      optionId: optionId ?? this.optionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'isSelected': isSelected,
        'basketProductNo': basketProductNo,
        'optionId': optionId,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(
          (json['product'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        ),
        quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
        isSelected: json['isSelected'] as bool? ?? true,
        basketProductNo: int.tryParse(json['basketProductNo']?.toString() ?? ''),
        optionId: json['optionId']?.toString(),
      );

  int get totalPrice => product.salePrice * quantity;
  int get totalOriginalPrice => product.originalPrice * quantity;
  int get totalDiscount => (product.originalPrice - product.salePrice) * quantity;
}
