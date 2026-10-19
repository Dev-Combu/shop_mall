import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/views/share/kakao_sync_auth_sheet.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const String _loginUrl =
      'https://suzicnl.com/member/login.html?noMemberOrder&returnUrl=%2Fmyshop%2Findex.html';

  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  late final WebViewController _headlessController;
  bool _isLoginPageReady = false;
  Completer<void>? _pageReadyCompleter;
  Completer<User>? _loginCompleter;

  // /myshop/index.html에서 먼저 수집한 기본 혜택 정보 임시 보관
  String _tempMyShopName = '';
  String _tempMyShopGroup = '수지씨앤엘 정회원';
  int _tempMyShopPoints = 0;
  int _tempMyShopCoupons = 0;

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initHeadlessAuthSSLEngine();
  }

  /// Cafe24의 AuthSSLManager 암호화 로그인을 백그라운드에서 수행하는 비가시성(1x1) 엔진 초기화
  Future<void> _initHeadlessAuthSSLEngine() async {
    _pageReadyCompleter = Completer<void>();

    _headlessController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24LoginBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {
        final msg = request.message.trim();
        debugPrint('[Login AuthSSL Alert] $msg');

        if (msg.isNotEmpty &&
            _loginCompleter != null &&
            !_loginCompleter!.isCompleted) {
          _loginCompleter!.completeError(Exception(msg));
        }
        _reloadLoginForm();
      })
      ..setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async => true,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('[Login AuthSSL Engine] Page finished: $url');

            if (url.contains('/member/login.html')) {
              _isLoginPageReady = true;
              if (_pageReadyCompleter != null &&
                  !_pageReadyCompleter!.isCompleted) {
                _pageReadyCompleter!.complete();
              }
              return;
            }

            if (_loginCompleter != null && !_loginCompleter!.isCompleted) {
              // 1단계: 로그인 성공 후 마이쇼핑(/myshop/index.html) 도달 시 적립금/쿠폰/등급 파싱 후 modify.html로 이동
              if (url.contains('/myshop/index.html')) {
                _scrapeMyShopAndNavigateToModify();
              } else if (url.contains('/member/modify.html')) {
                // 2단계: 회원정보 수정 페이지(/member/modify.html)에서 AuthSSLManager 복호화 완료 후 전화번호/이메일 추출
                _pollModifyPageForDecryptedProfile();
              } else if (!url.contains('/exec/front/Member/login')) {
                // 메인(/index.html) 등으로 이동한 경우 마이쇼핑으로 이동하여 회원 정보 조회
                _headlessController.loadRequest(
                  Uri.parse('https://suzicnl.com/myshop/index.html'),
                );
              }
            }
          },
        ),
      );

    await _headlessController.loadRequest(Uri.parse(_loginUrl));
  }

  void _reloadLoginForm() {
    _isLoginPageReady = false;
    _pageReadyCompleter = Completer<void>();
    _headlessController.loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _scrapeMyShopAndNavigateToModify() async {
    await _headlessController.runJavaScript('''
      (function() {
        try {
          var nameEl = document.querySelector('.xans-myshop-asyncbenefit .name, .xans-member-var-name, strong.name, .txtEm');
          var groupEl = document.querySelector('.xans-myshop-asyncbenefit .group, .xans-member-var-group_name');
          var pointEl = document.querySelector('#xans_myshop_bankbook_avail_mileage, .avail_mileage');
          var couponEl = document.querySelector('#xans_myshop_bankbook_coupon_cnt, .couponCount');

          Cafe24LoginBridge.postMessage(JSON.stringify({
            type: 'myshop',
            name: nameEl ? nameEl.innerText.trim() : '',
            groupName: groupEl ? groupEl.innerText.trim() : '수지씨앤엘 정회원',
            points: pointEl ? pointEl.innerText.replace(/[^0-9]/g, '') : '0',
            coupons: couponEl ? couponEl.innerText.replace(/[^0-9]/g, '') : '0'
          }));
        } catch (e) {
          Cafe24LoginBridge.postMessage(JSON.stringify({ type: 'myshop' }));
        }
        window.location.href = 'https://suzicnl.com/member/modify.html';
      })();
    ''');
  }

  /// Cafe24의 /member/modify.html은 개인정보(휴대폰 번호, 이메일, 실명)를 정적 HTML이 아닌
  /// 페이지 로드 후 AuthSSLManager 비동기 복호화 스크립트로 input value에 주입하므로 폴링 대기 후 추출
  Future<void> _pollModifyPageForDecryptedProfile() async {
    await _headlessController.runJavaScript('''
      (function() {
        var attempts = 0;
        var maxAttempts = 14; // 최대 약 2.8초 폴링 대기

        function extractProfileFields() {
          attempts++;
          try {
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

            var nameVal = (modNameEl && modNameEl.value) ? modNameEl.value.trim() : '';
            var emailVal = (modEmailEl && modEmailEl.value) ? modEmailEl.value.trim() : '';

            // AuthSSLManager 복호화가 아직 완료되지 않아 휴대폰 번호가 비어있다면 200ms 후 재확인
            if (!phoneStr && attempts < maxAttempts) {
              setTimeout(extractProfileFields, 200);
              return;
            }

            Cafe24LoginBridge.postMessage(JSON.stringify({
              type: 'profile',
              name: nameVal,
              email: emailVal,
              phone: phoneStr
            }));
          } catch (e) {
            Cafe24LoginBridge.postMessage(JSON.stringify({
              type: 'profile',
              name: '',
              email: '',
              phone: ''
            }));
          }
        }

        extractProfileFields();
      })();
    ''');
  }

  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type']?.toString();

      if (type == 'error') {
        final msg = data['message']?.toString() ?? '로그인 처리 중 오류가 발생했습니다.';
        if (_loginCompleter != null && !_loginCompleter!.isCompleted) {
          _loginCompleter!.completeError(Exception(msg));
        }
        _reloadLoginForm();
      } else if (type == 'myshop') {
        final rawName = data['name']?.toString().trim() ?? '';
        final rawGroup = data['groupName']
                ?.toString()
                .replaceAll(RegExp(r'[\[\]]'), '')
                .trim() ??
            '';
        if (rawName.isNotEmpty) _tempMyShopName = rawName;
        if (rawGroup.isNotEmpty) _tempMyShopGroup = rawGroup;
        _tempMyShopPoints =
            int.tryParse(data['points']?.toString() ?? '0') ?? 0;
        _tempMyShopCoupons =
            int.tryParse(data['coupons']?.toString() ?? '0') ?? 0;
      } else if (type == 'profile') {
        final cleanId = _idController.text.trim();
        final rawName = data['name']?.toString().trim() ?? '';
        final rawEmail = data['email']?.toString().trim() ?? '';
        final rawPhone = data['phone']?.toString().trim() ?? '';

        final finalName = rawName.isNotEmpty
            ? rawName
            : (_tempMyShopName.isNotEmpty ? _tempMyShopName : cleanId);

        final user = User(
          id: cleanId,
          name: finalName,
          email: rawEmail.isNotEmpty
              ? rawEmail
              : (cleanId.contains('@') ? cleanId : '$cleanId@suzicnl.com'),
          phone: rawPhone.isNotEmpty ? rawPhone : null,
          groupName: _tempMyShopGroup.isNotEmpty
              ? _tempMyShopGroup
              : '수지씨앤엘 정회원',
          points: _tempMyShopPoints,
          coupons: _tempMyShopCoupons,
          orders: 0,
          isCafe24Member: true,
        );

        if (_loginCompleter != null && !_loginCompleter!.isCompleted) {
          _loginCompleter!.complete(user);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final cleanId = _idController.text.trim();
    final password = _passwordController.text;

    if (cleanId == 'suzicnl1' && password == '123456') {
      await _handleDemoLogin();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (!_isLoginPageReady && _pageReadyCompleter != null) {
        await _pageReadyCompleter!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('쇼핑몰 서버 연결이 지연되고 있습니다. 다시 시도해주세요.'),
        );
      }

      _loginCompleter = Completer<User>();

      final jsId = jsonEncode(cleanId);
      final jsPw = jsonEncode(password);

      await _headlessController.runJavaScript('''
        (function() {
          try {
            var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
            var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
            if (!idEl || !pwEl) {
              Cafe24LoginBridge.postMessage(JSON.stringify({
                type: 'error',
                message: '로그인 폼을 초기화하는 중입니다. 다시 한번 눌러주세요.'
              }));
              return;
            }
            idEl.value = $jsId;
            pwEl.value = $jsPw;

            var form = idEl.closest('form') || document.querySelector('form[id^="member_form"]');
            if (typeof MemberAction !== 'undefined' && typeof MemberAction.login === 'function' && form) {
              MemberAction.login(form.id);
            } else {
              var loginBtn = document.querySelector('[onclick*="MemberAction.login"], .loginBtn, .btnSubmit');
              if (loginBtn) loginBtn.click();
              else if (form) form.submit();
            }
          } catch (err) {
            Cafe24LoginBridge.postMessage(JSON.stringify({
              type: 'error',
              message: String(err)
            }));
          }
        })();
      ''');

      final user = await _loginCompleter!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('아이디 또는 비밀번호를 다시 확인해주세요.'),
      );

      await ref.read(authProvider.notifier).setAuthenticatedUser(user);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('수지씨앤엘 쇼핑몰 계정으로 로그인되었습니다.'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleDemoLogin() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).loginWithDemo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('테스트 계정(suzicnl1)으로 빠르게 로그인되었습니다.'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleKakaoLogin() async {
    setState(() {
      _errorMessage = null;
    });

    final kakaoUser = await KakaoSyncAuthSheet.show(context);
    if (kakaoUser == null || !mounted) return;

    await ref.read(authProvider.notifier).setAuthenticatedUser(kakaoUser);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('카카오 계정(${kakaoUser.name})으로 로그인되었습니다.'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.primary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '로그인',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
      ),
      body: Stack(
        children: [
          // 백그라운드 Cafe24 AuthSSLManager 실행용 비가시성(1x1, 투명) 엔진
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0.0,
              child: IgnorePointer(
                child: WebViewWidget(controller: _headlessController),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '수지씨앤엘 쇼핑몰',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '쇼핑몰 아이디와 비밀번호로 로그인하세요',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.point, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.point,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _idController,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: '쇼핑몰 아이디',
                            hintText: '아이디 입력',
                            prefixIcon: const Icon(Icons.person_outline, size: 20),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return '쇼핑몰 아이디를 입력해주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submitLogin(),
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            hintText: '비밀번호 입력',
                            prefixIcon: const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: const Color(0xFF94A3B8),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return '비밀번호를 입력해주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    '로그인',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: const [
                      Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '간편 로그인',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 카카오싱크(Kakao Sync) 공식 1초 로그인 버튼
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _handleKakaoLogin,
                      icon: const Icon(
                        Icons.chat_bubble_rounded,
                        size: 20,
                        color: Color(0xFF191919),
                      ),
                      label: const Text(
                        '카카오로 1초 로그인 / 회원가입',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF191919),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE500),
                        foregroundColor: const Color(0xFF191919),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _handleDemoLogin,
                      icon: const Icon(Icons.bolt_rounded, size: 18, color: AppTheme.point),
                      label: const Text(
                        '테스트 계정(suzicnl1)으로 1초 로그인',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '아직 수지씨앤엘 회원이 아니신가요?',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      TextButton(
                        onPressed: () => context.push('/signup'),
                        child: const Text(
                          '회원가입하기',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.point,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
