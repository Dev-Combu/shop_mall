import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 상품 데이터 모델
class Product {
  final String id;
  final String name;
  final int originalPrice; // 원래 가격 (원)
  final int discountRate;  // 할인율 (0~100, %)
  final String tag;        // 예: 'NEW', 'BEST', 'SALE'
  final Color tagColor;
  final String category;   // 예: '롤매트', '현관발매트'
  final IconData icon;     // 이미지 플레이스홀더용 아이콘
  final String description;
  final double rating;     // 1.0 ~ 5.0
  final int reviewCount;

  const Product({
    required this.id,
    required this.name,
    required this.originalPrice,
    this.discountRate = 0,
    required this.tag,
    required this.tagColor,
    required this.category,
    required this.icon,
    this.description = '',
    this.rating = 4.5,
    this.reviewCount = 0,
  });

  /// 할인가 계산
  int get salePrice =>
      discountRate > 0
          ? (originalPrice * (1 - discountRate / 100)).round()
          : originalPrice;

  /// 가격 문자열 (예: "35,000원")
  String get formattedOriginalPrice =>
      '${_formatNumber(originalPrice)}원';

  String get formattedSalePrice =>
      '${_formatNumber(salePrice)}원';

  String formattedTotalPrice(int quantity) =>
      '${_formatNumber(salePrice * quantity)}원';

  static String _formatNumber(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
