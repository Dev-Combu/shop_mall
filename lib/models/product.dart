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
  final String? imageUrl;  // 상품 대표 이미지 URL
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
    this.icon = Icons.inventory_2_outlined,
    this.imageUrl,
    this.description = '',
    this.rating = 4.5,
    this.reviewCount = 0,
  });

  /// Cafe24 API 응답 JSON -> Product 변환
  factory Product.fromCafe24Json(Map<String, dynamic> json) {
    final originalPriceDouble = double.tryParse(json['retail_price']?.toString() ?? '') ??
        double.tryParse(json['price']?.toString() ?? '0') ??
        0.0;
    final salePriceDouble = double.tryParse(json['price']?.toString() ?? '0') ?? 0.0;

    int originalPrice = originalPriceDouble.round();
    if (originalPrice == 0) originalPrice = salePriceDouble.round();

    int discountRate = 0;
    if (originalPrice > salePriceDouble && originalPrice > 0) {
      discountRate = (((originalPrice - salePriceDouble) / originalPrice) * 100).round();
    }

    // 이미지 URL 파싱 (list_image -> detail_image -> small_image -> tiny_image 순)
    String? rawImage = json['list_image'] as String?;
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['detail_image'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['small_image'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['tiny_image'] as String?;
    }
    final imageUrl = _sanitizeImageUrl(rawImage);

    // 태그 결정
    String tag = 'BEST';
    Color tagColor = const Color(0xFF1E293B);
    if (discountRate > 0) {
      tag = 'SALE';
      tagColor = const Color(0xFFE11D48);
    }

    return Product(
      id: json['product_no']?.toString() ?? '',
      name: json['product_name']?.toString() ?? '상품명 없음',
      originalPrice: originalPrice,
      discountRate: discountRate,
      tag: tag,
      tagColor: tagColor,
      category: '상품',
      imageUrl: imageUrl,
      icon: Icons.shopping_bag_outlined,
      description: json['summary_description']?.toString() ??
          json['simple_description']?.toString() ??
          '',
      rating: 4.8,
      reviewCount: 50,
    );
  }

  static String? _sanitizeImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    return trimmed;
  }

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

  /// 카테고리명 또는 키워드와 매칭되는지 확인하는 헬퍼 메서드
  bool matchesCategory(String categoryName) {
    if (categoryName == '전체보기' || categoryName.trim().isEmpty) return true;
    final catClean = categoryName.replaceAll(' ', '').toLowerCase();
    final nameClean = name.replaceAll(' ', '').toLowerCase();
    final descClean = description.replaceAll(' ', '').toLowerCase();

    if (category.replaceAll(' ', '').toLowerCase().contains(catClean)) return true;

    if (catClean.contains('롤매트') && (nameClean.contains('롤매트') || nameClean.contains('매트'))) return true;
    if (catClean.contains('발매트') && (nameClean.contains('발매트') || nameClean.contains('현관') || nameClean.contains('매트'))) return true;
    if (catClean.contains('잔디') && (nameClean.contains('잔디') || nameClean.contains('인조잔디'))) return true;
    if (catClean.contains('청소') && (nameClean.contains('청소') || nameClean.contains('밀대') || nameClean.contains('걸레') || nameClean.contains('브러시'))) return true;
    if (catClean.contains('주방') && (nameClean.contains('주방') || nameClean.contains('생활') || nameClean.contains('식기') || nameClean.contains('수납'))) return true;
    if (catClean.contains('침구') && (nameClean.contains('침구') || nameClean.contains('이불') || nameClean.contains('패드') || nameClean.contains('토퍼') || nameClean.contains('베개'))) return true;
    if (catClean.contains('특가') || catClean.contains('할인')) return discountRate > 0;

    return nameClean.contains(catClean) || descClean.contains(catClean);
  }
}
