import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/category.dart';
import 'package:shopmall/services/cafe24_api_service.dart';

/// 외부(홈 화면 등)에서 특정 카테고리나 필터(예: '신상품', '베스트', '롤매트')를 선택하여 진입할 때 사용하는 Notifier
class SelectedCategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) {
    state = filter;
  }

  void clear() {
    state = null;
  }
}

final selectedCategoryFilterProvider =
    NotifierProvider<SelectedCategoryFilterNotifier, String?>(
  SelectedCategoryFilterNotifier.new,
);

/// 앱 기본 Fallback 카테고리 목록
final defaultCategories = [
  const ShopCategory(id: 24, name: '전체보기', depth: 1, icon: Icons.grid_view_rounded),
  const ShopCategory(id: 181, name: '롤매트', depth: 2, icon: Icons.view_column_rounded),
  const ShopCategory(id: 42, name: '현관발매트', depth: 2, icon: Icons.door_front_door_rounded),
  const ShopCategory(id: 44, name: '인조잔디', depth: 2, icon: Icons.grass_rounded),
  const ShopCategory(id: 45, name: '청소용품', depth: 2, icon: Icons.cleaning_services_rounded),
  const ShopCategory(id: 46, name: '생활 주방용품', depth: 2, icon: Icons.kitchen_rounded),
  const ShopCategory(id: 48, name: '침구', depth: 2, icon: Icons.king_bed_rounded),
];

/// Cafe24 전체 카테고리 목록 (depth 1 ~ 4 원본)
final allCategoriesProvider = FutureProvider<List<ShopCategory>>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);

  if (!api.hasCredentials) {
    return defaultCategories;
  }

  try {
    final liveCategories = await api.fetchCategories();
    return liveCategories.isNotEmpty ? liveCategories : defaultCategories;
  } catch (e) {
    debugPrint('[allCategoriesProvider] 카테고리 로드 실패: $e');
    return defaultCategories;
  }
});

/// 주요 카테고리 목록 (depth 2 대분류: 롤매트, 현관발매트, 인조잔디, 청소용품, 생활주방, 침구 등)
final categoriesProvider = FutureProvider<List<ShopCategory>>((ref) async {
  final all = await ref.watch(allCategoriesProvider.future);

  // depth 2에 해당하는 주요 카테고리 추출
  final depth2Categories = all.where((c) => c.depth == 2).toList();
  if (depth2Categories.isNotEmpty) {
    return [
      const ShopCategory(id: 24, name: '전체보기', depth: 1, icon: Icons.grid_view_rounded),
      ...depth2Categories,
    ];
  }
  return all;
});
