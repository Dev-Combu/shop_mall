import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/product_data.dart';

/// 웹사이트 메인 진열 신상품 (NEW PRODUCT: display_group = 2)
final newProductsProvider = FutureProvider<List<Product>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);
  if (!api.hasCredentials) {
    return ProductDataService.newProducts;
  }

  try {
    final mainNews = await api.fetchMainDisplayProducts(
      2,
      limit: 30,
      forceNew: true,
      forceTag: 'NEW',
    );
    if (mainNews.isNotEmpty) {
      return mainNews;
    }
  } catch (e) {
    // ignore: avoid_print
    print('[newProductsProvider] 메인 진열(2: 신상품) 로드 실패: $e');
  }

  return ProductDataService.newProducts;
});

/// 웹사이트 메인 진열 베스트 상품 (BEST MAT TOP 10: display_group = 3)
final bestProductsProvider = FutureProvider<List<Product>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);
  if (!api.hasCredentials) {
    return ProductDataService.bestProducts;
  }

  try {
    final mainBests = await api.fetchMainDisplayProducts(
      3,
      limit: 30,
      forceRecommend: true,
      forceTag: 'BEST',
    );
    if (mainBests.isNotEmpty) {
      return mainBests;
    }
  } catch (e) {
    // ignore: avoid_print
    print('[bestProductsProvider] 메인 진열(3: 베스트) 로드 실패: $e');
  }

  return ProductDataService.bestProducts;
});

/// 웹사이트 메인 진열 기타 추천 상품 (OTHER: display_group = 4)
final otherProductsProvider = FutureProvider<List<Product>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);
  if (!api.hasCredentials) {
    return ProductDataService.otherProducts;
  }

  try {
    final mainOthers = await api.fetchMainDisplayProducts(
      4,
      limit: 20,
      forceTag: 'MD',
    );
    if (mainOthers.isNotEmpty) {
      return mainOthers;
    }
  } catch (e) {
    // ignore: avoid_print
    print('[otherProductsProvider] 메인 진열(4: 기타) 로드 실패: $e');
  }

  return ProductDataService.otherProducts;
});

/// 전체 상품 목록 Provider (신상품 + 베스트 + 일반 상품 통합, 카테고리/검색 화면에서 활용)
final homeProductsProvider = FutureProvider<List<Product>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);

  if (!api.hasCredentials) {
    return ProductDataService.all;
  }

  try {
    // 메인 진열 신상품(2), 베스트(3)와 일반 상품 목록을 병렬로 조회하여 통합
    final results = await Future.wait([
      ref.watch(newProductsProvider.future),
      ref.watch(bestProductsProvider.future),
      api.fetchProducts(limit: 50),
    ]);

    final news = results[0];
    final bests = results[1];
    final generals = results[2];

    final Map<String, Product> mergedMap = {};
    for (final p in news) {
      mergedMap[p.id] = p;
    }
    for (final p in bests) {
      if (!mergedMap.containsKey(p.id)) {
        mergedMap[p.id] = p;
      }
    }
    for (final p in generals) {
      if (!mergedMap.containsKey(p.id)) {
        mergedMap[p.id] = p;
      }
    }

    if (mergedMap.isNotEmpty) {
      return mergedMap.values.toList();
    }
    return ProductDataService.all;
  } catch (e) {
    // ignore: avoid_print
    print('[homeProductsProvider] Cafe24 API 로드 실패 (기본 데이터로 대체): $e');
    return ProductDataService.all;
  }
});
