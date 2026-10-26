import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 수지씨앤엘 쇼핑몰(suzicnl.com) Cafe24 네이버(Naver) 간편로그인/회원가입 모달 시트
class NaverAuthSheet extends StatefulWidget {
  const NaverAuthSheet({super.key});

  /// 네이버 인증 모달을 띄우고, 실제 Cafe24 가입/인증 완료 시 회원 정보를 담은 [User]를 반환합니다.
  static Future<User?> show(BuildContext context) {
    return showModalBottomSheet<User>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const NaverAuthSheet(),
    );
  }

  @override
  State<NaverAuthSheet> createState() => _NaverAuthSheetState();
}

class _NaverAuthSheetState extends State<NaverAuthSheet> {
  static const String _loginUrl =
      'https://suzicnl.com/member/login.html?noMemberOrder&returnUrl=%2Fmyshop%2Findex.html';

  late final WebViewController _controller;

  bool _hasTriggeredNaverLogin = false;
  bool _hasVisitedNaverAuth = false;
  bool _showWebView = false;
  String _statusMessage = '네이버 인증 화면을 준비하고 있습니다...';

  String _tempMemberId = '';
  String _tempName = '';
  String _tempGroup = '수지씨앤엘 정회원';
  int _tempPoints = 0;
  int _tempCoupons = 0;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _initNaverAuthWebView();
  }

  Future<void> _initNaverAuthWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24NaverBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {
        final msg = request.message.trim();
        debugPrint('[NaverAuth Alert] $msg');
        if (mounted && msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: msg.contains('완료') || msg.contains('축하')
                  ? AppTheme.primary
                  : AppTheme.point,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      })
      ..setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async => true,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            debugPrint('[NaverAuth NavRequest] $url');

            // 네이버 앱 외부 스킴(nidlogin://, naversearchapp:// 등) 호출 시 웹뷰 에러를 방지하고 웹 로그인 유도
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }

            if (url.contains('naver.com')) {
              _hasVisitedNaverAuth = true;
              if (mounted && !_showWebView) {
                setState(() {
                  _showWebView = true;
                });
              }
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            debugPrint('[NaverAuth PageFinished] $url');

            // 1. 네이버 인증 도메인(nid.naver.com 등) 표시
            if (url.contains('naver.com')) {
              _hasVisitedNaverAuth = true;
              if (mounted && !_showWebView) {
                setState(() {
                  _showWebView = true;
                });
              }
              return;
            }

            // 2. 최초 Cafe24 로그인 페이지 로드 완료 시 네이버 로그인 실행
            if (!_hasTriggeredNaverLogin && url.contains('/member/login.html')) {
              _hasTriggeredNaverLogin = true;
              _triggerCafe24NaverLogin();
              return;
            }

            // 3. 네이버 인증을 거친 뒤 suzicnl.com으로 돌아온 경우
            if (_hasVisitedNaverAuth && url.contains('suzicnl.com')) {
              // OAuth 콜백 중간 처리 경로는 그대로 진행하도록 대기
              if (url.contains('/Api/Member/Oauth2ClientCallback')) {
                return;
              }

              // 3-A. 마이쇼핑(/myshop/index.html)에 도달한 경우: 실제 로그인 여부 검증 후 프로필 추출
              if (url.contains('/myshop/index.html')) {
                _verifyAndScrapeMyShop();
                return;
              }

              // 3-B. 회원정보 수정(/member/modify.html)에 도달한 경우: 복호화된 이름/이메일/휴대폰 추출
              if (url.contains('/member/modify.html')) {
                _pollModifyPageForDecryptedProfile();
                return;
              }

              // 3-C. 그 외 suzicnl.com 페이지(신규 SNS 약관동의 레이어, /member/join.html, /member/agreement.html, /index.html 등):
              // 현재 페이지에서 Cafe24 세션이 생성되었는지 또는 추가 가입/약관동의 화면인지 확인
              _inspectCafe24PageAfterNaver();
            }
          },
        ),
      );

    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _triggerCafe24NaverLogin() async {
    await _controller.runJavaScript('''
      (function() {
        var attempts = 0;
        var maxAttempts = 25; // 25회 * 150ms = 약 3.75초 동안 비동기 스크립트/DOM 로딩 대기

        function tryTrigger() {
          attempts++;
          try {
            // 1. Cafe24 공식 SNS 네이버 로그인 메서드 시도
            if (typeof MemberAction !== 'undefined' && typeof MemberAction.snsLogin === 'function') {
              MemberAction.snsLogin('naver', '%2Fmyshop%2Findex.html');
              return true;
            }

            // 2. 다양한 셀렉터로 네이버 로그인 버튼 탐색
            var selectors = [
              '[onclick*="snsLogin(\\'naver\\'"]',
              '[onclick*="snsLogin(\\"naver\\""]',
              '.btnNaver',
              '.btn-naver',
              'a.naver',
              'a[href*="/naver"]',
              'a[href*="nid.naver.com"]'
            ];

            for (var i = 0; i < selectors.length; i++) {
              var el = document.querySelector(selectors[i]);
              if (el) {
                el.click();
                return true;
              }
            }

            // 3. 이미지(img) alt/src 기반 네이버 버튼 탐색
            var naverImgs = document.querySelectorAll('img[alt*="네이버"], img[src*="naver"]');
            if (naverImgs.length > 0) {
              var btn = naverImgs[0].closest('a, button') || naverImgs[0];
              btn.click();
              return true;
            }

            // 4. 텍스트 내용 기반 탐색
            var allLinks = document.querySelectorAll('a, button');
            for (var j = 0; j < allLinks.length; j++) {
              var item = allLinks[j];
              var text = (item.innerText || '').trim();
              var onclickAttr = (item.getAttribute('onclick') || '').toLowerCase();
              if (text.indexOf('네이버') !== -1 || onclickAttr.indexOf('naver') !== -1) {
                item.click();
                return true;
              }
            }
          } catch (e) {
            console.error('[NaverAuth] tryTrigger error: ' + e);
          }
          return false;
        }

        // 최초 1회 즉시 시도
        if (tryTrigger()) return;

        // 즉시 탐색 실패 시 비동기 스크립트 실행을 대기하며 폴링 수행
        var timer = setInterval(function() {
          if (tryTrigger()) {
            clearInterval(timer);
          } else if (attempts >= maxAttempts) {
            clearInterval(timer);
            Cafe24NaverBridge.postMessage(JSON.stringify({
              type: 'show_webview_fallback',
              message: '네이버 로그인 버튼을 확인하고 있습니다.'
            }));
          }
        }, 150);
      })();
    ''');
  }

  /// 네이버 인증 후 돌아온 suzicnl.com 페이지에서:
  /// 1) 이미 Cafe24 로그인이 완료된 상태(IS_LOGIN === true 또는 iscache=F 쿠키 또는 join_result.html)인지 확인
  /// 2) 아직 로그인이 완료되지 않았다면(신규 네이버 회원의 약관 동의 레이어 #mCafe24SnsAgree, /member/join.html 등)
  ///    웹뷰를 그대로 화면에 노출하고 모바일 화면 크기에 맞게 스타일을 보정하여 사용자가 가입 완료 버튼을 누를 수 있게 함
  Future<void> _inspectCafe24PageAfterNaver() async {
    await _controller.runJavaScript('''
      (function() {
        try {
          var isLoggedIn = false;
          if (typeof CAPP_ASYNC_METHODS !== 'undefined' && CAPP_ASYNC_METHODS.IS_LOGIN === true) {
            isLoggedIn = true;
          }
          if (document.cookie.indexOf('iscache=F') !== -1) {
            isLoggedIn = true;
          }
          if (window.location.href.indexOf('join_result.html') !== -1 ||
              window.location.href.indexOf('join_complete') !== -1) {
            isLoggedIn = true;
          }
          if (document.querySelector('a[href*="/exec/front/Member/logout"]')) {
            isLoggedIn = true;
          }

          if (isLoggedIn) {
            Cafe24NaverBridge.postMessage(JSON.stringify({
              type: 'logged_in_confirmed'
            }));
            return;
          }

          // 아직 로그인 세션이 생성되지 않은 경우:
          // Cafe24 SNS 약관 동의 레이어(#mCafe24SnsAgree)가 모바일 화면에서 잘리지 않도록 반응형 스타일 보정
          var snsLayer = document.getElementById('mCafe24SnsAgree');
          var snsIframe = document.getElementById('ifrm_sns');
          if (snsLayer) {
            snsLayer.style.left = '0';
            snsLayer.style.top = '0';
            snsLayer.style.margin = '0';
            snsLayer.style.width = '100%';
            snsLayer.style.height = '100%';
          }
          if (snsIframe) {
            snsIframe.style.width = '100%';
            snsIframe.style.height = '100%';
          }

          Cafe24NaverBridge.postMessage(JSON.stringify({
            type: 'show_registration_step',
            url: window.location.href
          }));
        } catch (e) {
          Cafe24NaverBridge.postMessage(JSON.stringify({
            type: 'show_registration_step',
            url: ''
          }));
        }
      })();
    ''');
  }

  /// /myshop/index.html에 도달했을 때 실제로 로그인된 회원인지 확인 후 회원 아이디/이름/혜택 수집
  Future<void> _verifyAndScrapeMyShop() async {
    await _controller.runJavaScript('''
      (function() {
        try {
          if (window.location.href.indexOf('/member/login.html') !== -1) {
            return;
          }

          var nameEl = document.querySelector('.xans-myshop-asyncbenefit .name, .xans-member-var-name, strong.name, .txtEm');
          var groupEl = document.querySelector('.xans-myshop-asyncbenefit .group, .xans-member-var-group_name');
          var pointEl = document.querySelector('#xans_myshop_bankbook_avail_mileage, .avail_mileage');
          var couponEl = document.querySelector('#xans_myshop_bankbook_coupon_cnt, .couponCount');
          var idEl = document.querySelector('.xans-member-var-id');

          var memberId = idEl ? idEl.innerText.trim() : '';
          if (!memberId && typeof CAPP_ASYNC_METHODS !== 'undefined' && CAPP_ASYNC_METHODS.AppCommon && typeof CAPP_ASYNC_METHODS.AppCommon.getMemberID === 'function') {
            memberId = CAPP_ASYNC_METHODS.AppCommon.getMemberID() || '';
          }

          Cafe24NaverBridge.postMessage(JSON.stringify({
            type: 'myshop',
            id: memberId,
            name: nameEl ? nameEl.innerText.trim() : '',
            groupName: groupEl ? groupEl.innerText.trim() : '수지씨앤엘 정회원',
            points: pointEl ? pointEl.innerText.replace(/[^0-9]/g, '') : '0',
            coupons: couponEl ? couponEl.innerText.replace(/[^0-9]/g, '') : '0'
          }));

          window.location.href = 'https://suzicnl.com/member/modify.html';
        } catch (e) {
          window.location.href = 'https://suzicnl.com/member/modify.html';
        }
      })();
    ''');
  }

  Future<void> _pollModifyPageForDecryptedProfile() async {
    await _controller.runJavaScript('''
      (function() {
        var attempts = 0;
        var maxAttempts = 12; // 최대 2.4초 폴링 대기

        function checkDecryptedFields() {
          attempts++;
          try {
            var idEl = document.querySelector('#member_id, input[name="member_id"]');
            var modNameEl = document.querySelector('#name, input[name="name"]');
            var modEmailEl = document.querySelector('#email1, input[name="email1"]');
            var mobiles = document.querySelectorAll('select[name="mobile[]"], input[name="mobile[]"], #mobile1, #mobile2, #mobile3');
            var phones = document.querySelectorAll('select[name="phone[]"], input[name="phone[]"], #phone1, #phone2, #phone3');

            var phoneStr = '';
            if (mobiles.length >= 3) {
              var m1 = (mobiles[0].value || '010').trim();
              var m2 = (mobiles[1].value || '').trim();
              var m3 = (mobiles[2].value || '').trim();
              if (m2 && m3) {
                phoneStr = m1 + '-' + m2 + '-' + m3;
              }
            }
            if (!phoneStr && phones.length >= 3) {
              var p1 = (phones[0].value || '02').trim();
              var p2 = (phones[1].value || '').trim();
              var p3 = (phones[2].value || '').trim();
              if (p2 && p3) {
                phoneStr = p1 + '-' + p2 + '-' + p3;
              }
            }

            var idVal = (idEl && (idEl.value || idEl.innerText)) ? (idEl.value || idEl.innerText).trim() : '';
            if (!idVal && typeof CAPP_ASYNC_METHODS !== 'undefined' && CAPP_ASYNC_METHODS.AppCommon && typeof CAPP_ASYNC_METHODS.AppCommon.getMemberID === 'function') {
              idVal = CAPP_ASYNC_METHODS.AppCommon.getMemberID() || '';
            }
            var nameVal = (modNameEl && modNameEl.value) ? modNameEl.value.trim() : '';
            var emailVal = (modEmailEl && modEmailEl.value) ? modEmailEl.value.trim() : '';

            if ((!phoneStr || !nameVal || !idVal) && attempts < maxAttempts) {
              setTimeout(checkDecryptedFields, 200);
              return;
            }

            Cafe24NaverBridge.postMessage(JSON.stringify({
              type: 'profile',
              id: idVal,
              name: nameVal,
              email: emailVal,
              phone: phoneStr
            }));
          } catch (e) {
            Cafe24NaverBridge.postMessage(JSON.stringify({
              type: 'profile',
              id: '',
              name: '',
              email: '',
              phone: ''
            }));
          }
        }

        checkDecryptedFields();
      })();
    ''');
  }

  void _handleBridgeMessage(String raw) {
    if (_isCompleted || !mounted) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type']?.toString();
      debugPrint('[NaverAuth Bridge] $raw');

      if (type == 'error') {
        final msg = data['message']?.toString() ?? '네이버 로그인 중 오류가 발생했습니다.';
        if (msg.contains('모듈') || msg.contains('불러오지')) {
          setState(() {
            _showWebView = true;
            _statusMessage = '네이버 로그인 버튼을 직접 터치해주세요.';
          });
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.point,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      } else if (type == 'show_webview_fallback') {
        setState(() {
          _showWebView = true;
          _statusMessage = '네이버 로그인 버튼을 직접 터치해주세요.';
        });
      } else if (type == 'logged_in_confirmed') {
        // 실제로 Cafe24 로그인 세션(iscache=F / IS_LOGIN)이 확인된 경우에만 마이쇼핑으로 이동하여 프로필 추출
        setState(() {
          _showWebView = false;
          _statusMessage = '네이버 인증 완료! 회원 정보를 동기화하고 있습니다...';
        });
        _controller.loadRequest(
          Uri.parse('https://suzicnl.com/myshop/index.html'),
        );
      } else if (type == 'show_registration_step') {
        // 신규 네이버 회원의 약관 동의 레이어 또는 추가 정보 입력 페이지인 경우 웹뷰를 그대로 노출
        setState(() {
          _showWebView = true;
        });
      } else if (type == 'myshop') {
        final rawId = data['id']?.toString().trim() ?? '';
        final rawName = data['name']?.toString().trim() ?? '';
        final rawGroup = data['groupName']
                ?.toString()
                .replaceAll(RegExp(r'[\[\]]'), '')
                .trim() ??
            '';
        if (rawId.isNotEmpty) _tempMemberId = rawId;
        if (rawName.isNotEmpty) _tempName = rawName;
        if (rawGroup.isNotEmpty) _tempGroup = rawGroup;
        _tempPoints = int.tryParse(data['points']?.toString() ?? '0') ?? 0;
        _tempCoupons = int.tryParse(data['coupons']?.toString() ?? '0') ?? 0;
      } else if (type == 'profile') {
        final rawId = data['id']?.toString().trim() ?? '';
        final rawName = data['name']?.toString().trim() ?? '';
        final rawEmail = data['email']?.toString().trim() ?? '';
        final rawPhone = data['phone']?.toString().trim() ?? '';

        final finalId = rawId.isNotEmpty ? rawId : _tempMemberId;
        final finalName = rawName.isNotEmpty
            ? rawName
            : (_tempName.isNotEmpty ? _tempName : finalId);

        if (finalId.isEmpty) {
          setState(() {
            _showWebView = true;
          });
          return;
        }

        _isCompleted = true;
        final finalEmail = rawEmail.isNotEmpty ? rawEmail : '$finalId@naver.com';

        final user = User(
          id: finalId,
          name: finalName,
          email: finalEmail,
          phone: rawPhone.isNotEmpty ? rawPhone : null,
          groupName: _tempGroup.isNotEmpty ? _tempGroup : '수지씨앤엘 정회원',
          points: _tempPoints,
          coupons: _tempCoupons,
          orders: 0,
          isCafe24Member: true,
        );

        Navigator.of(context).pop(user);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 상단 네이티브 헤더 바 (네이버 공식 그린 컬러 #03C75A)
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF03C75A),
              border: Border(
                bottom: BorderSide(color: Color(0xFF02B350), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'N',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF03C75A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '네이버 간편 로그인 / 회원가입',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // 본문: 네이버 인증/가입 화면 또는 프로필 동기화 로딩 오버레이
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),

                if (!_showWebView)
                  Container(
                    color: Colors.white,
                    width: double.infinity,
                    height: double.infinity,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF03C75A),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Color(0xFF03C75A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '수지씨앤엘 공식 네이버 아이디 로그인 보안 연결 중',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

