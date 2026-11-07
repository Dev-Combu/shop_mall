import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/cafe24_web_cart_service.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';

/// 앱은 로그인되어 있으나 Cafe24 웹뷰 세션이 만료되어 대화형 재인증이 필요한지 여부
class WebSessionDisconnectedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setDisconnected(bool value) {
    if (state != value) {
      state = value;
    }
  }
}

final webSessionDisconnectedProvider =
    NotifierProvider<WebSessionDisconnectedNotifier, bool>(
  WebSessionDisconnectedNotifier.new,
);

/// Cafe24 DB 및 쇼핑몰 세션과 실시간 동기화되는 장바구니 ViewModel
class CartViewModel extends Notifier<List<CartItem>> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Cafe24ApiService _api;
  late Cafe24WebCartService _webCartService;
  User? _currentUser;
  String? _memberId;

  /// 웹뷰 세션이 일시 단절된 동안 앱에서 발생한 변경사항 존재 여부 (재연결 시 서버로 자동 반영)
  bool _hasPendingLocalMutations = false;

  /// 사용자가 명시적으로 '전체 비우기'를 수행했는지 여부 (비정상 빈 스냅샷으로 인한 로컬 장바구니 증발 방지)
  bool _userInitiatedClear = false;

  String get _storageKey =>
      (_memberId != null && _memberId!.isNotEmpty)
          ? 'cafe24_db_cart_${_memberId!}'
          : 'cafe24_db_cart_guest';

  String get _backupStorageKey => '${_storageKey}_backup';

  bool get _isRealCafe24Member =>
      _currentUser != null &&
      _memberId != null &&
      _memberId!.isNotEmpty &&
      _memberId != 'suzicnl1';

  @override
  List<CartItem> build() {
    _api = ref.watch(cafe24ApiServiceProvider);
    _webCartService = ref.watch(cafe24WebCartServiceProvider);
    _currentUser = ref.watch(authProvider);
    _memberId = _currentUser?.id;

    // 로그아웃 상태에서는 세션 단절 배너 해제
    if (!_isRealCafe24Member) {
      Future.microtask(() {
        ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(false);
      });
    }

    // 앱 시작 및 로그인 상태 변경 시 저장소 & Cafe24 서버 DB에서 장바구니 로드
    _loadAndSyncCart();
    return [];
  }

  Future<String?> _getMemberPassword() async {
    final id = _memberId;
    if (id == null || id.isEmpty) return null;
    return ref.read(authProvider.notifier).getMemberPassword(id);
  }

  /// 웹뷰 대화형 재로그인이 완료되었을 때 호출하여 보류 중이던 변경분 반영 및 최신 장바구니 동기화
  Future<void> onWebSessionRestored() async {
    _webCartService.resetSilentLoginCooldown();
    ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(false);
    await _loadAndSyncCart(forceReload: true);
  }

  /// 로컬 보안 저장소 복원 + Cafe24 서버 회원 장바구니 DB 동기화
  Future<void> _loadAndSyncCart({bool forceReload = false}) async {
    List<CartItem> localItems = [];
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          localItems = decoded
              .whereType<Map<String, dynamic>>()
              .map((json) => CartItem.fromJson(json))
              .toList();
          if (localItems.isNotEmpty) {
            state = localItems;
          }
        }
      }
    } catch (e) {
      debugPrint('[CartViewModel] 로컬 장바구니 복원 실패: $e');
    }

    // 로컬 저장소가 비어있을 때 백업 저장소에서 2차 복구 시도 (꼬임 방지 안전망)
    if (localItems.isEmpty && !_userInitiatedClear) {
      try {
        final backupRaw = await _storage.read(key: _backupStorageKey);
        if (backupRaw != null && backupRaw.isNotEmpty) {
          final decoded = jsonDecode(backupRaw);
          if (decoded is List && decoded.isNotEmpty) {
            localItems = decoded
                .whereType<Map<String, dynamic>>()
                .map((json) => CartItem.fromJson(json))
                .toList();
            if (localItems.isNotEmpty) {
              state = localItems;
              debugPrint('[CartViewModel] 백업 저장소에서 장바구니 ${localItems.length}건 안전 복구');
            }
          }
        }
      } catch (_) {}
    }

    final memberId = _memberId;
    if (memberId == null || memberId.isEmpty || memberId == 'suzicnl1') {
      return;
    }

    // 비회원(guest) 상태에서 담아두었던 장바구니 상품이 있다면 회원 장바구니로 자동 병합
    bool mergedGuestItems = false;
    try {
      final guestRaw = await _storage.read(key: 'cafe24_db_cart_guest');
      if (guestRaw != null && guestRaw.isNotEmpty) {
        final guestDecoded = jsonDecode(guestRaw);
        if (guestDecoded is List && guestDecoded.isNotEmpty) {
          final guestItems = guestDecoded
              .whereType<Map<String, dynamic>>()
              .map((json) => CartItem.fromJson(json))
              .toList();

          final Map<String, CartItem> merged = {
            for (final item in localItems) item.product.id: item,
          };
          for (final gItem in guestItems) {
            if (merged.containsKey(gItem.product.id)) {
              final existing = merged[gItem.product.id]!;
              merged[gItem.product.id] = existing.copyWith(
                quantity: existing.quantity + gItem.quantity,
              );
            } else {
              merged[gItem.product.id] = gItem;
            }
          }
          localItems = merged.values.toList();
          state = localItems;
          mergedGuestItems = true;
          await _storage.delete(key: 'cafe24_db_cart_guest');
          await _persistCart();
        }
      }
    } catch (_) {}

    final pw = await _getMemberPassword();

    // 1. Cafe24 WebKit 세션(/order/basket.html) 실시간 스냅샷 조회 (무자각 자동 재로그인 및 DOM 스크래핑 포함)
    WebBasketSnapshot snapshot = const WebBasketSnapshot(
      isLoggedIn: false,
      fetchSucceeded: false,
      items: [],
    );
    try {
      snapshot = await _webCartService.fetchBasketSnapshot(
        expectedUser: _currentUser,
        password: pw,
        forceReload: forceReload,
      );
    } catch (e) {
      debugPrint('[CartViewModel] Cafe24 웹 세션 장바구니 조회 오류: $e');
    }

    // 웹뷰 로그인이 풀려 있고 무자각 복구도 실패한 경우:
    // 비회원 빈 장바구니([])로 로컬 회원 장바구니를 절대 덮어쓰지 않고 보호!
    if (!snapshot.isLoggedIn) {
      ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
      if (mergedGuestItems) {
        _hasPendingLocalMutations = true;
      }

      return;
    }

    // 웹뷰 로그인 세션 정상 활성 상태!
    ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(false);

    List<CartItem> webItemsParsed = await _parseRawWebItems(
      snapshot.items,
      localItems.isNotEmpty ? localItems : state,
    );

    // 세션 단절 중 로컬 변경사항(또는 비회원 병합분)이 있었다면 Cafe24 웹 장바구니에 먼저 정합성 반영
    if (_hasPendingLocalMutations || mergedGuestItems) {
      _hasPendingLocalMutations = false;
      await _reconcileLocalStateToCafe24(
        localTarget: state.isNotEmpty ? state : localItems,
        currentRemote: webItemsParsed,
        password: pw,
      );
      final refreshedSnap = await _webCartService.fetchBasketSnapshot(
        expectedUser: _currentUser,
        password: pw,
        forceReload: true,
      );
      if (refreshedSnap.isLoggedIn && refreshedSnap.fetchSucceeded) {
        webItemsParsed = await _parseRawWebItems(
          refreshedSnap.items,
          state.isNotEmpty ? state : localItems,
        );
        snapshot = refreshedSnap;
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 정합성 동기화 및 꼬임 방지 안전망
    // ─────────────────────────────────────────────────────────────
    if (webItemsParsed.isNotEmpty) {
      // 1. 서버에 데이터가 정상적으로 존재하는 경우: 서버 데이터를 단일 진실 공급원으로 반영
      final Map<String, CartItem> prevById = {
        for (final item in state) item.product.id: item,
      };
      state = [
        for (final rItem in webItemsParsed)
          rItem.copyWith(
            isSelected: prevById[rItem.product.id]?.isSelected ?? true,
          ),
      ];
      await _persistCart();
    } else if (snapshot.fetchSucceeded) {
      // 2. 서버 장바구니가 0개로 읽힌 경우:
      final hasLocalData = state.isNotEmpty || localItems.isNotEmpty;

      if (hasLocalData && !_userInitiatedClear) {
        // [핵심 방어] 사용자가 직접 '전체 비우기'를 누른 적이 없는데 서버 스냅샷이 0개라면
        // 세션 타이밍 오류나 꼬임 현상이므로 로컬 장바구니를 절대 지우지 않고 유지하며,
        // 서버로 로컬 장바구니 품목을 즉시 재동기화(Push)하여 양방향 복원 수행!
        debugPrint('[CartViewModel] 비정상 빈 스냅샷 감지 -> 로컬 장바구니 보존 및 서버 재적재 시작');
        final targetItems = state.isNotEmpty ? state : localItems;
        _hasPendingLocalMutations = true;
        await _reconcileLocalStateToCafe24(
          localTarget: targetItems,
          currentRemote: [],
          password: pw,
        );
        final checkSnap = await _webCartService.fetchBasketSnapshot(
          expectedUser: _currentUser,
          password: pw,
          forceReload: true,
        );
        if (checkSnap.items.isNotEmpty) {
          final recovered = await _parseRawWebItems(checkSnap.items, targetItems);
          if (recovered.isNotEmpty) {
            state = recovered;
            await _persistCart();
          }
        }
      } else {
        // 사용자가 명시적으로 비웠거나 애초에 담긴 상품이 없는 진짜 빈 장바구니인 경우
        state = [];
        await _persistCart();
      }
    }
  }

  String _cleanOptionText(String text) {
    var cleaned = text.trim();
    // 앞뒤 중복 대괄호 제거: [[옵션: 120x100cm당]] -> 옵션: 120x100cm당
    while (cleaned.startsWith('[') && cleaned.endsWith(']') && cleaned.length >= 2) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    // 접두사 '옵션:' 정리
    if (cleaned.startsWith('옵션:') || cleaned.startsWith('옵션 :')) {
      cleaned = cleaned.substring(cleaned.indexOf(':') + 1).trim();
    }
    return cleaned;
  }

  Future<List<CartItem>> _parseRawWebItems(
    List<Map<String, dynamic>> rawList,
    List<CartItem> referenceItems,
  ) async {
    final List<CartItem> parsedList = [];
    final Set<CartItem> usedRefs = {};

    for (final raw in rawList) {
      final pNo = raw['product_no']?.toString() ?? '';
      final qty = int.tryParse(raw['quantity']?.toString() ?? '1') ?? 1;
      final bNo = int.tryParse(raw['basket_product_no']?.toString() ?? '');
      if (pNo.isNotEmpty) {
        // 기존 장바구니 품목에서 1:1 매칭하여 옵션 및 추가금액 보존
        CartItem? refItem;
        if (bNo != null && bNo > 0) {
          for (final it in referenceItems) {
            if (!usedRefs.contains(it) && it.basketProductNo == bNo) {
              refItem = it;
              usedRefs.add(it);
              break;
            }
          }
        }
        if (refItem == null) {
          for (final it in referenceItems) {
            if (!usedRefs.contains(it) && it.product.id == pNo) {
              refItem = it;
              usedRefs.add(it);
              break;
            }
          }
        }

        Product? prod = refItem?.product;
        if (prod == null) {
          try {
            prod = await _api.fetchProductDetail(pNo);
          } catch (_) {}
        }
        // [품목 유실 방지] API 상세 조회가 지연되거나 실패하더라도 스냅샷의 이름과 가격으로 기본 Product 객체를 생성하여 절대 누락되지 않도록 보장
        final rawName = (raw['product_name'] ?? '').toString().trim();
        final rawPrice = int.tryParse(raw['price']?.toString() ?? '0') ?? 0;
        prod ??= Product(
          id: pNo,
          name: rawName.isNotEmpty ? rawName : '상품 #$pNo',
          originalPrice: rawPrice,
          category: '기타',
          tag: 'BEST',
          tagColor: const Color(0xFF64748B),
        );

        // 원격 스냅샷에 옵션 문자열이 있다면 파싱, 없다면 기존 로컬 옵션 그대로 보존
        List<String> finalOptions = refItem?.selectedOptions ?? const [];
        if (raw['options'] is List) {
          final optList = (raw['options'] as List)
              .map((e) => _cleanOptionText(e.toString()))
              .where((e) => e.isNotEmpty)
              .toList();
          if (optList.isNotEmpty) {
            finalOptions = optList;
          }
        } else if (raw['option_str'] != null && raw['option_str'].toString().trim().isNotEmpty) {
          final optStr = _cleanOptionText(raw['option_str'].toString());
          if (optStr.isNotEmpty) {
            finalOptions = [optStr];
          }
        } else if (finalOptions.isNotEmpty) {
          finalOptions = finalOptions.map(_cleanOptionText).toList();
        }

        // 옵션 추가금액 계산: 원격 실제 판매단가(rawPrice/qty)와 본품 할인가(prod.salePrice)의 차액 반영
        int finalAdditionalAmount = refItem?.optionAdditionalAmount ?? 0;
        if (rawPrice > 0 && qty > 0 && prod.salePrice > 0) {
          final remoteUnitPrice = rawPrice ~/ qty;
          final diff = remoteUnitPrice - prod.salePrice;
          if (diff != 0) {
            finalAdditionalAmount = diff;
          }
        }

        parsedList.add(
          CartItem(
            product: prod,
            quantity: qty,
            basketProductNo: bNo,
            isSelected: refItem?.isSelected ?? true,
            selectedOptions: finalOptions,
            optionAdditionalAmount: finalAdditionalAmount,
          ),
        );
      }
    }
    return parsedList;
  }

  /// 세션 복구 직후 로컬 장바구니 변경분을 Cafe24 회원 장바구니에 동기화
  Future<void> _reconcileLocalStateToCafe24({
    required List<CartItem> localTarget,
    required List<CartItem> currentRemote,
    required String? password,
  }) async {
    // 만약 로컬이 비어있는데 원격에 품목이 있는 경우:
    // 로컬이 일시적으로 비워진 것이므로 원격 품목을 지우지 않고 원격 품목으로 로컬을 복원!
    if (localTarget.isEmpty && currentRemote.isNotEmpty && !_userInitiatedClear) {
      state = currentRemote;
      await _persistCart();
      return;
    }

    final localById = {for (final it in localTarget) it.product.id: it};
    final remoteById = {for (final it in currentRemote) it.product.id: it};

    // 1. 로컬에서 삭제된 원격 품목 제거 (단, localTarget이 유효할 때만 실행)
    if (localTarget.isNotEmpty) {
      for (final rItem in currentRemote) {
        if (!localById.containsKey(rItem.product.id)) {
          await _webCartService.deleteItem(
            basketProductNo: rItem.basketProductNo,
            productNo: rItem.product.id,
            expectedUser: _currentUser,
            password: password,
          );
        }
      }
    }

    // 2. 로컬에서 추가되거나 수량이 변경된 품목 반영
    for (final lItem in localTarget) {
      if (int.tryParse(lItem.product.id) == null) continue;
      final rItem = remoteById[lItem.product.id];
      if (rItem == null) {
        await _webCartService.addItem(
          productNo: lItem.product.id,
          quantity: lItem.quantity,
          expectedUser: _currentUser,
          password: password,
        );
      } else if (rItem.quantity != lItem.quantity) {
        await _webCartService.updateQuantity(
          basketProductNo: rItem.basketProductNo,
          productNo: lItem.product.id,
          quantity: lItem.quantity,
          expectedUser: _currentUser,
          password: password,
        );
      }
    }
  }

  Future<void> _persistCart() async {
    try {
      final encoded = jsonEncode(state.map((e) => e.toJson()).toList());
      await _storage.write(key: _storageKey, value: encoded);
      if (state.isNotEmpty) {
        await _storage.write(key: _backupStorageKey, value: encoded);
      }
    } catch (e) {
      debugPrint('[CartViewModel] 장바구니 영구 저장 오류: $e');
    }
  }

  Future<void> _clearBackupStorage() async {
    try {
      await _storage.delete(key: _backupStorageKey);
    } catch (_) {}
  }

  /// 상품 추가 (로컬 상태 + 영구 저장소 + Cafe24 웹 세션 및 서버 DB 동시 반영)
  Future<void> addProduct(
    Product product, {
    int quantity = 1,
    List<String> selectedOptions = const [],
    int optionAdditionalAmount = 0,
  }) async {
    _userInitiatedClear = false;
    final index = state.indexWhere(
      (item) =>
          item.product.id == product.id &&
          listEquals(item.selectedOptions, selectedOptions),
    );
    if (index >= 0) {
      final existing = state[index];
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            existing.copyWith(
              quantity: existing.quantity + quantity,
              isSelected: true,
            )
          else
            state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(
          product: product,
          quantity: quantity,
          isSelected: true,
          selectedOptions: selectedOptions,
          optionAdditionalAmount: optionAdditionalAmount,
        ),
      ];
    }

    await _persistCart();

    final pw = await _getMemberPassword();
    final synced = await _webCartService.addItem(
      productNo: product.id,
      quantity: quantity,
      selectedOptions: selectedOptions,
      expectedUser: _currentUser,
      password: pw,
    );

    if (synced) {
      await refreshFromCafe24();
    } else if (_isRealCafe24Member) {
      _hasPendingLocalMutations = true;
      ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
    }
  }

  /// 수량 변경 (Cafe24 웹 세션 및 서버 동기화 포함)
  Future<void> updateQuantity(String productId, int newQuantity) async {
    if (newQuantity <= 0) {
      await removeItem(productId);
      return;
    }

    final targetItem =
        state.where((item) => item.product.id == productId).firstOrNull;
    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.copyWith(quantity: newQuantity)
        else
          item,
    ];

    await _persistCart();

    if (targetItem != null) {
      final pw = await _getMemberPassword();
      final synced = await _webCartService.updateQuantity(
        basketProductNo: targetItem.basketProductNo,
        productNo: productId,
        quantity: newQuantity,
        expectedUser: _currentUser,
        password: pw,
      );
      if (synced) {
        await refreshFromCafe24();
      } else if (_isRealCafe24Member) {
        _hasPendingLocalMutations = true;
        ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
      }
    }
  }

  /// 선택 상태 토글
  Future<void> toggleSelection(String productId) async {
    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.copyWith(isSelected: !item.isSelected)
        else
          item,
    ];
    await _persistCart();
  }

  /// 전체 선택 / 해제
  Future<void> toggleAllSelection(bool selectAll) async {
    state = [
      for (final item in state) item.copyWith(isSelected: selectAll),
    ];
    await _persistCart();
  }

  /// 아이템 삭제 (Cafe24 웹 세션 및 서버 동기화 포함)
  Future<void> removeItem(String productId) async {
    final targetItem =
        state.where((item) => item.product.id == productId).firstOrNull;
    state = state.where((item) => item.product.id != productId).toList();
    await _persistCart();

    if (targetItem != null) {
      final pw = await _getMemberPassword();
      final synced = await _webCartService.deleteItem(
        basketProductNo: targetItem.basketProductNo,
        productNo: productId,
        expectedUser: _currentUser,
        password: pw,
      );
      if (synced) {
        await refreshFromCafe24();
      } else if (_isRealCafe24Member) {
        _hasPendingLocalMutations = true;
        ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
      }
    }
  }

  /// 선택된 아이템들 삭제 (Cafe24 웹 세션 및 서버 동기화 포함)
  Future<void> removeSelected() async {
    final removedItems = state.where((item) => item.isSelected).toList();
    state = state.where((item) => !item.isSelected).toList();
    await _persistCart();

    final pw = await _getMemberPassword();
    bool allSynced = true;
    for (final item in removedItems) {
      final ok = await _webCartService.deleteItem(
        basketProductNo: item.basketProductNo,
        productNo: item.product.id,
        expectedUser: _currentUser,
        password: pw,
      );
      if (!ok) allSynced = false;
    }

    if (allSynced) {
      await refreshFromCafe24();
    } else if (_isRealCafe24Member) {
      _hasPendingLocalMutations = true;
      ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
    }
  }

  /// 전체 비우기 (Cafe24 웹 세션 및 서버 동기화 포함)
  Future<void> clear() async {
    _userInitiatedClear = true;
    state = [];
    await _persistCart();
    await _clearBackupStorage();
    final pw = await _getMemberPassword();
    final synced = await _webCartService.clearBasket(
      expectedUser: _currentUser,
      password: pw,
    );
    _userInitiatedClear = false;
    if (synced) {
      await refreshFromCafe24(forceReload: true);
    } else if (_isRealCafe24Member) {
      _hasPendingLocalMutations = true;
      ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(true);
    }
  }

  /// 수동으로 Cafe24 서버 장바구니 새로고침 (웹뷰 강제 재로딩 및 양방향 동기화 복구)
  Future<void> refreshFromCafe24({bool forceReload = true}) =>
      _loadAndSyncCart(forceReload: forceReload);
}

