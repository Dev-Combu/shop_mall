import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/product_data.dart';

/// 홈 화면 상품 목록 Provider (Cafe24 API 연동 + Fallback 더미 데이터 지원)
final homeProductsProvider = FutureProvider<List<Product>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);

  // 1. 토큰이 없는 경우 fallback 더미 데이터 반환
  if (api.accessToken.isEmpty && api.refreshToken.isEmpty) {
    return ProductDataService.all;
  }

  // 2. 실제 Cafe24 쇼핑몰 API 호출
  try {
    final products = await api.fetchProducts(limit: 30);
    if (products.isNotEmpty) {
      return products;
    }
    return ProductDataService.all;
  } catch (e) {
    // API 호출 실패 시 원인 로그 출력 후 안전하게 기본 데이터 반환
    // ignore: avoid_print
    print('[homeProductsProvider] Cafe24 API 로드 실패 (기본 데이터로 대체): $e');
    return ProductDataService.all;
  }
});

/// 신상품 필터 Provider
final newProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final allAsync = ref.watch(homeProductsProvider);
  return allAsync.whenData((products) {
    final news = products.where((p) => p.tag == 'NEW').toList();
    if (news.isEmpty) return products.take(4).toList();
    return news;
  });
});

/// 베스트 상품 필터 Provider
final bestProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final allAsync = ref.watch(homeProductsProvider);
  return allAsync.whenData((products) {
    final bests = products.where((p) => p.tag == 'BEST' || p.tag == 'SALE').toList();
    if (bests.isEmpty) return products.skip(4).take(4).toList();
    return bests;
  });
});

