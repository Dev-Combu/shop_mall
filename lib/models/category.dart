import 'package:flutter/material.dart';

/// 쇼핑몰 카테고리 데이터 모델
class ShopCategory {
  final int id;
  final String name;
  final int depth;
  final int parentId;
  final IconData icon;

  const ShopCategory({
    required this.id,
    required this.name,
    this.depth = 1,
    this.parentId = 0,
    this.icon = Icons.category_outlined,
  });

  factory ShopCategory.fromCafe24Json(Map<String, dynamic> json) {
    final name = json['category_name']?.toString() ?? '미분류';
    return ShopCategory(
      id: int.tryParse(json['category_no']?.toString() ?? '0') ?? 0,
      name: name,
      depth: int.tryParse(json['category_depth']?.toString() ?? '1') ?? 1,
      parentId: int.tryParse(json['parent_category_no']?.toString() ?? '0') ?? 0,
      icon: _matchCategoryIcon(name),
    );
  }

  static IconData _matchCategoryIcon(String name) {
    if (name.contains('매트') || name.contains('롤매트')) {
      return Icons.view_column_rounded;
    } else if (name.contains('전기') || name.contains('온수') || name.contains('난방')) {
      return Icons.whatshot_rounded;
    } else if (name.contains('현관') || name.contains('발매트')) {
      return Icons.door_front_door_rounded;
    } else if (name.contains('잔디')) {
      return Icons.grass_rounded;
    } else if (name.contains('청소')) {
      return Icons.cleaning_services_rounded;
    } else if (name.contains('주방') || name.contains('생활')) {
      return Icons.kitchen_rounded;
    } else if (name.contains('침구') || name.contains('이불')) {
      return Icons.king_bed_rounded;
    } else if (name.contains('특가') || name.contains('할인') || name.contains('이벤트')) {
      return Icons.local_offer_rounded;
    }
    return Icons.grid_view_rounded;
  }
}