final cartProvider = NotifierProvider<CartViewModel, List<CartItem>>(
  CartViewModel.new,
);

/// Cafe24 [mall.read_shipping] 실시간 배송비 설정 Provider
final shippingSettingsProvider =
    FutureProvider<({int baseFee, int freeThreshold})?>((ref) async {
  final api = ref.watch(cafe24ApiServiceProvider);
  return api.fetchShippingSettings();
});

/// 계산 유틸리티를 위한 계산 결과 Provider
final cartSummaryProvider = Provider((ref) {
  final items = ref.watch(cartProvider);
  final selectedItems = items.where((item) => item.isSelected).toList();

  final int totalOriginalPrice =
      selectedItems.fold(0, (sum, item) => sum + item.totalOriginalPrice);
  final int totalSalePrice =
      selectedItems.fold(0, (sum, item) => sum + item.totalPrice);
  final int totalDiscount = totalOriginalPrice - totalSalePrice;

  // Cafe24 실시간 배송 설정 연동 (미설정 시 기본 30,000원 이상 무료배송, 이하 3,000원)
  final shippingSettings = ref.watch(shippingSettingsProvider).value;
  final int baseFee = shippingSettings?.baseFee ?? 3000;
  final int freeShippingThreshold = shippingSettings?.freeThreshold ?? 30000;
  final int shippingFee =
      (totalSalePrice >= freeShippingThreshold || selectedItems.isEmpty)
          ? 0
          : baseFee;
  final int finalPrice = totalSalePrice + shippingFee;

  final bool isAllSelected =
      items.isNotEmpty && items.every((item) => item.isSelected);

  return CartSummary(
    totalCount: items.length,
    selectedCount: selectedItems.length,
    totalOriginalPrice: totalOriginalPrice,
    totalSalePrice: totalSalePrice,
    totalDiscount: totalDiscount,
    shippingFee: shippingFee,
    freeShippingThreshold: freeShippingThreshold,
    finalPrice: finalPrice,
    isAllSelected: isAllSelected,
  );
});

class CartSummary {
  final int totalCount;
  final int selectedCount;
  final int totalOriginalPrice;
  final int totalSalePrice;
  final int totalDiscount;
  final int shippingFee;
  final int freeShippingThreshold;
  final int finalPrice;
  final bool isAllSelected;

  CartSummary({
    required this.totalCount,
    required this.selectedCount,
    required this.totalOriginalPrice,
    required this.totalSalePrice,
    required this.totalDiscount,
    required this.shippingFee,
    required this.freeShippingThreshold,
    required this.finalPrice,
    required this.isAllSelected,
  });

  /// 숫자를 세 자릿수 콤마 포맷으로 변환
  static String format(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
