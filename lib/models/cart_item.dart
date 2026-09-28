import 'package:shopmall/models/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final bool isSelected;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.isSelected = true,
  });

  CartItem copyWith({
    Product? product,
    int? quantity,
    bool? isSelected,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  int get totalPrice => product.salePrice * quantity;
  int get totalOriginalPrice => product.originalPrice * quantity;
  int get totalDiscount => (product.originalPrice - product.salePrice) * quantity;
}
