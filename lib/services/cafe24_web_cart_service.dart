import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/models/user.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cafe24 웹 장바구니 스냅샷 (웹뷰 로그인 세션 유효 여부 포함)
class WebBasketSnapshot {
  final bool isLoggedIn;
  final bool fetchSucceeded;
  final List<Map<String, dynamic>> items;

  const WebBasketSnapshot({
    required this.isLoggedIn,
    required this.fetchSucceeded,
    required this.items,
  });
}

/// Cafe24WebCartService Riverpod 전역 Provider
final cafe24WebCartServiceProvider = Provider<Cafe24WebCartService>((ref) {
  return Cafe24WebCartService();
});

/// Cafe24 쇼핑몰(suzicnl.com) WebKit 세션과 실시간 연동 및 자동 세션 복구를 담당하는 서비스
class Cafe24WebCartService {
  static const String _mallBase = 'https://suzicnl.com';
  static const String _kakaoJsKey = 'd6643748e516858c8b6138b85638b1bb';

  WebViewController? _controller;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  Completer<void>? _pageLoadCompleter;

  /// 단일 WebViewController에 대한 직렬 실행 큐 (동시 페이지 이동 충돌 방지)
  Future<void> _operationChain = Future<void>.value();

  /// 무자각 자동 재로그인 실패 시 불필요한 반복 폴링을 막기 위한 쿨다운 기록
  DateTime? _lastSilentLoginFailAt;
  String? _lastSilentLoginFailUserId;

  WebViewController get controller {
    _ensureInitialized();
    return _controller!;
  }

