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
  final List<int> categoryNos; // Cafe24 소속 카테고리 번호 목록
  final bool? _isNew;          // 신상품 여부 (Hot Reload null safety 방어)
  final bool? _isRecommend;    // 추천/베스트 상품 여부 (Hot Reload null safety 방어)
  final DateTime? createdDate; // 상품 등록일

  bool get isNew => (_isNew == true) || tag == 'NEW';
  bool get isRecommend => (_isRecommend == true) || tag == 'BEST';

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
    this.categoryNos = const [],
    bool isNew = false,
    bool isRecommend = false,
    this.createdDate,
  })  : _isNew = isNew,
        _isRecommend = isRecommend;

  /// Cafe24 API 응답 JSON -> Product 변환
  factory Product.fromCafe24Json(
    Map<String, dynamic> json, {
    bool forceNew = false,
    bool forceRecommend = false,
    String? forceTag,
    Color? forceTagColor,
  }) {
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

    // 이미지 URL 파싱 (Front API 및 Admin API 필드 호환)
    String? rawImage = json['list_image'] as String?;
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['list_image_url'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['detail_image'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['image_url'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['small_image'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['small_image_url'] as String?;
    }
    if (rawImage == null || rawImage.isEmpty) {
      rawImage = json['tiny_image'] as String?;
    }
    final imageUrl = _sanitizeImageUrl(rawImage);

    // Cafe24 카테고리 매핑 및 신상품/추천상품(베스트) 플래그 분석
    final List<int> categoryNos = [];
    bool isNew = forceNew;
    bool isRecommend = forceRecommend;

    // Cafe24 상품 최상위 플래그 확인
    if (json['new'] == 'T' || json['new'] == true || json['is_new'] == true) {
      isNew = true;
    }
    if (json['recommend'] == 'T' || json['recommend'] == true || json['is_recommend'] == true || json['hot'] == 'T') {
      isRecommend = true;
    }

    final rawCategory = json['category'];
    if (rawCategory is List) {
      for (final catItem in rawCategory) {
        if (catItem is Map<String, dynamic>) {
          final catNo = int.tryParse(catItem['category_no']?.toString() ?? '');
          if (catNo != null) categoryNos.add(catNo);
          if (catItem['new'] == 'T' || catItem['new'] == true) {
            isNew = true;
          }
          if (catItem['recommend'] == 'T' || catItem['recommend'] == true) {
            isRecommend = true;
          }
        } else if (catItem is int) {
          categoryNos.add(catItem);
        }
      }
    }

    // 등록일시 파싱
    final rawCreatedDate = json['created_date']?.toString() ??
        json['product_register_date']?.toString();
    final createdDate = DateTime.tryParse(rawCreatedDate ?? '');

    // 상품명 분석을 통한 카테고리 및 태그 보정
    final productName = json['product_name']?.toString() ?? '상품명 없음';
    final pNameLower = productName.toLowerCase();

    if (!isNew && (pNameLower.contains('new') || pNameLower.contains('신제품') || pNameLower.contains('신상품'))) {
      isNew = true;
    }
    if (!isRecommend && (pNameLower.contains('best') || pNameLower.contains('인기') || pNameLower.contains('베스트') || pNameLower.contains('추천'))) {
      isRecommend = true;
    }

    // 카테고리명 유추
    String inferredCategory = '생활용품';
    if (pNameLower.contains('롤매트')) {
      inferredCategory = '롤매트';
    } else if (pNameLower.contains('발매트') || pNameLower.contains('현관')) {
      inferredCategory = '현관발매트';
    } else if (pNameLower.contains('잔디')) {
      inferredCategory = '인조잔디';
    } else if (pNameLower.contains('청소') || pNameLower.contains('걸레') || pNameLower.contains('밀대')) {
      inferredCategory = '청소용품';
    } else if (pNameLower.contains('주방') || pNameLower.contains('식기') || pNameLower.contains('수납')) {
      inferredCategory = '생활 주방용품';
    } else if (pNameLower.contains('침구') || pNameLower.contains('이불') || pNameLower.contains('베개') || pNameLower.contains('패드')) {
      inferredCategory = '침구';
    }

    // 태그 결정 (forceTag -> NEW -> BEST -> SALE 우선순위)
    String tag = forceTag ?? 'BEST';
    Color tagColor = forceTagColor ?? const Color(0xFF1E293B);

    if (forceTag != null) {
      tag = forceTag;
      tagColor = forceTagColor ??
          (forceTag == 'NEW'
              ? const Color(0xFF16A34A)
              : (forceTag == 'MD' ? const Color(0xFF0284C7) : const Color(0xFF1E293B)));
    } else if (isNew) {
      tag = 'NEW';
      tagColor = const Color(0xFF16A34A);
    } else if (isRecommend) {
      tag = 'BEST';
      tagColor = const Color(0xFF1E293B);
    } else if (discountRate > 0) {
      tag = 'SALE';
      tagColor = const Color(0xFFE11D48);
    }

    return Product(
      id: json['product_no']?.toString() ?? '',
      name: productName,
      originalPrice: originalPrice,
      discountRate: discountRate,
      tag: tag,
      tagColor: tagColor,
      category: inferredCategory,
      imageUrl: imageUrl,
      icon: _matchProductIcon(inferredCategory),
      description: json['summary_description']?.toString() ??
          json['simple_description']?.toString() ??
          '',
      rating: 4.8,
      reviewCount: 50,
      categoryNos: categoryNos,
      isNew: isNew,
      isRecommend: isRecommend,
      createdDate: createdDate,
    );
  }

  static IconData _matchProductIcon(String category) {
    if (category.contains('롤매트')) return Icons.view_column_rounded;
    if (category.contains('현관') || category.contains('발매트')) return Icons.door_front_door_rounded;
    if (category.contains('잔디')) return Icons.grass_rounded;
    if (category.contains('청소')) return Icons.cleaning_services_rounded;
    if (category.contains('주방') || category.contains('생활')) return Icons.kitchen_rounded;
    if (category.contains('침구') || category.contains('이불')) return Icons.king_bed_rounded;
    return Icons.shopping_bag_outlined;
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
    final catClean = categoryName.replaceAll(' ', '').replaceAll('#', '').toLowerCase();
    final nameClean = name.replaceAll(' ', '').toLowerCase();
    final descClean = description.replaceAll(' ', '').toLowerCase();

    // 1. 신상품 카테고리 키워드 매칭
    if (catClean.contains('신상품') || catClean.contains('신제품') || catClean == 'new') {
      return isNew || tag == 'NEW';
    }

    // 2. 베스트 상품 카테고리 키워드 매칭
    if (catClean.contains('베스트') || catClean.contains('인기') || catClean == 'best') {
      return isRecommend || tag == 'BEST';
    }

    // 3. 특가/할인 매칭
    if (catClean.contains('특가') || catClean.contains('할인') || catClean == 'sale') {
      return discountRate > 0;
    }

    if (category.replaceAll(' ', '').toLowerCase().contains(catClean)) return true;

    if (catClean.contains('롤매트') && (nameClean.contains('롤매트') || nameClean.contains('매트'))) return true;
    if (catClean.contains('발매트') && (nameClean.contains('발매트') || nameClean.contains('현관') || nameClean.contains('매트'))) return true;
    if (catClean.contains('잔디') && (nameClean.contains('잔디') || nameClean.contains('인조잔디'))) return true;
    if (catClean.contains('청소') && (nameClean.contains('청소') || nameClean.contains('밀대') || nameClean.contains('걸레') || nameClean.contains('브러시'))) return true;
    if (catClean.contains('주방') && (nameClean.contains('주방') || nameClean.contains('생활') || nameClean.contains('식기') || nameClean.contains('수납'))) return true;
    if (catClean.contains('침구') && (nameClean.contains('침구') || nameClean.contains('이불') || nameClean.contains('패드') || nameClean.contains('토퍼') || nameClean.contains('베개'))) return true;

    return nameClean.contains(catClean) || descClean.contains(catClean);
  }
}
