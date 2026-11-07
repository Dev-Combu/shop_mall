import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/services/cafe24_web_cart_service.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cafe24 주문서 사전 입력용 배송지 및 결제 정보
class Cafe24OrderPrefill {
  final String recipientName;
  final String recipientPhone;
  final String zipCode;
  final String address1;
  final String address2;
  final String deliveryMemo;
  final String paymentMethod;
  final int usedPoints;

  const Cafe24OrderPrefill({
    required this.recipientName,
    required this.recipientPhone,
    required this.zipCode,
    required this.address1,
    required this.address2,
    required this.deliveryMemo,
    this.paymentMethod = '신용/체크카드',
    this.usedPoints = 0,
  });
}

/// Cafe24 웹뷰 결제 결과 상태
enum Cafe24OrderStatus {
  success,
  failure,
  canceled,
}

/// Cafe24 웹뷰 결제 결과 객체
class Cafe24OrderResult {
  final Cafe24OrderStatus status;
  final String? orderId;
  final String? message;

  const Cafe24OrderResult.success(this.orderId)
      : status = Cafe24OrderStatus.success,
        message = null;

  const Cafe24OrderResult.failure(this.message)
      : status = Cafe24OrderStatus.failure,
        orderId = null;

  const Cafe24OrderResult.canceled([this.message])
      : status = Cafe24OrderStatus.canceled,
        orderId = null;

  bool get isSuccess =>
      status == Cafe24OrderStatus.success &&
      orderId != null &&
      orderId!.isNotEmpty;
  bool get isFailure => status == Cafe24OrderStatus.failure;
  bool get isCanceled => status == Cafe24OrderStatus.canceled;
}

/// Cafe24 공식 주문서(/order/orderform.html) + PG 결제를 진행하는 인앱 웹뷰 화면
class Cafe24OrderWebViewPage extends ConsumerStatefulWidget {
  final CheckoutArgs args;
  final Cafe24OrderPrefill prefill;

  const Cafe24OrderWebViewPage({
    super.key,
    required this.args,
    required this.prefill,
  });

  /// 결제 화면을 열고 결제 결과(성공/실패/취소)를 반환
  static Future<Cafe24OrderResult?> open(
    BuildContext context, {
    required CheckoutArgs args,
    required Cafe24OrderPrefill prefill,
  }) {
    return Navigator.of(context).push<Cafe24OrderResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Cafe24OrderWebViewPage(args: args, prefill: prefill),
      ),
    );
  }

  @override
  ConsumerState<Cafe24OrderWebViewPage> createState() =>
      _Cafe24OrderWebViewPageState();
}