  /// 대화형(모달/웹뷰) 재로그인이 완료되었을 때 쿨다운 초기화
  void resetSilentLoginCooldown() {
    _lastSilentLoginFailAt = null;
    _lastSilentLoginFailUserId = null;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationChain = _operationChain.then((_) async {
      try {
        final res = await action();
        if (!completer.isCompleted) completer.complete(res);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// 백그라운드 WebViewController 초기화 및 basket.html 로드
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setOnJavaScriptAlertDialog((request) async {
          debugPrint('[Cafe24WebCartService Alert] ${request.message}');
        })
        ..setOnJavaScriptConfirmDialog((request) async => true)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final url = request.url;
              // 백그라운드 웹뷰에서 카카오톡/네이버 앱 스킴 호출을 차단하여 웹 OAuth 리다이렉트 유지
              if (!url.startsWith('http://') &&
                  !url.startsWith('https://') &&
                  !url.startsWith('about:') &&
                  !url.startsWith('javascript:') &&
                  !url.startsWith('data:')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (url) {
              if (!_isInitialized) {
                _isInitialized = true;
                if (_initCompleter != null && !_initCompleter!.isCompleted) {
                  _initCompleter!.complete();
                }
              }
              if (_pageLoadCompleter != null && !_pageLoadCompleter!.isCompleted) {
                _pageLoadCompleter!.complete();
              }
            },
            onWebResourceError: (error) {
              debugPrint('[Cafe24WebCartService] 웹뷰 리소스 오류: ${error.description}');
            },
          ),
        );

      await _controller!.loadRequest(Uri.parse('$_mallBase/order/basket.html'));

      // 안전 타임아웃: 4초 후 강제 초기화 완료
      Timer(const Duration(seconds: 4), () {
        if (!_isInitialized) {
          _isInitialized = true;
          if (_initCompleter != null && !_initCompleter!.isCompleted) {
            _initCompleter!.complete();
          }
        }
      });
    } catch (e) {
      debugPrint('[Cafe24WebCartService] 초기화 예외: $e');
      _isInitialized = true;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    }

    return _initCompleter!.future;
  }

  /// 페이지 이동 및 로딩 완료 대기 (타임아웃 6초)
  Future<void> _loadUrl(String url) async {
    await _ensureInitialized();
    _pageLoadCompleter = Completer<void>();
    await _controller!.loadRequest(Uri.parse(url));
    try {
      await _pageLoadCompleter!.future.timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  String _unescapeJsString(dynamic rawResult) {
    if (rawResult == null) return '';
    String rawStr = rawResult.toString();
    if (rawStr.startsWith('"') && rawStr.endsWith('"')) {
      try {
        final unescaped = jsonDecode(rawStr);
        if (unescaped is String) return unescaped;
      } catch (_) {}
    }
    return rawStr;
  }

  /// 현재 suzicnl.com 페이지에서 Cafe24 회원 로그인 세션 유효 여부 동기 확인
  Future<bool> _checkLoggedInOnCurrentPage() async {
    if (_controller == null) return false;
    try {
      final currentUrl = await _controller!.currentUrl() ?? '';
      if (!currentUrl.contains('suzicnl.com')) {
        await _loadUrl('$_mallBase/order/basket.html');
      }
      final dynamic res = await _controller!.runJavaScriptReturningResult('''
        (function() {
          try {
            if (typeof CAPP_ASYNC_METHODS !== 'undefined' && CAPP_ASYNC_METHODS.IS_LOGIN === true) {
              return 'T';
            }
            if (document.cookie && document.cookie.indexOf('iscache=F') !== -1) {
              return 'T';
            }
            if (document.querySelector('a[href*="/exec/front/Member/logout"]')) {
              return 'T';
            }
            return 'F';
          } catch (e) {
            return 'F';
          }
        })()
      ''');
      return _unescapeJsString(res) == 'T';
    } catch (_) {
      return false;
    }
  }

  /// 외부에서 현재 Cafe24 웹뷰 로그인 세션 유효 여부 확인
  Future<bool> isWebSessionLoggedIn() {
    return _enqueue(() async {
      await _ensureInitialized();
      return _checkLoggedInOnCurrentPage();
    });
  }

  /// 웹뷰 로그인이 풀렸을 때 백그라운드에서 무자각 세션 복구 시도 (Kakao 302 SSO / Naver SSO / AuthSSL ID·PW)
  Future<bool> _trySilentReLoginInternal({
    required User user,
    String? password,
    bool force = false,
  }) async {
    if (user.id.isEmpty || user.id == 'suzicnl1') return true;
    await _ensureInitialized();
    if (_controller == null) return false;

    if (await _checkLoggedInOnCurrentPage()) {
      resetSilentLoginCooldown();
      return true;
    }

    if (!force &&
        _lastSilentLoginFailUserId == user.id &&
        _lastSilentLoginFailAt != null &&
        DateTime.now().difference(_lastSilentLoginFailAt!) <
            const Duration(seconds: 25)) {
      return false;
    }

    try {
      await _loadUrl(
        '$_mallBase/member/login.html?noMemberOrder&returnUrl=%2Forder%2Fbasket.html',
      );

      // 로드 직후 이미 로그인 상태로 리다이렉트된 경우
      if (await _checkLoggedInOnCurrentPage()) {
        resetSilentLoginCooldown();
        return true;
      }

      final isKakao = user.id.endsWith('@k');
      final isNaver = user.id.endsWith('@n');
      final hasPw = password != null && password.isNotEmpty;

      final dynamic triggerRes =
          await _controller!.runJavaScriptReturningResult('''
        (function() {
          try {
            window.alert = function() {};
            window.confirm = function() { return true; };

            var keepEl = document.getElementById('use_login_keeping') || document.querySelector('input[name="use_login_keeping"]');
            if (keepEl && !keepEl.checked) {
              keepEl.checked = true;
              keepEl.dispatchEvent(new Event('change', { bubbles: true }));
            }

            if (${isKakao ? 'true' : 'false'}) {
              if (typeof MemberAction !== 'undefined' && typeof MemberAction.kakaosyncLogin === 'function') {
                MemberAction.kakaosyncLogin('$_kakaoJsKey');
                return 'TRIGGERED_KAKAO';
              }
              if (typeof MemberAction !== 'undefined' && typeof MemberAction.snsLogin === 'function') {
                MemberAction.snsLogin('kakao', '%2Forder%2Fbasket.html');
                return 'TRIGGERED_KAKAO';
              }
              var kBtn = document.querySelector('[onclick*="kakaosyncLogin"], .btnKakao, a.kakao');
              if (kBtn) { kBtn.click(); return 'TRIGGERED_KAKAO'; }
              return 'NO_BTN';
            }

            if (${isNaver ? 'true' : 'false'}) {
              if (typeof MemberAction !== 'undefined' && typeof MemberAction.snsLogin === 'function') {
                MemberAction.snsLogin('naver', '%2Forder%2Fbasket.html');
                return 'TRIGGERED_NAVER';
              }
              var nBtn = document.querySelector('[onclick*="snsLogin(\\'naver\\'"], .btnNaver, a.naver');
              if (nBtn) { nBtn.click(); return 'TRIGGERED_NAVER'; }
              return 'NO_BTN';
            }

            if (${hasPw ? 'true' : 'false'}) {
              var loginDivs = document.querySelectorAll('.login, .xans-member-login');
              loginDivs.forEach(function(d) {
                d.classList.remove('displaynone');
                d.style.display = 'block';
              });
              var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
              var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
              if (idEl && pwEl) {
                idEl.value = ${jsonEncode(user.id)};
                idEl.dispatchEvent(new Event('input', { bubbles: true }));
                pwEl.value = ${jsonEncode(password ?? '')};
                pwEl.dispatchEvent(new Event('input', { bubbles: true }));
                var form = idEl.closest('form') || document.querySelector('form[id^="member_form"]');
                if (typeof MemberAction !== 'undefined' && typeof MemberAction.login === 'function' && form) {
                  MemberAction.login(form.id || 'member_form_');
                  return 'TRIGGERED_IDPW';
                }
                var lBtn = document.querySelector('[onclick*="MemberAction.login"], .btnSubmit, .btnLogin');
                if (lBtn) { lBtn.click(); return 'TRIGGERED_IDPW'; }
              }
              return 'NO_FORM';
            }

            return 'NO_CREDENTIALS';
          } catch (e) {
            return 'ERR:' + e.message;
          }
        })()
      ''');

      final status = _unescapeJsString(triggerRes);
      debugPrint('[Cafe24WebCartService] 무자각 재로그인 시도 결과: $status');

      if (!status.startsWith('TRIGGERED_')) {
        await _loadUrl('$_mallBase/order/basket.html');
        _lastSilentLoginFailUserId = user.id;
        _lastSilentLoginFailAt = DateTime.now();
        return false;
      }

      // 최대 약 4.5초간 OAuth 302 리다이렉트 또는 AuthSSL 로그인 완료 폴링
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 450));
        final url = await _controller!.currentUrl() ?? '';

        // 카카오/네이버 로그인 입력 폼에 머무는 경우 -> 쿠키 만료로 대화형 입력이 필요하므로 즉시 중단
        if (url.contains('accounts.kakao.com/login') ||
            url.contains('nid.naver.com/nidlogin.login')) {
          debugPrint('[Cafe24WebCartService] OAuth 쿠키 만료 감지 (대화형 로그인 필요): $url');
          break;
        }

        if (url.contains('suzicnl.com') &&
            !url.contains('/Api/Member/Oauth2ClientCallback') &&
            !url.contains('/exec/front/Member/login')) {
          if (await _checkLoggedInOnCurrentPage()) {
            debugPrint('[Cafe24WebCartService] 무자각 세션 복구 성공!');
            resetSilentLoginCooldown();
            if (!url.contains('/order/basket.html')) {
              await _loadUrl('$_mallBase/order/basket.html');
            }
            return true;
          }
        }
      }

      await _loadUrl('$_mallBase/order/basket.html');
      final finalCheck = await _checkLoggedInOnCurrentPage();
      if (finalCheck) {
        resetSilentLoginCooldown();
        return true;
      }

      _lastSilentLoginFailUserId = user.id;
      _lastSilentLoginFailAt = DateTime.now();
      return false;
    } catch (e) {
      debugPrint('[Cafe24WebCartService] 무자각 재로그인 예외: $e');
      _lastSilentLoginFailUserId = user.id;
      _lastSilentLoginFailAt = DateTime.now();
      return false;
    }
  }

