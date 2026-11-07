import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';

/// 회원(또는 비회원)별로 상품 목록을 보안 저장소에 보관하는 공통 Notifier.
/// 찜한 상품 / 최근 본 상품에서 사용합니다.
abstract class _SavedProductsNotifier extends Notifier<List<Product>> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _memberId;
  Future<void> _loaded = Future.value();

  String get keyPrefix;
  int get maxItems;

  String get _storageKey => '${keyPrefix}_${_memberId ?? 'guest'}';

  @override
  List<Product> build() {
    _memberId = ref.watch(authProvider)?.id;
    _loaded = _load();
    return [];
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          state = list
              .whereType<Map<String, dynamic>>()
              .map(Product.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[$keyPrefix] 로드 실패: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(state.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[$keyPrefix] 저장 실패: $e');
    }
  }

  bool contains(String productId) => state.any((p) => p.id == productId);

  Future<void> remove(String productId) async {
    await _loaded;
    state = state.where((p) => p.id != productId).toList();
    await _persist();
  }

  Future<void> clear() async {
    await _loaded;
    state = [];
    await _persist();
  }

  /// 맨 앞에 추가(이미 있으면 앞으로 이동)하고 최대 개수를 유지
  Future<void> _addFirst(Product product) async {
    await _loaded; // 저장된 목록 로드 전에 추가되어 덮어써지는 경쟁 상태 방지
    final next = [product, ...state.where((p) => p.id != product.id)];
    state = next.length > maxItems ? next.sublist(0, maxItems) : next;
    await _persist();
  }
}

/// 찜한 상품
class FavoritesViewModel extends _SavedProductsNotifier {
  @override
  String get keyPrefix => 'cafe24_favorites';
  @override
  int get maxItems => 200;

  Future<void> toggle(Product product) async {
    if (contains(product.id)) {
      await remove(product.id);
    } else {
      await _addFirst(product);
    }
  }
}

/// 최근 본 상품
class RecentViewModel extends _SavedProductsNotifier {
  @override
  String get keyPrefix => 'cafe24_recent';
  @override
  int get maxItems => 30;

  Future<void> record(Product product) => _addFirst(product);
}

final favoritesProvider =
    NotifierProvider<FavoritesViewModel, List<Product>>(FavoritesViewModel.new);
final recentProvider =
    NotifierProvider<RecentViewModel, List<Product>>(RecentViewModel.new);