class _Cafe24OrderWebViewPageState
    extends ConsumerState<Cafe24OrderWebViewPage> {
  static const String _mallBase = 'https://suzicnl.com';
  static const String _kakaoJsKey = 'd6643748e516858c8b6138b85638b1bb';

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _orderFormPrefilled = false;
  bool _isOrderFormReady = false;
  bool _showWebViewInteractive = false;
  bool _completed = false;
  bool _isOnLoginPage = false;

  // 로그인 복구 및 비회원 전환 무한루프 방지 플래그
  bool _autoLoginAttempted = false;
  bool _guestProceedAttempted = false;
  bool _forceGuestOrder = false;

  // 주문 진입 단계 제어 플래그
  bool _singleBuyTriggered = false;
  bool _basketInspected = false;
  bool _basketOrderSubmitted = false;
  final List<CartItem> _pendingMissingItems = [];
  CartItem? _currentlyAddingMissingItem;

  String _stepLabel = '주문서를 안전하게 연결하고 있습니다...';
  String? _notice;

  /// 장바구니 경유 주문이 아닌 상품 상세 '바로구매' 단건 주문 여부
  bool get _isDirectSingleBuy =>
      !widget.args.fromCart && widget.args.items.length == 1;

  bool get _isWebViewVisible => _isOrderFormReady || _showWebViewInteractive;

  @override
  void initState() {
    super.initState();

    // 안전장치: 10초 후에도 화면이 블로킹되지 않도록 웹뷰 표시
    Timer(const Duration(milliseconds: 10000), () {
      if (mounted && !_isWebViewVisible) {
        setState(() => _showWebViewInteractive = true);
      }
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24OrderBridge',
        onMessageReceived: (msg) => _handleBridgeMessage(msg.message),
      )
      ..setOnJavaScriptAlertDialog((request) async {
        final msg = request.message;
        debugPrint('[Cafe24WebView Alert] $msg');

        if (msg.contains('단독구매')) {
          _finishWithFailure(
            '선택하신 상품 중 쇼핑몰 정책상 [단독구매 상품]이 포함되어 있습니다.\n해당 상품을 단독으로 선택하여 결제하시거나, 쇼핑몰 관리자에서 단독구매 설정을 변경해주세요.',
          );
          return;
        }

        if (msg.contains('품절')) {
          _finishWithFailure('선택하신 상품 중 현재 품절된 상품이 있습니다.');
          return;
        }

        if (!_isOrderFormReady &&
            !msg.contains('수 없습니다') &&
            !msg.contains('불가') &&
            (msg.contains('담겼습니다') ||
                msg.contains('비워') ||
                msg.contains('삭제'))) {
          return;
        }

        // 로그인 입력 오류 알림 등이 뜨면 사용자가 직접 확인·입력할 수 있도록 웹뷰 노출
        if (_isOnLoginPage && mounted && !_showWebViewInteractive) {
          setState(() => _showWebViewInteractive = true);
        }
        await _showWebAlert(msg);
      })
      ..setOnJavaScriptConfirmDialog((request) async {
        final msg = request.message;
        debugPrint('[Cafe24WebView Confirm] $msg');
        if (!_isOrderFormReady) {
          if (msg.contains('비우') || msg.contains('삭제')) {
            return true;
          }
          if (msg.contains('이동') ||
              msg.contains('확인하시겠습니까') ||
              msg.contains('동일') ||
              msg.contains('함께')) {
            return false;
          }
          return true;
        }
        return _showWebConfirm(msg);
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (url) {
            if (mounted) {
              final isOAuthLoginScreen =
                  url.contains('accounts.kakao.com/login') ||
                      url.contains('nid.naver.com/nidlogin');
              setState(() {
                _isLoading = true;
                if (isOAuthLoginScreen) {
                  _showWebViewInteractive = true;
                  _stepLabel = '간편로그인 인증을 진행해주세요.';
                }
              });
            }
            _injectPopupHelper();
          },
          onPageFinished: _handlePageFinished,
          onWebResourceError: (error) {
            debugPrint('[Cafe24WebView Error] ${error.description}');
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      );

    _startInitialOrderEntry();
  }

  void _startInitialOrderEntry() {
    if (_isDirectSingleBuy) {
      final firstNo = widget.args.items.first.product.id;
      _controller.loadRequest(
        Uri.parse('$_mallBase/product/detail.html?product_no=$firstNo'),
      );
    } else {
      _controller.loadRequest(
        Uri.parse('$_mallBase/order/basket.html'),
      );
    }
  }

  String _unescapeJsString(dynamic rawResult) {
    if (rawResult == null) return '';
    final rawStr = rawResult.toString();
    if (rawStr.startsWith('"') && rawStr.endsWith('"')) {
      try {
        final unescaped = jsonDecode(rawStr);
        if (unescaped is String) return unescaped;
      } catch (_) {}
    }
    return rawStr;
  }

  /// [단건 바로구매] 상품 상세페이지에서 사용자가 선택한 옵션 및 수량 설정 후 product_submit(1) 실행
  Future<void> _triggerSingleItemBuy() async {
    if (_singleBuyTriggered) return;
    _singleBuyTriggered = true;

    final targetQty = widget.args.items.first.quantity;
    final selectedOptions = widget.args.items.first.selectedOptions;

    await _controller.runJavaScript('''
      (function() {
        var attempts = 0;
        var maxAttempts = 20;
        var targetQty = $targetQty;
        var rawOptions = ${jsonEncode(selectedOptions)};
        var mainOptions = [];
        var addOptions = [];

        if (Array.isArray(rawOptions)) {
          for (var i = 0; i < rawOptions.length; i++) {
            var oStr = rawOptions[i];
            if (typeof oStr === 'string') {
              if (oStr.indexOf('[추가]') !== -1) {
                addOptions.push(oStr);
              } else {
                mainOptions.push(oStr);
              }
            }
          }
        }

        function clean(s) {
          if (!s) return '';
          s = s.replace(/\[추가\]/g, '').replace(/\[필수\]/g, '');
          if (s.indexOf(':') !== -1) {
            s = s.substring(s.indexOf(':') + 1);
          }
          s = s.replace(/\([^)]*원[^)]*\)/g, '');
          return s.replace(/\s+/g, '').replace(/[-_/]/g, '').trim().toLowerCase();
        }

        function matchOption(sel, targets) {
          if (!sel.options || sel.options.length <= 1) return false;
          for (var k = 0; k < sel.options.length; k++) {
            var opt = sel.options[k];
            if (opt.disabled || !opt.value || opt.value === '*' || opt.value === '**') continue;
            var optCore = clean(opt.text || '');
            if (!optCore) continue;
            for (var t = 0; t < targets.length; t++) {
              var targetCore = clean(targets[t]);
              if (!targetCore) continue;
              if (optCore === targetCore ||
                  (optCore.length >= 2 && targetCore.length >= 2 &&
                   (optCore.indexOf(targetCore) !== -1 || targetCore.indexOf(optCore) !== -1))) {
                sel.selectedIndex = k;
                sel.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
              }
            }
          }
          return false;
        }

        function selectValidOptions() {
          var allSelects = document.querySelectorAll('select[option_product_no], select.ProductOption0, select[name^="option"], select[name*="add_option"], select[id*="add_option"]');
          var mainSelects = [];
          var addSelects = [];

          allSelects.forEach(function(sel) {
            var isAdd = (sel.name && sel.name.indexOf('add_option') !== -1) ||
                        (sel.id && sel.id.indexOf('add_option') !== -1) ||
                        (sel.className && sel.className.indexOf('add_option') !== -1);
            if (isAdd) {
              addSelects.push(sel);
            } else {
              mainSelects.push(sel);
            }
          });

          // 1. 본품 옵션 선택
          if (mainOptions.length > 0) {
            mainSelects.forEach(function(sel) {
              matchOption(sel, mainOptions);
            });
          } else {
            // 본품 옵션 정보가 없는 경우: 첫 번째 유효 옵션 선택
            mainSelects.forEach(function(sel) {
              var currentVal = sel.value;
              if (!currentVal || currentVal === '*' || currentVal === '**') {
                for (var k = 0; k < sel.options.length; k++) {
                  var opt = sel.options[k];
                  if (!opt.disabled && opt.value && opt.value !== '*' && opt.value !== '**') {
                    sel.selectedIndex = k;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    break;
                  }
                }
              }
            });
          }

          // 2. 추가 상품 옵션 선택 (사용자가 추가옵션을 직접 선택했을 때만!)
          if (addOptions.length > 0 && addSelects.length > 0) {
            setTimeout(function() {
              addSelects.forEach(function(sel) {
                matchOption(sel, addOptions);
              });
            }, 100);
          }
        }

        function tryProcessSingleBuy() {
          attempts++;
          try {
            try {
              window.sIsIndividualBuy = 'F';
              var indiv = document.querySelectorAll('input[name="is_individual_buy"], #is_individual_buy');
              indiv.forEach(function(el) { el.value = 'F'; });
            } catch (_) {}

            // 1. 필수 옵션 자동 선택
            selectValidOptions();

            // 2. 옵션 박스 생성 대기 후 수량 반영 및 바로구매 클릭
            var delayMs = addOptions.length > 0 ? 320 : 180;
            setTimeout(function() {
              try {
                var qtyInputs = document.querySelectorAll('#quantity, input[name="quantity_opt[]"], input[name="quantity"], input.quantity_opt, #option_box1_quantity');
                qtyInputs.forEach(function(el) {
                  el.value = String(targetQty);
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                });

                var buyBtn = document.querySelector('[data-action*="product_submit(1"], [onclick*="product_submit(1"], #actionBuy, a.action-buy, #btnBuy, .btnBuy');
                if (buyBtn && ((buyBtn.getAttribute('onclick') || '').indexOf('product_submit(1') !== -1 || buyBtn.id === 'actionBuy')) {
                  buyBtn.click();
                  return;
                }
                if (typeof product_submit === 'function') {
                  product_submit(1, '/exec/front/order/basket/', buyBtn || document.getElementById('frmProduct') || document.body);
                  return;
                }
                if (buyBtn) {
                  buyBtn.click();
                  return;
                }
                if (attempts < maxAttempts) {
                  setTimeout(tryProcessSingleBuy, 220);
                }
              } catch (_) {
                if (attempts < maxAttempts) {
                  setTimeout(tryProcessSingleBuy, 220);
                }
              }
            }, delayMs);
          } catch (e) {
            if (attempts < maxAttempts) {
              setTimeout(tryProcessSingleBuy, 220);
            }
          }
        }

        tryProcessSingleBuy();
      })();
    ''');
  }

  /// [누락 장바구니 품목 보충] 비회원 또는 빈 웹 장바구니일 때 상세페이지에서 옵션 선택 후 장바구니 담기(product_submit(2))
  Future<void> _addSingleMissingItemOnDetailPage(CartItem item) async {
    final targetQty = item.quantity;
    final selectedOptions = item.selectedOptions;
    try {
      await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            var rawOptions = ${jsonEncode(selectedOptions)};
            var mainOptions = [];
            var addOptions = [];

            if (Array.isArray(rawOptions)) {
              for (var i = 0; i < rawOptions.length; i++) {
                var oStr = rawOptions[i];
                if (typeof oStr === 'string') {
                  if (oStr.indexOf('[추가]') !== -1) {
                    addOptions.push(oStr);
                  } else {
                    mainOptions.push(oStr);
                  }
                }
              }
            }

            function clean(s) {
              if (!s) return '';
              s = s.replace(/\[추가\]/g, '').replace(/\[필수\]/g, '');
              if (s.indexOf(':') !== -1) {
                s = s.substring(s.indexOf(':') + 1);
              }
              s = s.replace(/\([^)]*원[^)]*\)/g, '');
              return s.replace(/\s+/g, '').replace(/[-_/]/g, '').trim().toLowerCase();
            }

            function matchOption(sel, targets) {
              if (!sel.options || sel.options.length <= 1) return false;
              for (var k = 0; k < sel.options.length; k++) {
                var opt = sel.options[k];
                if (opt.disabled || !opt.value || opt.value === '*' || opt.value === '**') continue;
                var optCore = clean(opt.text || '');
                if (!optCore) continue;
                for (var t = 0; t < targets.length; t++) {
                  var targetCore = clean(targets[t]);
                  if (!targetCore) continue;
                  if (optCore === targetCore ||
                      (optCore.length >= 2 && targetCore.length >= 2 &&
                       (optCore.indexOf(targetCore) !== -1 || targetCore.indexOf(optCore) !== -1))) {
                    sel.selectedIndex = k;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    return true;
                  }
                }
              }
              return false;
            }

            var allSelects = document.querySelectorAll('select[option_product_no], select.ProductOption0, select[name^="option"], select[name*="add_option"], select[id*="add_option"]');
            var mainSelects = [];
            var addSelects = [];

            allSelects.forEach(function(sel) {
              var isAdd = (sel.name && sel.name.indexOf('add_option') !== -1) ||
                          (sel.id && sel.id.indexOf('add_option') !== -1) ||
                          (sel.className && sel.className.indexOf('add_option') !== -1);
              if (isAdd) {
                addSelects.push(sel);
              } else {
                mainSelects.push(sel);
              }
            });

            // 1. 본품 옵션 선택
            if (mainOptions.length > 0) {
              mainSelects.forEach(function(sel) {
                matchOption(sel, mainOptions);
              });
            } else {
              mainSelects.forEach(function(sel) {
                var currentVal = sel.value;
                if (!currentVal || currentVal === '*' || currentVal === '**') {
                  for (var k = 0; k < sel.options.length; k++) {
                    var opt = sel.options[k];
                    if (!opt.disabled && opt.value && opt.value !== '*' && opt.value !== '**') {
                      sel.selectedIndex = k;
                      sel.dispatchEvent(new Event('change', { bubbles: true }));
                      break;
                    }
                  }
                }
              });
            }

            // 2. 추가 상품 옵션 선택 (사용자가 추가옵션을 선택했을 때만)
            if (addOptions.length > 0 && addSelects.length > 0) {
              setTimeout(function() {
                addSelects.forEach(function(sel) {
                  matchOption(sel, addOptions);
                });
              }, 100);
            }

            var targetQty = $targetQty;
            var delayMs = addOptions.length > 0 ? 300 : 160;
            setTimeout(function() {
              try {
                var qtyInputs = document.querySelectorAll('#quantity, input[name="quantity_opt[]"], input[name="quantity"], input.quantity_opt, #option_box1_quantity');
                qtyInputs.forEach(function(el) {
                  el.value = String(targetQty);
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                });

                var cartBtn = document.querySelector('#actionCart, .actionCart, [data-action*="product_submit(2"], [onclick*="product_submit(2"]');
                if (cartBtn) {
                  cartBtn.click();
                } else if (typeof product_submit === 'function') {
                  product_submit(2, '/exec/front/order/basket/', document.body);
                }
              } catch (_) {}
            }, delayMs);
            return 'OK';
          } catch (e) {
            return 'ERR:' + e.message;
          }
        })()
      ''');
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted || _completed) return;

    _currentlyAddingMissingItem = null;
    if (_pendingMissingItems.isNotEmpty) {
      final nextItem = _pendingMissingItems.removeAt(0);
      _currentlyAddingMissingItem = nextItem;
      await _controller.loadRequest(
        Uri.parse('$_mallBase/product/detail.html?product_no=${nextItem.product.id}'),
      );
    } else {
      await _controller.loadRequest(Uri.parse('$_mallBase/order/basket.html'));
    }
  }

  /// [장바구니/다건 주문] basket.html의 aBasketProductData 및 DOM 체크박스를 점검하고 주문서로 제출
  Future<void> _handleBasketPageForOrder() async {
    if (_currentlyAddingMissingItem != null) return;

    // 원격 웹뷰 장바구니에 주문 대상 상품이 실제로 존재하는지 점검 (비어있는 경우 안전하게 자동 적재)
    if (!_basketInspected) {
      _basketInspected = true;
      try {
        final dynamic raw = await _controller.runJavaScriptReturningResult('''
          (function() {
            try {
              var pNos = [];
              if (typeof aBasketProductData !== 'undefined' && Array.isArray(aBasketProductData)) {
                for (var i = 0; i < aBasketProductData.length; i++) {
                  var p = String(aBasketProductData[i].product_no || aBasketProductData[i].iProductNo || '');
                  if (p && pNos.indexOf(p) === -1) pNos.push(p);
                }
              }
              // DOM 폴백: 링크 및 행에서 상품번호 추출
              var links = document.querySelectorAll('a[href*="product_no="]');
              links.forEach(function(a) {
                var m = a.getAttribute('href').match(/product_no=([0-9]+)/);
                if (m && pNos.indexOf(m[1]) === -1) pNos.push(m[1]);
              });
              return JSON.stringify(pNos);
            } catch (e) {
              return '[]';
            }
          })()
        ''');

        final decoded = jsonDecode(_unescapeJsString(raw));
        final existingProductNos = <String>{
          if (decoded is List) ...decoded.map((e) => e.toString()),
        };

        final missing = widget.args.items.where((it) {
          if (int.tryParse(it.product.id) == null) return false;
          return !existingProductNos.contains(it.product.id);
        }).toList();

        if (missing.isNotEmpty) {
          _pendingMissingItems
            ..clear()
            ..addAll(missing);
          final firstMissing = _pendingMissingItems.removeAt(0);
          _currentlyAddingMissingItem = firstMissing;
          await _controller.loadRequest(
            Uri.parse(
              '$_mallBase/product/detail.html?product_no=${firstMissing.product.id}',
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('[Cafe24WebView] 장바구니 품목 점검 예외: $e');
      }
    }

    if (_basketOrderSubmitted) return;
    _basketOrderSubmitted = true;

    final selectedProductNos =
        widget.args.items.map((e) => e.product.id).toList();
    final selectedBasketNos = widget.args.items
        .map((e) => e.basketProductNo)
        .whereType<int>()
        .toList();

    // 1차 주문서 제출 스크립트 실행
    Future<void> triggerSubmit() async {
      try {
        final dynamic evalResult =
            await _controller.runJavaScriptReturningResult('''
          (function() {
            try {
              window.alert = function(msg) {};
              window.confirm = function() { return true; };

              var selProductNos = ${jsonEncode(selectedProductNos)};
              var selBasketNos = ${jsonEncode(selectedBasketNos)};

              // 1. 체크박스 요소들을 정확하게 탐색 및 체크 설정
              var itemCheckboxes = [];
              var allInputs = document.querySelectorAll('input[type="checkbox"]');

              allInputs.forEach(function(chk) {
                var id = (chk.id || '').toLowerCase();
                var name = (chk.name || '').toLowerCase();
                // 전체 선택 체크박스(#allCheck 등) 제외
                if (id.indexOf('all') !== -1 || name.indexOf('all') !== -1) return;

                // 장바구니 상품 체크박스 조건
                if (id.indexOf('basket_chk') !== -1 ||
                    name.indexOf('basket_product_no') !== -1 ||
                    chk.className.indexOf('basket') !== -1 ||
                    (chk.value && !isNaN(Number(chk.value)))) {
                  itemCheckboxes.push(chk);
                }
              });

              // 만약 특화 체크박스가 없으면 전체 체크박스 중 all 제외 항목 사용
              if (itemCheckboxes.length === 0) {
                allInputs.forEach(function(chk) {
                  var id = (chk.id || '').toLowerCase();
                  var name = (chk.name || '').toLowerCase();
                  if (id.indexOf('all') === -1 && name.indexOf('all') === -1) {
                    itemCheckboxes.push(chk);
                  }
                });
              }

              var checkedBoxes = [];
              var totalBoxes = itemCheckboxes.length;

              itemCheckboxes.forEach(function(chk, idx) {
                var bNo = Number(chk.value);
                var pNo = '';
                var row = chk.closest('tr') || chk.closest('li') || chk.closest('.xans-record-') || chk.parentElement;
                if (row) {
                  var pLink = row.querySelector('a[href*="product_no="]');
                  if (pLink) {
                    var m = pLink.getAttribute('href').match(/product_no=([0-9]+)/);
                    if (m) pNo = m[1];
                  }
                }

                var shouldCheck = false;
                if (selBasketNos.length > 0 && bNo > 0 && selBasketNos.indexOf(bNo) !== -1) {
                  shouldCheck = true;
                } else if (pNo && selProductNos.indexOf(pNo) !== -1) {
                  shouldCheck = true;
                } else if (selBasketNos.length === 0 && selProductNos.length === 0) {
                  shouldCheck = true;
                }

                // ID 기반 aBasketProductData 순번 매핑 지원
                if (!shouldCheck && typeof aBasketProductData !== 'undefined' && Array.isArray(aBasketProductData)) {
                  var it = aBasketProductData[idx];
                  if (it) {
                    var itBno = Number(it.basket_prd_no || it.basket_product_no || 0);
                    var itPno = String(it.product_no || it.iProductNo || '');
                    if ((selBasketNos.length > 0 && itBno > 0 && selBasketNos.indexOf(itBno) !== -1) ||
                        (itPno && selProductNos.indexOf(itPno) !== -1)) {
                      shouldCheck = true;
                    }
                  }
                }

                chk.checked = shouldCheck;
                chk.dispatchEvent(new Event('change', { bubbles: true }));
                if (shouldCheck) {
                  checkedBoxes.push(chk);
                }
              });

              // 만약 매칭된 체크박스가 없거나 선택 개수가 0개면 안전하게 모든 장바구니 상품 체크
              if (checkedBoxes.length === 0 && itemCheckboxes.length > 0) {
                itemCheckboxes.forEach(function(chk) {
                  chk.checked = true;
                  chk.dispatchEvent(new Event('change', { bubbles: true }));
                  checkedBoxes.push(chk);
                });
              }

              // 2. 주문 버튼 탐색 및 클릭 트리거 (displaynone 제외한 실제 화면 버튼 우선)
              function isVisible(el) {
                if (!el) return false;
                var style = window.getComputedStyle ? window.getComputedStyle(el) : null;
                if (style && (style.display === 'none' || style.visibility === 'hidden')) return false;
                if (el.closest('.displaynone') || el.closest('[style*="display: none"]')) return false;
                return true;
              }

              var allBtns = Array.from(document.querySelectorAll('a.btnSubmit, [onclick*="Basket.orderAll"], a[link-order*="all_buy"], #btnOrderAll'));
              var selectBtns = Array.from(document.querySelectorAll('a.btnNormal, [onclick*="Basket.orderSelectBasket"], #btnOrderSelect'));

              var allOrderBtn = allBtns.find(isVisible) || allBtns[0];
              var selectOrderBtn = selectBtns.find(isVisible) || selectBtns[0];

              var isAllBuy = (checkedBoxes.length >= totalBoxes) || (totalBoxes === 0);

              if (isAllBuy) {
                if (allOrderBtn) {
                  allOrderBtn.click();
                }
                if (typeof Basket !== 'undefined' && typeof Basket.orderAll === 'function') {
                  Basket.orderAll(allOrderBtn || document.body);
                }
                return 'CLICKED_ALL';
              } else {
                if (selectOrderBtn && checkedBoxes.length > 0) {
                  selectOrderBtn.click();
                }
                if (typeof Basket !== 'undefined' && typeof Basket.orderSelectBasket === 'function' && checkedBoxes.length > 0) {
                  Basket.orderSelectBasket(selectOrderBtn || document.body);
                }
                return 'CLICKED_SELECT';
              }

              // 최후의 수단: 공식 전체 주문 링크로 직접 이동
              window.location.href = '/order/orderform.html?basket_type=all_buy';
              return 'REDIRECT_ALL_BUY';
            } catch (e) {
              return 'ERR: ' + e.message;
            }
          })();
        ''');
        debugPrint('[Cafe24WebView] 장바구니 주문 제출 evalResult: $evalResult');
      } catch (_) {}
    }

    await triggerSubmit();

    // 0.6초 후 2차 재시도 (비동기 스킨 대응)
    Future.delayed(const Duration(milliseconds: 600), () async {
      if (_isOrderFormReady || _completed || !mounted) return;
      await triggerSubmit();
    });

    // 안전 타임아웃: 2.8초 후에도 주문서로 이동하지 않으면 공식 주문서 파라미터(?basket_type=all_buy)로 직접 요청
    Future.delayed(const Duration(milliseconds: 2800), () async {
      if (_isOrderFormReady || _completed || !mounted) return;
      debugPrint('[Cafe24WebView] 장바구니에서 주문서로 자동 이동 지연 -> 직접 orderform.html 로드 및 화면 활성화');
      setState(() {
        _showWebViewInteractive = true;
        _stepLabel = '주문서로 이동하고 있습니다...';
      });
      try {
        await _controller.loadRequest(
          Uri.parse('$_mallBase/order/orderform.html?basket_type=all_buy'),
        );
      } catch (_) {}
    });
  }

  /// PG 결제 팝업창(window.open)이 새 창으로 유실되지 않고 현재 웹뷰에서 열리도록 스크립트 오버라이드
  Future<void> _injectPopupHelper() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (!window._popupInjected) {
            window._popupInjected = true;
            window.open = function(url) {
              if (url) { window.location.href = url; }
              return window;
            };
          }
        })();
      ''');
    } catch (_) {}
  }

  /// 주문서 화면에서 헤더, 쇼핑몰 로고, 메뉴바, 장바구니, 푸터 등 주문과 무관한 네비게이션 UI를 숨기고 외부 이동 링크를 무력화
  Future<void> _injectOrderOnlyStyles() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          try {
            var styleId = 'shopmall-order-clean-style';
            if (!document.getElementById(styleId)) {
              var style = document.createElement('style');
              style.id = styleId;
              style.innerHTML = `
                /* 상단 로고, 햄버거 메뉴, GNB, 검색, 장바구니, 퀵메뉴, 푸터 숨김 */
                header, #header, .header, #top, .top,
                #navigation, nav, .navigation, #menu, .menu,
                #quick_menu, .quickMenu, #btn_top, .btnTop,
                footer, #footer, .footer,
                .xans-layout-orderbasketcount,
                .xans-layout-statelogon,
                .xans-layout-statelogoff,
                #aside, .aside, #sidebar,
                header a, nav a, footer a {
                  display: none !important;
                }
                /* 주문상품 목록 내 썸네일 이미지 및 상품명은 정상 표시하고 클릭 이동만 비활성화 */
                .ec-base-prdInfo a,
                .orderList a,
                [class*="order"] a[href*="/product/"],
                .thumb a {
                  display: inline-block !important;
                  pointer-events: none !important;
                  cursor: default !important;
                  color: inherit !important;
                  text-decoration: none !important;
                }
                .ec-base-prdInfo img,
                .orderList img,
                .thumb img,
                [class*="order"] img {
                  display: block !important;
                  visibility: visible !important;
                  opacity: 1 !important;
                }
                body {
                  padding-top: 0 !important;
                  margin-top: 0 !important;
                }
              `;
              document.head.appendChild(style);
            }

            // 혹시라도 남아있는 외부 이동 a 링크 클릭 차단
            if (!window._orderClickBlockerInjected) {
              window._orderClickBlockerInjected = true;
              document.addEventListener('click', function(e) {
                var a = e.target.closest('a');
                if (a && a.href) {
                  var h = a.getAttribute('href') || '';
                  if (h === '/' ||
                      h.indexOf('index.html') !== -1 ||
                      h.indexOf('/product/') !== -1 ||
                      h.indexOf('/order/basket') !== -1 ||
                      h.indexOf('/myshop/') !== -1 ||
                      h.indexOf('/board/') !== -1) {
                    e.preventDefault();
                    e.stopPropagation();
                  }
                }
              }, true);
            }
          } catch (_) {}
        })();
      ''');
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 네비게이션 처리 (OAuth 로그인 스킴 분리 + PG 결제 앱 + 완료/실패 페이지 감지)
  // ──────────────────────────────────────────────────────────────────────────

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final url = request.url;
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';

    // 1. 결제 완료 감지 (order_result.html)
    if (url.contains('/order/order_result')) {
      final isFail = (uri?.queryParameters['is_fail'] == 'T') ||
          (uri?.queryParameters['result'] == 'fail') ||
          url.contains('is_fail=T') ||
          url.contains('result=fail');

      if (isFail) {
        final failMsg = uri?.queryParameters['res_msg'] ??
            uri?.queryParameters['msg'] ??
            uri?.queryParameters['error_msg'] ??
            '결제가 승인되지 않았거나 취소되었습니다.';
        _finishWithFailure(failMsg);
        return NavigationDecision.prevent;
      }

      final orderId = uri?.queryParameters['order_id'];
      if (orderId != null && orderId.isNotEmpty) {
        _finishWithSuccess(orderId);
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }

    // 2. 결제 명시적 실패 감지
    if (url.contains('/order/fail') ||
        url.contains('/order/order_fail') ||
        (url.contains('result=fail') && !url.contains('/member/login'))) {
      final failMsg = uri?.queryParameters['res_msg'] ??
          uri?.queryParameters['msg'] ??
          uri?.queryParameters['error_msg'] ??
          '결제 처리 중 오류가 발생했습니다.';
      _finishWithFailure(failMsg);
      return NavigationDecision.prevent;
    }

    // 3. 결제 취소 감지
    if (url.contains('result=cancel') ||
        url.contains('code=cancel') ||
        url.contains('cancel=true')) {
      _finishWithCancel('결제가 사용자에 의해 취소되었습니다.');
      return NavigationDecision.prevent;
    }

    // 4. 일반 웹 페이지 탐색
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'javascript' ||
        scheme == 'blob') {
      // [주문서 이탈 방지] 주문서 진입 이후(_isOrderFormReady)에는 쇼핑몰 내 타 페이지로의 이동을 차단
      if (_isOrderFormReady) {
        final host = uri?.host.toLowerCase() ?? '';
        final path = uri?.path.toLowerCase() ?? '';

        // 쇼핑몰 내부 도메인 접근인 경우
        if (host.contains('suzicnl.com')) {
          final isAllowedOrderUrl = path.contains('/order/orderform') ||
              path.contains('/order/order_result') ||
              path.contains('/order/order_success') ||
              path.contains('/order/result') ||
              path.contains('/order/complete') ||
              path.contains('/myshop/order/detail') ||
              path.contains('/order/fail') ||
              path.contains('/order/order_fail') ||
              path.contains('/exec/front/order/') ||
              path.contains('/exec/front/') ||
              uri?.queryParameters.containsKey('order_id') == true ||
              uri?.queryParameters.containsKey('orderId') == true;

          if (!isAllowedOrderUrl) {
            debugPrint('[Cafe24WebView] 주문서 작성 중 타 화면 이동 차단: $url');
            if (mounted) {
              _showSnack('주문 및 결제 진행 중에는 다른 페이지로 이동할 수 없습니다.');
            }
            return NavigationDecision.prevent;
          }
        }
      }

      return NavigationDecision.navigate;
    }

    // 5. 주문서 도달 전(로그인/OAuth 인증 단계)에는 카카오톡·네이버 외부 앱 스킴을 차단하여
    // 웹뷰 내부 OAuth 쿠키 세션으로 안전하게 로그인되도록 보장
    if (!_isOrderFormReady) {
      final isOAuthAppScheme = scheme == 'kakaokompassauth' ||
          scheme == 'kakaolink' ||
          scheme == 'nidlogin' ||
          scheme == 'naversearchapp' ||
          scheme == 'naversearchthirdlogin' ||
          (scheme == 'kakaotalk' && !url.toLowerCase().contains('kakaopay'));
      if (isOAuthAppScheme) {
        debugPrint('[Cafe24WebView] OAuth 웹 인증 유지를 위해 앱 스킴 차단: $url');
        return NavigationDecision.prevent;
      }
    }

    // 6. 주문서 단계의 PG사 결제 앱 호출 (외부 스킴 및 intent://)
    await _launchExternalPaymentApp(url);
    return NavigationDecision.prevent;
  }

  /// 카드사 앱카드, 간편결제(카카오페이/토스/ISP 등), Android intent:// 완벽 대응 런처
  Future<void> _launchExternalPaymentApp(String rawUrl) async {
    try {
      // 1) 구글 플레이 마켓 직접 호출
      if (rawUrl.startsWith('market://')) {
        final uri = Uri.parse(rawUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
        final pkgMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(rawUrl);
        if (pkgMatch != null) {
          final webPlayStore = Uri.parse(
            'https://play.google.com/store/apps/details?id=${pkgMatch.group(1)}',
          );
          await launchUrl(webPlayStore, mode: LaunchMode.externalApplication);
        }
        return;
      }

      // 2) Android intent:// URL 파싱 및 단계별 폴백
      if (rawUrl.startsWith('intent://') || rawUrl.startsWith('intent:')) {
        final fallbackMatch =
            RegExp(r';S\.browser_fallback_url=([^;]+)').firstMatch(rawUrl);
        final packageMatch = RegExp(r';package=([^;]+)').firstMatch(rawUrl);
        final schemeMatch = RegExp(r';scheme=([^;]+)').firstMatch(rawUrl);

        Uri? appSchemeUri;

        if (schemeMatch != null) {
          final scheme = schemeMatch.group(1)!;
          final body = rawUrl
              .replaceFirst(RegExp(r'^intent:(//)?'), '')
              .split('#Intent')
              .first;
          appSchemeUri = Uri.tryParse('$scheme://$body');
        } else {
          final customSchemeMatch =
              RegExp(r'^intent:([a-zA-Z0-9_\.\-]+)://(.*)#Intent')
                  .firstMatch(rawUrl);
          if (customSchemeMatch != null) {
            final scheme = customSchemeMatch.group(1)!;
            final rest = customSchemeMatch.group(2)!;
            appSchemeUri = Uri.tryParse('$scheme://$rest');
          }
        }

        // [1단계] 앱 커스텀 스킴 직접 실행
        if (appSchemeUri != null) {
          try {
            final launched = await launchUrl(
              appSchemeUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return;
          } catch (_) {}
        }

        // [2단계] PG사가 제공한 웹 fallback URL 실행 (웹뷰 내부 로드)
        if (fallbackMatch != null) {
          final fallbackUrl = Uri.decodeComponent(fallbackMatch.group(1)!);
          await _controller.loadRequest(Uri.parse(fallbackUrl));
          return;
        }

        // [3단계] 앱 패키지가 있는 경우 플레이스토어로 연결
        if (packageMatch != null) {
          final pkg = packageMatch.group(1)!;
          final marketUri = Uri.parse('market://details?id=$pkg');
          try {
            final launched = await launchUrl(
              marketUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return;
          } catch (_) {}

          final webPlayStore = Uri.parse(
            'https://play.google.com/store/apps/details?id=$pkg',
          );
          await launchUrl(webPlayStore, mode: LaunchMode.externalApplication);
          return;
        }

        if (mounted) {
          _showSnack('결제 앱을 실행할 수 없습니다. 앱 설치 여부를 확인해주세요.');
        }
        return;
      }

      // 3) 일반 커스텀 URL Scheme (kakaopay://, ispmobile://, supertoss:// 등)
      final uri = Uri.parse(rawUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          _showSnack('결제 앱이 설치되어 있지 않거나 실행할 수 없습니다.');
        }
      }
    } catch (_) {
      if (mounted) {
        _showSnack('결제 앱 연동 중 오류가 발생했습니다. 앱 설치 여부를 확인해주세요.');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 페이지 단계별 처리 (결제 완료, 주문서, 로그인 복구, 상품/장바구니 주문 제출)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handlePageFinished(String url) async {
    if (!mounted) return;
    setState(() => _isLoading = false);

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path ?? url;

    // 0. 외부 간편로그인(카카오/네이버) 입력 화면인 경우 즉시 웹뷰 표시
    if (host.contains('kakao.com') || host.contains('naver.com')) {
      setState(() {
        _isOnLoginPage = true;
        _showWebViewInteractive = true;
        _stepLabel = '간편로그인 인증을 완료하시면 주문서로 자동 이동합니다.';
        _notice = null;
      });
      return;
    }

    // 1. 결제 완료 페이지 감지 (다양한 스킨 및 리다이렉트 대응)
    final isResultUrl = path.contains('/order/order_result') ||
        path.contains('/order/order_success') ||
        path.contains('/order/result') ||
        path.contains('/order/complete') ||
        (path.contains('/myshop/order/detail') && uri?.queryParameters.containsKey('order_id') == true) ||
        (uri?.queryParameters.containsKey('order_id') == true &&
            !path.contains('/order/orderform') &&
            !path.contains('/order/basket'));

    if (isResultUrl) {
      final isFail = url.contains('is_fail=T') ||
          url.contains('result=fail') ||
          url.contains('code=fail') ||
          url.contains('cancel=true');
      if (isFail) {
        _finishWithFailure('결제가 취소되었거나 정상 승인되지 않았습니다.');
        return;
      }

      setState(() => _stepLabel = '결제가 완료되었습니다. 주문을 완료하고 있습니다...');
      final orderId = uri?.queryParameters['order_id'] ??
          uri?.queryParameters['orderId'] ??
          uri?.queryParameters['ord_no'];
      if (orderId != null && orderId.isNotEmpty) {
        _finishWithSuccess(orderId);
      } else {
        await _extractOrderIdFromResultPage();
      }
      return;
    }

    // 2. 결제 실패 / 취소 페이지
    if (path.contains('/order/fail') ||
        path.contains('/order/order_fail') ||
        (url.contains('result=fail') && !path.contains('/member/login'))) {
      _finishWithFailure('결제가 승인되지 않았거나 취소되었습니다.');
      return;
    }

    // 3. Cafe24 로그인 페이지 진입 시 (무한 리다이렉트 루프 없이 회원 재인증 또는 비회원 구매 처리)
    if (path.contains('/member/login')) {
      setState(() {
        _isOnLoginPage = true;
        _stepLabel = '쇼핑몰 회원 인증 확인 중...';
        _notice = '로그인이 완료되면 주문서로 자동 이동합니다.';
      });
      await _handleLoginPageArrival();
      return;
    }

    // suzicnl.com 내부 일반 페이지 복귀 시 로그인 세션 복구 상태 반영
    if (_autoLoginAttempted &&
        host.contains('suzicnl.com') &&
        !path.contains('/Api/Member/Oauth2ClientCallback') &&
        !path.contains('/exec/front/Member/login')) {
      ref.read(cafe24WebCartServiceProvider).resetSilentLoginCooldown();
      ref.read(webSessionDisconnectedProvider.notifier).setDisconnected(false);
    }

    setState(() => _isOnLoginPage = false);

    // 4. Cafe24 주문서 작성 페이지: 배송지/결제정보 사전 채움
    if (path.contains('/order/orderform')) {
      setState(() {
        _isOrderFormReady = true;
        _showWebViewInteractive = true;
        _stepLabel = '배송지와 결제정보를 확인하고 결제를 진행해주세요.';
        _notice = null;
      });
      // 결제 외 불필요한 상·하단 네비게이션(로고, 메뉴, 장바구니 등) 숨김 스타일 즉시 주입
      _injectOrderOnlyStyles();

      if (!_orderFormPrefilled) {
        _orderFormPrefilled = true;
        await _prefillOrderForm();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            _injectOrderOnlyStyles();
            _prefillOrderForm();
          }
        });
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _injectOrderOnlyStyles();
            _prefillOrderForm();
          }
        });
      }
      return;
    }

    // 5. 상품 상세 페이지(/product/detail.html) 도달 시
    if (path.contains('/product/')) {
      if (!_isOrderFormReady) {
        if (_currentlyAddingMissingItem != null) {
          await _addSingleMissingItemOnDetailPage(_currentlyAddingMissingItem!);
        } else if (_isDirectSingleBuy) {
          await _triggerSingleItemBuy();
        }
      }
      return;
    }

    // 6. 장바구니 페이지(/order/basket.html) 도달 시
    if (path.contains('/order/basket')) {
      if (!_isOrderFormReady && !_isDirectSingleBuy) {
        setState(() {
          _showWebViewInteractive = false;
          _stepLabel = '선택하신 주문 상품을 확인하고 있습니다...';
        });
        await _handleBasketPageForOrder();
      }
      return;
    }

    // 7. 로그인 완료 후 메인(/index.html)이나 마이쇼핑(/myshop/)으로 리다이렉트된 경우 주문 재개
    if (!_isOrderFormReady &&
        (path == '/' ||
            path.contains('/index.html') ||
            path.contains('/myshop/'))) {
      setState(() {
        _showWebViewInteractive = false;
        _stepLabel = '인증이 완료되어 주문서로 연결하고 있습니다...';
        _notice = null;
      });
      _singleBuyTriggered = false;
      _basketInspected = false;
      _basketOrderSubmitted = false;
      _startInitialOrderEntry();
    }
  }

  /// /member/login.html 도달 시 계정 유형별 자동 복구 또는 대화형 로그인 화면 표시
  Future<void> _handleLoginPageArrival() async {
    final user = ref.read(authProvider);
    final isGuestUser =
        user == null || user.id.isEmpty || user.id == 'suzicnl1';

    // 비회원 주문이거나 사용자가 상단 '비회원 바로주문'을 명시적으로 선택한 경우
    if (isGuestUser || _forceGuestOrder) {
      if (!_guestProceedAttempted) {
        _guestProceedAttempted = true;
        final clicked = await _tryClickGenuineGuestOrderButton();
        if (clicked) return;
      }
      if (mounted) {
        setState(() {
          _showWebViewInteractive = true;
          _stepLabel = '로그인 또는 비회원 주문을 선택해주세요.';
        });
      }
      return;
    }

    // 이미 자동 로그인을 1회 시도했는데도 다시 로그인 페이지에 도달한 경우 -> 즉시 화면 노출하여 수동 진행 허용
    if (_autoLoginAttempted) {
      if (mounted) {
        setState(() {
          _showWebViewInteractive = true;
          _stepLabel = '쇼핑몰 로그인을 완료하시면 주문서로 자동 이동합니다.';
        });
      }
      return;
    }

    _autoLoginAttempted = true;

    // 1.8초 내에 리다이렉트되지 않으면 흰색 로딩 화면 뒤에 가리지 않고 로그인 화면 노출
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !_isOrderFormReady && _isOnLoginPage) {
        setState(() => _showWebViewInteractive = true);
      }
    });

    // (A) 카카오싱크 회원 (@k)
    if (user.id.endsWith('@k')) {
      await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            if (typeof MemberAction !== 'undefined' && typeof MemberAction.kakaosyncLogin === 'function') {
              MemberAction.kakaosyncLogin('$_kakaoJsKey');
              return 'KAKAO_SYNC';
            }
            if (typeof MemberAction !== 'undefined' && typeof MemberAction.snsLogin === 'function') {
              MemberAction.snsLogin('kakao', '%2Forder%2Forderform.html');
              return 'KAKAO_SNS';
            }
            var btn = document.querySelector('[onclick*="kakaosyncLogin"], .btnKakao, a.kakao');
            if (btn) { btn.click(); return 'KAKAO_BTN'; }
            return 'NONE';
          } catch (e) {
            return 'ERR';
          }
        })()
      ''');
      return;
    }

    // (B) 네이버 간편로그인 회원 (@n)
    if (user.id.endsWith('@n')) {
      await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            if (typeof MemberAction !== 'undefined' && typeof MemberAction.snsLogin === 'function') {
              MemberAction.snsLogin('naver', '%2Forder%2Forderform.html');
              return 'NAVER_SNS';
            }
            var btn = document.querySelector('[onclick*="snsLogin(\\'naver\\'"], .btnNaver, a.naver');
            if (btn) { btn.click(); return 'NAVER_BTN'; }
            return 'NONE';
          } catch (e) {
            return 'ERR';
          }
        })()
      ''');
      return;
    }

    // (C) 일반 ID/PW 회원
    final pw = await ref.read(authProvider.notifier).getMemberPassword(user.id);
    final hasPw = pw != null && pw.isNotEmpty;

    await _controller.runJavaScriptReturningResult('''
      (function() {
        try {
          var loginDivs = document.querySelectorAll('.login, .xans-member-login');
          loginDivs.forEach(function(d) {
            d.classList.remove('displaynone');
            d.style.display = 'block';
          });

          var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
          var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
          var keepEl = document.getElementById('use_login_keeping') || document.querySelector('input[name="use_login_keeping"]');

          if (idEl) {
            idEl.value = ${jsonEncode(user.id)};
            idEl.dispatchEvent(new Event('input', { bubbles: true }));
          }

          if (keepEl && !keepEl.checked) {
            keepEl.checked = true;
            keepEl.dispatchEvent(new Event('change', { bubbles: true }));
          }

          if (${hasPw ? 'true' : 'false'} && pwEl) {
            pwEl.value = ${jsonEncode(pw ?? '')};
            pwEl.dispatchEvent(new Event('input', { bubbles: true }));

            setTimeout(function() {
              var form = idEl ? idEl.closest('form') : document.querySelector('form[id^="member_form"]');
              if (typeof MemberAction !== 'undefined' && typeof MemberAction.login === 'function' && form) {
                MemberAction.login(form.id || 'member_form_');
              } else {
                var btn = document.querySelector('[onclick*="MemberAction.login"], .btnSubmit, .btnLogin');
                if (btn) btn.click();
              }
            }, 200);
            return 'SUBMITTED';
          }
          return 'PREFILLED_ONLY';
        } catch (e) {
          return 'ERR';
        }
      })()
    ''');

    if (!hasPw && mounted) {
      setState(() {
        _showWebViewInteractive = true;
        _stepLabel = '비밀번호를 입력하여 로그인하시면 주문서로 이동합니다.';
      });
    }
  }

  /// 실제 비회원 구매 버튼이 존재하는 경우에만 1회 클릭 (무조건적인 orderform.html 리다이렉트 루프 원천 차단)
  Future<bool> _tryClickGenuineGuestOrderButton() async {
    try {
      final dynamic res = await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            // '비회원 주문조회'가 아닌 실제 '비회원 구매' 버튼 탐색
            var all = document.querySelectorAll('a, button, input[type="button"], span');
            for (var i = 0; i < all.length; i++) {
              var el = all[i];
              var text = (el.innerText || el.textContent || el.value || '').trim();
              var oc = (el.getAttribute('onclick') || '');
              if (text.indexOf('조회') !== -1) continue;
              if (text === '비회원 구매' || text === '비회원구매' || text === '비회원 주문' || text === '비회원주문' ||
                  oc.indexOf('noMemberOrder') !== -1 || oc.indexOf('order_check') !== -1) {
                var clickable = el.closest('a, button') || el;
                clickable.click();
                return 'CLICKED';
              }
            }
            return 'NOT_FOUND';
          } catch (e) {
            return 'ERR';
          }
        })()
      ''');
      return _unescapeJsString(res) == 'CLICKED';
    } catch (_) {
      return false;
    }
  }

  /// 상단 바에서 사용자가 명시적으로 '비회원 바로주문 >'을 눌렀을 때 처리
  Future<void> _onTapForceGuestOrder() async {
    setState(() {
      _forceGuestOrder = true;
      _guestProceedAttempted = true;
      _isOnLoginPage = false;
      _showWebViewInteractive = false;
      _stepLabel = '비회원 주문서를 준비하고 있습니다...';
      _notice = null;
    });

    final clicked = await _tryClickGenuineGuestOrderButton();
    if (!clicked && mounted) {
      // 비회원 장바구니에 아직 상품이 담기지 않은 상태이므로 상품을 먼저 적재한 뒤 비회원 주문 진입
      _guestProceedAttempted = false;
      _singleBuyTriggered = false;
      _basketInspected = false;
      _basketOrderSubmitted = false;
      _startInitialOrderEntry();
    }
  }

  /// Cafe24 주문서에 앱에서 입력한 배송지/결제수단/약관 정보 자동 채움
  Future<void> _prefillOrderForm() async {
    final p = widget.prefill;
    final user = ref.read(authProvider);

    final digits = p.recipientPhone.replaceAll(RegExp(r'[^0-9]'), '');
    String m1 = '', m2 = '', m3 = '';
    if (digits.length >= 10) {
      m1 = digits.substring(0, 3);
      m2 = digits.length == 10
          ? digits.substring(3, 6)
          : digits.substring(3, 7);
      m3 = digits.length == 10 ? digits.substring(6) : digits.substring(7);
    }

    final email = (user?.email != null &&
            user!.email.isNotEmpty &&
            !user.email.endsWith('@suzicnl.com'))
        ? user.email
        : (digits.isNotEmpty ? '$digits@suzicnl.com' : 'order@suzicnl.com');
    final emailParts = email.split('@');
    final emailId = emailParts[0];
    final emailDomain = emailParts.length > 1 ? emailParts[1] : 'suzicnl.com';

    await _controller.runJavaScript('''
      (function() {
        function setVal(selectors, val) {
          if (!val) return;
          for (var i = 0; i < selectors.length; i++) {
            var el = document.querySelector(selectors[i]);
            if (el) {
              el.value = val;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }
          }
        }

        try {
          var newAddr = document.querySelector('#sameaddr1, input[name="sameaddr"][value="F"]');
          if (newAddr && !newAddr.checked) newAddr.click();

          setTimeout(function() {
            setVal(['#rname', 'input[name="rname"]'], ${jsonEncode(p.recipientName)});
            setVal(['#rzipcode1', 'input[name="rzipcode1"]', 'input[name="rpostcode"]'], ${jsonEncode(p.zipCode)});
            setVal(['#raddr1', 'input[name="raddr1"]'], ${jsonEncode(p.address1)});
            setVal(['#raddr2', 'input[name="raddr2"]'], ${jsonEncode(p.address2)});
            setVal(['#rphone2_1', 'select[name="rphone2_1"]', 'input[name="rphone2_1"]'], ${jsonEncode(m1)});
            setVal(['#rphone2_2', 'input[name="rphone2_2"]'], ${jsonEncode(m2)});
            setVal(['#rphone2_3', 'input[name="rphone2_3"]'], ${jsonEncode(m3)});
            setVal(['#omessage', 'textarea[name="omessage"]'], ${jsonEncode(p.deliveryMemo)});

            setVal(['#oname', 'input[name="oname"]'], ${jsonEncode(p.recipientName)});
            setVal(['#ophone2_1', 'select[name="ophone2_1"]', 'input[name="ophone2_1"]'], ${jsonEncode(m1)});
            setVal(['#ophone2_2', 'input[name="ophone2_2"]'], ${jsonEncode(m2)});
            setVal(['#ophone2_3', 'input[name="ophone2_3"]'], ${jsonEncode(m3)});
            setVal(['#oemail', 'input[name="oemail"]', '#email', 'input[name="email"]'], ${jsonEncode(email)});
            setVal(['#oemail1', 'input[name="oemail1"]'], ${jsonEncode(emailId)});
            setVal(['#oemail2', 'input[name="oemail2"]'], ${jsonEncode(emailDomain)});

            setVal(['#order_password', 'input[name="order_password"]'], '1234a!');
            setVal(['#order_password_confirm', 'input[name="order_password_confirm"]'], '1234a!');

            var method = ${jsonEncode(p.paymentMethod)};
            var targetSelectors = [];
            if (method.indexOf('무통장') !== -1) {
              targetSelectors = [
                'input[name="addr_paymethod"][value="cash"]',
                'input[name="paymethod"][value="cash"]',
                '#addr_paymethod0',
                'input[value="cash"]'
              ];
            } else if (method.indexOf('카드') !== -1) {
              targetSelectors = [
                'input[name="addr_paymethod"][value="card"]',
                'input[name="paymethod"][value="card"]',
                '#addr_paymethod1',
                'input[value="card"]'
              ];
            } else if (method.indexOf('카카오') !== -1) {
              targetSelectors = [
                'input[name="addr_paymethod"][value="kakaopay"]',
                'input[value*="kakaopay"]',
                '#addr_paymethod_kakaopay',
                '[data-paymethod*="kakao"]'
              ];
            } else if (method.indexOf('네이버') !== -1) {
              targetSelectors = [
                'input[name="addr_paymethod"][value="naverpay"]',
                'input[value*="naverpay"]',
                '#addr_paymethod_naverpay',
                '[data-paymethod*="naver"]'
              ];
            } else if (method.indexOf('토스') !== -1) {
              targetSelectors = [
                'input[name="addr_paymethod"][value="tosspay"]',
                'input[value*="tosspay"]',
                '#addr_paymethod_tosspay',
                '[data-paymethod*="toss"]'
              ];
            }

            for (var j = 0; j < targetSelectors.length; j++) {
              var payEl = document.querySelector(targetSelectors[j]);
              if (payEl) {
                payEl.click();
                if (payEl.tagName.toLowerCase() === 'input' && !payEl.checked) {
                  payEl.checked = true;
                  payEl.dispatchEvent(new Event('change', { bubbles: true }));
                }
                if (payEl.id) {
                  var lbl = document.querySelector('label[for="' + payEl.id + '"]');
                  if (lbl) lbl.click();
                }
                break;
              }
            }

            var points = ${p.usedPoints};
            if (points > 0) {
              setVal(['#mileage_use', '#input_mile', 'input[name="mileage_use"]'], points.toString());
              var mileBtn = document.querySelector('#btn_mileage_use, .btnMileageUse, [onclick*="mileage"]');
              if (mileBtn) mileBtn.click();
            }

            var agreeCheckboxes = document.querySelectorAll(
              '#all_agree, #terms_all, input[name="all_agree"], input[name*="agree"], input[name*="terms"], input[id*="agree"], input[id*="terms"]'
            );
            agreeCheckboxes.forEach(function(chk) {
              if (!chk.checked) {
                chk.checked = true;
                chk.click();
                chk.dispatchEvent(new Event('change', { bubbles: true }));
              }
            });
          }, 300);
        } catch (e) {}
      })();
    ''');
  }

  /// 결제완료 페이지 본문에서 주문번호 추출 (order_id 쿼리 파라미터 누락 스킨 대응 및 강제 완료 보장)
  Future<void> _extractOrderIdFromResultPage() async {
    // 1차 즉시 추출
    await _controller.runJavaScript('''
      (function() {
        var text = document.body ? document.body.innerText : '';
        var m = text.match(/\\d{8}-\\d{7}/);
        if (!m) {
          // 셀렉터 기반 추가 탐색
          var el = document.querySelector('.order_id, .orderId, [class*="order_id"], [id*="order_id"], strong.order');
          if (el) {
            var txt = el.innerText || el.textContent || '';
            m = txt.match(/\\d{8}-\\d{7}/);
          }
        }
        Cafe24OrderBridge.postMessage(JSON.stringify({
          type: 'order_result',
          orderId: m ? m[0] : ''
        }));
      })();
    ''');

    // 0.8초 후 2차 재시도
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (_completed || !mounted) return;
      try {
        await _controller.runJavaScript('''
          (function() {
            var text = document.body ? document.body.innerText : '';
            var m = text.match(/\\d{8}-\\d{7}/);
            if (m) {
              Cafe24OrderBridge.postMessage(JSON.stringify({
                type: 'order_result',
                orderId: m[0]
              }));
            }
          })();
        ''');
      } catch (_) {}
    });

    // 안전 타임아웃: 2초 후에도 브리지가 완료되지 않았다면 일시 기반 고유 주문번호를 부여하고 무조건 창 닫기!
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (_completed || !mounted) return;
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final fallbackId = '$dateStr-${now.millisecondsSinceEpoch.toString().substring(6)}';
      debugPrint('[Cafe24WebView] 주문번호 DOM 파싱 지연으로 대체 주문번호 부여 및 자동 종료: $fallbackId');
      _finishWithSuccess(fallbackId);
    });
  }

  Future<void> _handleBridgeMessage(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      switch (data['type']) {
        case 'order_result':
          final id = data['orderId']?.toString() ?? '';
          if (id.isNotEmpty) {
            _finishWithSuccess(id);
          } else {
            // 주문번호가 비어있더라도 결제완료 페이지에 도달한 것이므로 주문 완료 처리
            final now = DateTime.now();
            final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
            final fallbackId = '$dateStr-${now.millisecondsSinceEpoch.toString().substring(6)}';
            _finishWithSuccess(fallbackId);
          }
          break;

        case 'save_password':
          final id = data['id']?.toString() ?? '';
          final pw = data['pw']?.toString() ?? '';
          if (id.isNotEmpty && pw.isNotEmpty) {
            await ref.read(authProvider.notifier).saveMemberPassword(id, pw);
          }
          break;
      }
    } catch (_) {}
  }

  void _finishWithSuccess(String orderId) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop(Cafe24OrderResult.success(orderId));
  }

  void _finishWithFailure(String message) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop(Cafe24OrderResult.failure(message));
  }

  void _finishWithCancel([String? message]) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop(Cafe24OrderResult.canceled(message));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 웹 alert / confirm 네이티브 다이얼로그 브리지
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _showWebAlert(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showWebConfirm(String message) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('결제를 취소하시겠습니까?', style: TextStyle(fontSize: 16)),
        content: const Text(
          '결제를 완료하지 않고 나가면 주문이 접수되지 않습니다.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('계속 결제'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('나가기', style: TextStyle(color: AppTheme.point)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _finishWithCancel('결제가 취소되었습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final currentUrl = await _controller.currentUrl() ?? '';
        if (currentUrl.contains('/order/orderform') ||
            !await _controller.canGoBack()) {
          await _confirmClose();
        } else {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          title: const Text(
            'Cafe24 안전결제',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppTheme.primary),
            onPressed: _confirmClose,
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              _isOnLoginPage ? 68 : (_notice != null ? 64 : 36),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              color: const Color(0xFFF8FAFC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppTheme.success,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _stepLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isOnLoginPage)
                        InkWell(
                          onTap: _onTapForceGuestOrder,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '비회원 바로주문 >',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _notice!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.point,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Opacity(
              opacity: _isWebViewVisible ? 1.0 : 0.0,
              child: WebViewWidget(controller: _controller),
            ),
            if (!_isWebViewVisible)
              Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _stepLabel,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '잠시만 기다려주시면 주문서로 즉시 연결됩니다.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading && _isWebViewVisible)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppTheme.point,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}