  /// 외부(결제 런처/장바구니)에서 회원 웹뷰 세션 유효성을 보장하기 위한 메서드
  Future<bool> ensureMemberSession({
    required User user,
    String? password,
    bool forceSilentAttempt = false,
  }) {
    return _enqueue(() async {
      return _trySilentReLoginInternal(
        user: user,
        password: password,
        force: forceSilentAttempt,
      );
    });
  }

  /// Cafe24 웹 세션(/order/basket.html)에서 로그인 상태 + 장바구니 품목 스냅샷 조회
  Future<WebBasketSnapshot> fetchBasketSnapshot({
    User? expectedUser,
    String? password,
    bool forceReload = false,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      if (_controller == null) {
        return const WebBasketSnapshot(
          isLoggedIn: false,
          fetchSucceeded: false,
          items: [],
        );
      }

      try {
        final currentUrl = await _controller!.currentUrl();
        if (forceReload || currentUrl == null || !currentUrl.contains('/order/basket.html')) {
          await _loadUrl('$_mallBase/order/basket.html');
        } else {
          // 이미 basket.html에 머물러 있는 경우 최신 서버 상태 반영을 위해 새로고침
          await _controller!.reload();
          await Future.delayed(const Duration(milliseconds: 650));
        }

        WebBasketSnapshot snap = await _readBasketPageSnapshotInternal();

        // 앱에 로그인된 회원이 있는데 웹뷰 로그인이 풀려 있다면 무자각 세션 복구 후 재조회!
        if (!snap.isLoggedIn &&
            expectedUser != null &&
            expectedUser.id.isNotEmpty &&
            expectedUser.id != 'suzicnl1') {
          final recovered = await _trySilentReLoginInternal(
            user: expectedUser,
            password: password,
          );
          if (recovered) {
            final urlAfter = await _controller!.currentUrl() ?? '';
            if (!urlAfter.contains('/order/basket.html')) {
              await _loadUrl('$_mallBase/order/basket.html');
            } else {
              await _controller!.reload();
              await Future.delayed(const Duration(milliseconds: 650));
            }
            snap = await _readBasketPageSnapshotInternal();
          }
        }

        return snap;
      } catch (e) {
        debugPrint('[Cafe24WebCartService] fetchBasketSnapshot 오류: $e');
        return const WebBasketSnapshot(
          isLoggedIn: false,
          fetchSucceeded: false,
          items: [],
        );
      }
    });
  }

  Future<WebBasketSnapshot> _readBasketPageSnapshotInternal() async {
    final dynamic rawResult = await _controller!.runJavaScriptReturningResult('''
      (function() {
        try {
          var loggedIn = false;
          if (typeof CAPP_ASYNC_METHODS !== 'undefined' && CAPP_ASYNC_METHODS.IS_LOGIN === true) {
            loggedIn = true;
          } else if (document.cookie && document.cookie.indexOf('iscache=F') !== -1) {
            loggedIn = true;
          } else if (document.querySelector('a[href*="/exec/front/Member/logout"]')) {
            loggedIn = true;
          }

          var arr = [];
          if (typeof aBasketProductData !== 'undefined' && Array.isArray(aBasketProductData) && aBasketProductData.length > 0) {
            arr = aBasketProductData;
          } else {
            // [DOM 스크래핑 폴백] aBasketProductData가 비동기 로딩 중이거나 비어있을 때 HTML 테이블에서 직접 추출
            var checkedBoxes = document.querySelectorAll('input[type="checkbox"][id^="basket_chk_id_"]');
            var seenPnos = {};

            checkedBoxes.forEach(function(chk, idx) {
              try {
                var row = chk.closest('tr') || chk.parentElement;
                if (!row) return;

                var pNo = '';
                var pLink = row.querySelector('a[href*="product_no="]');
                if (pLink) {
                  var m = pLink.getAttribute('href').match(/product_no=([0-9]+)/);
                  if (m) pNo = m[1];
                }
                if (!pNo && chk.value && !isNaN(Number(chk.value))) {
                  pNo = chk.value;
                }
                if (!pNo) return;

                var bNo = Number(chk.value) || (idx + 1);
                var pName = '';
                var nameEl = row.querySelector('.name, .product, strong.name, a[href*="product_no="]');
                if (nameEl) {
                  pName = (nameEl.innerText || nameEl.textContent || '').trim();
                }

                var qty = 1;
                var qtyInput = row.querySelector('input[name*="quantity"], input.quantity_opt, #quantity_id_' + idx);
                if (qtyInput && qtyInput.value) {
                  qty = parseInt(qtyInput.value, 10) || 1;
                }

                var price = 0;
                var priceEl = row.querySelector('[id*="sum_price"], .price, .product_price');
                if (priceEl) {
                  var pTxt = (priceEl.innerText || priceEl.textContent || '').replace(/[^0-9]/g, '');
                  if (pTxt) price = parseInt(pTxt, 10) || 0;
                }

                if (!seenPnos[pNo]) {
                  seenPnos[pNo] = true;
                  arr.push({
                    product_no: pNo,
                    product_name: pName,
                    quantity: qty,
                    basket_prd_no: bNo,
                    product_sum_price: price
                  });
                }
              } catch (_) {}
            });
          }

          return JSON.stringify({
            isLoggedIn: loggedIn,
            items: arr
          });
        } catch (e) {
          return JSON.stringify({ isLoggedIn: false, items: [] });
        }
      })()
    ''');

    final rawStr = _unescapeJsString(rawResult);
    if (rawStr.isEmpty) {
      return const WebBasketSnapshot(
        isLoggedIn: false,
        fetchSucceeded: false,
        items: [],
      );
    }

    final decoded = jsonDecode(rawStr);
    if (decoded is Map) {
      final isLoggedIn = decoded['isLoggedIn'] == true;
      final rawItems = decoded['items'];
      final List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        for (final it in rawItems) {
          if (it is Map) {
            final pNo =
                it['product_no']?.toString() ?? it['iProductNo']?.toString() ?? '';
            if (pNo.isNotEmpty) {
              items.add({
                'product_no': pNo,
                'product_name':
                    (it['product_name'] ?? it['sProductName'] ?? '').toString(),
                'quantity': int.tryParse(
                      it['quantity']?.toString() ??
                          it['product_qty']?.toString() ??
                          '1',
                    ) ??
                    1,
                'basket_product_no': int.tryParse(
                  it['basket_prd_no']?.toString() ??
                      it['basket_product_no']?.toString() ??
                      '0',
                ),
                'price': int.tryParse(
                      it['product_sum_price']?.toString() ??
                          it['product_price']?.toString() ??
                          it['price']?.toString() ??
                          '0',
                    ) ??
                    0,
              });
            }
          }
        }
      }
      return WebBasketSnapshot(
        isLoggedIn: isLoggedIn,
        fetchSucceeded: true,
        items: items,
      );
    }

    return const WebBasketSnapshot(
      isLoggedIn: false,
      fetchSucceeded: false,
      items: [],
    );
  }

  /// 하위 호환용 품목 리스트 조회
  Future<List<Map<String, dynamic>>> fetchBasketItems({
    User? expectedUser,
    String? password,
  }) async {
    final snap = await fetchBasketSnapshot(
      expectedUser: expectedUser,
      password: password,
    );
    return snap.items;
  }

  /// Cafe24 웹 세션 장바구니에 상품 추가 (회원 세션 확인/복구 포함)
  Future<bool> addItem({
    required String productNo,
    required int quantity,
    User? expectedUser,
    String? password,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      if (_controller == null) return false;

      // 더미 상품 ID(예: p001)는 Cafe24 상품번호가 아니므로 스킵
      if (int.tryParse(productNo) == null) return false;

      if (expectedUser != null &&
          expectedUser.id.isNotEmpty &&
          expectedUser.id != 'suzicnl1') {
        final ok = await _trySilentReLoginInternal(
          user: expectedUser,
          password: password,
        );
        if (!ok) {
          debugPrint('[Cafe24WebCartService] addItem 보류: 회원 웹뷰 세션 만료 상태');
          return false;
        }
      }

      try {
        await _loadUrl('$_mallBase/product/detail.html?product_no=$productNo');

        final dynamic evalResult =
            await _controller!.runJavaScriptReturningResult('''
          (function() {
            try {
              window.alert = function() {};
              window.confirm = function() { return false; };

              // 1. 필수 옵션 자동 선택 (비활성/구분선 제외한 첫 번째 유효 옵션)
              var selects = document.querySelectorAll('select[option_product_no], select.ProductOption0, select[name^="option"]');
              selects.forEach(function(sel) {
                if (sel.options && sel.options.length > 0) {
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

              // 2. 옵션 박스 생성 직후 수량 반영 및 장바구니 제출
              var targetQty = $quantity;
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
              }, 150);

              return 'OK';
            } catch(e) {
              return 'ERR: ' + e.message;
            }
          })()
        ''');

        debugPrint('[Cafe24WebCartService] addItem evalResult: $evalResult');

        await Future.delayed(const Duration(milliseconds: 1350));
        await _loadUrl('$_mallBase/order/basket.html');
        return true;
      } catch (e) {
        debugPrint('[Cafe24WebCartService] addItem 오류: $e');
        return false;
      }
    });
  }

  /// Cafe24 웹 세션 장바구니 상품 수량 변경
  Future<bool> updateQuantity({
    required int? basketProductNo,
    required String productNo,
    required int quantity,
    User? expectedUser,
    String? password,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      if (_controller == null) return false;

      if (expectedUser != null &&
          expectedUser.id.isNotEmpty &&
          expectedUser.id != 'suzicnl1') {
        final ok = await _trySilentReLoginInternal(
          user: expectedUser,
          password: password,
        );
        if (!ok) return false;
      }

      try {
        final currentUrl = await _controller!.currentUrl();
        if (currentUrl == null || !currentUrl.contains('/order/basket.html')) {
          await _loadUrl('$_mallBase/order/basket.html');
        }

        final dynamic evalResult =
            await _controller!.runJavaScriptReturningResult('''
          (function() {
            try {
              window.alert = function() {};
              window.confirm = function() { return true; };

              var bNo = ${basketProductNo ?? 'null'};
              var pNo = '$productNo';
              var targetQty = $quantity;
              var modified = false;

              if (typeof aBasketProductData !== 'undefined' && Array.isArray(aBasketProductData)) {
                for (var i = 0; i < aBasketProductData.length; i++) {
                  var it = aBasketProductData[i];
                  if ((bNo && (it.basket_prd_no == bNo || it.basket_product_no == bNo)) || (pNo && it.product_no == pNo)) {
                    var qEl = document.getElementById('quantity_id_' + i);
                    if (qEl) {
                      qEl.value = String(targetQty);
                      qEl.dispatchEvent(new Event('input', { bubbles: true }));
                      qEl.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    if (typeof Basket !== 'undefined' && typeof Basket.modifyQuantity === 'function') {
                      Basket.modifyQuantity('quantity_id_' + i);
                      modified = true;
                      break;
                    }
                  }
                }
              }

              if (!modified) {
                var row = null;
                if (bNo) {
                  var chk = document.querySelector('input[type="checkbox"][id^="basket_chk_id_"][value="' + bNo + '"]');
                  if (chk) row = chk.closest('tr') || chk.parentElement;
                }
                if (!row && pNo) {
                  var link = document.querySelector('a[href*="product_no=' + pNo + '"]');
                  if (link) row = link.closest('tr') || link.parentElement;
                }

                if (row) {
                  var qtyInput = row.querySelector('input[name*="quantity"], input.quantity_opt');
                  var modBtn = row.querySelector('.btnModify, .btnQuantity, [onclick*="modify"], a[onclick*="Basket"], a.modify');
                  if (qtyInput) {
                    qtyInput.value = String(targetQty);
                    qtyInput.dispatchEvent(new Event('input', { bubbles: true }));
                    qtyInput.dispatchEvent(new Event('change', { bubbles: true }));
                    if (modBtn) {
                      modBtn.click();
                      modified = true;
                    }
                  }
                }
              }

              if (!modified && bNo) {
                var xhr = new XMLHttpRequest();
                xhr.open('POST', '/exec/front/order/basket/', false);
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                xhr.send('command=modify_quantity&basket_product_no=' + bNo + '&quantity=' + targetQty + '&delvtype=A');
                modified = true;
              }

              return modified ? 'MODIFIED' : 'FAILED';
            } catch(e) {
              return 'ERR: ' + e.message;
            }
          })()
        ''');

        debugPrint('[Cafe24WebCartService] updateQuantity evalResult: $evalResult');

        await Future.delayed(const Duration(milliseconds: 600));
        await _loadUrl('$_mallBase/order/basket.html');
        return true;
      } catch (e) {
        debugPrint('[Cafe24WebCartService] updateQuantity 오류: $e');
        return false;
      }
    });
  }

  /// Cafe24 웹 세션 장바구니 상품 삭제
  Future<bool> deleteItem({
    required int? basketProductNo,
    required String productNo,
    User? expectedUser,
    String? password,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      if (_controller == null) return false;

      if (expectedUser != null &&
          expectedUser.id.isNotEmpty &&
          expectedUser.id != 'suzicnl1') {
        final ok = await _trySilentReLoginInternal(
          user: expectedUser,
          password: password,
        );
        if (!ok) return false;
      }

      try {
        final currentUrl = await _controller!.currentUrl();
        if (currentUrl == null || !currentUrl.contains('/order/basket.html')) {
          await _loadUrl('$_mallBase/order/basket.html');
        }

        final dynamic evalResult =
            await _controller!.runJavaScriptReturningResult('''
          (function() {
            try {
              window.alert = function() {};
              window.confirm = function() { return true; };

              var bNo = ${basketProductNo ?? 'null'};
              var pNo = '$productNo';
              var deleted = false;

              if (typeof aBasketProductData !== 'undefined' && Array.isArray(aBasketProductData)) {
                for (var i = 0; i < aBasketProductData.length; i++) {
                  var it = aBasketProductData[i];
                  if ((bNo && (it.basket_prd_no == bNo || it.basket_product_no == bNo)) || (pNo && it.product_no == pNo)) {
                    if (typeof selBasketDel === 'function') {
                      selBasketDel('basket_chk_id_' + i);
                      deleted = true;
                      break;
                    } else if (typeof Basket !== 'undefined' && typeof Basket.deleteBasket === 'function') {
                      if (typeof \$ !== 'undefined') {
                        \$('[id^="basket_chk_id_"]').prop('checked', false);
                        \$('#basket_chk_id_' + i).prop('checked', true);
                      }
                      Basket.deleteBasket();
                      deleted = true;
                      break;
                    }
                  }
                }
              }

              if (!deleted) {
                var row = null;
                if (bNo) {
                  var chk = document.querySelector('input[type="checkbox"][id^="basket_chk_id_"][value="' + bNo + '"]');
                  if (chk) row = chk.closest('tr') || chk.parentElement;
                }
                if (!row && pNo) {
                  var link = document.querySelector('a[href*="product_no=' + pNo + '"]');
                  if (link) row = link.closest('tr') || link.parentElement;
                }

                if (row) {
                  var delBtn = row.querySelector('.btnDelete, [onclick*="delete"], [data-action*="delete"], a.delete');
                  if (delBtn) {
                    delBtn.click();
                    deleted = true;
                  }
                }
              }

              if (!deleted) {
                var delTarget = bNo ? String(bNo) : pNo;
                var xhr = new XMLHttpRequest();
                xhr.open('POST', '/exec/front/order/basket/', false);
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                xhr.send('command=select_delete&checked_product=' + encodeURIComponent(delTarget) + '&delvtype=A');
                deleted = true;
              }

              return deleted ? 'DELETED' : 'FAILED';
            } catch(e) {
              return 'ERR: ' + e.message;
            }
          })()
        ''');

        debugPrint('[Cafe24WebCartService] deleteItem evalResult: $evalResult');

        await Future.delayed(const Duration(milliseconds: 600));
        await _loadUrl('$_mallBase/order/basket.html');
        return true;
      } catch (e) {
        debugPrint('[Cafe24WebCartService] deleteItem 오류: $e');
        return false;
      }
    });
  }

  /// Cafe24 웹 세션 장바구니 전체 비우기
  Future<bool> clearBasket({
    User? expectedUser,
    String? password,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      if (_controller == null) return false;

      if (expectedUser != null &&
          expectedUser.id.isNotEmpty &&
          expectedUser.id != 'suzicnl1') {
        final ok = await _trySilentReLoginInternal(
          user: expectedUser,
          password: password,
        );
        if (!ok) return false;
      }

      try {
        final currentUrl = await _controller!.currentUrl();
        if (currentUrl == null || !currentUrl.contains('/order/basket.html')) {
          await _loadUrl('$_mallBase/order/basket.html');
        }

        final dynamic evalResult =
            await _controller!.runJavaScriptReturningResult('''
          (function() {
            try {
              window.alert = function() {};
              window.confirm = function() { return true; };

              if (typeof Basket !== 'undefined' && typeof Basket.deleteBasket === 'function' && typeof \$ !== 'undefined') {
                \$('[id^="basket_chk_id_"]').prop('checked', true);
                Basket.deleteBasket();
              }

              var xhr = new XMLHttpRequest();
              xhr.open('POST', '/exec/front/order/basket/', false);
              xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
              xhr.send('command=all_delete&delvtype=A');

              return 'OK';
            } catch (e) {
              return 'ERR: ' + e.message;
            }
          })()
        ''');

        debugPrint('[Cafe24WebCartService] clearBasket evalResult: $evalResult');

        await Future.delayed(const Duration(milliseconds: 600));
        await _loadUrl('$_mallBase/order/basket.html');
        return true;
      } catch (e) {
        debugPrint('[Cafe24WebCartService] clearBasket 오류: $e');
        return false;
      }
    });
  }
}
