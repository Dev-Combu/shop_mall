import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
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
              // 로그인 성공 후 마이쇼핑(/myshop/index.html)에 도달한 경우 실제 회원 정보 파싱
              if (url.contains('/myshop/index.html')) {
                _scrapeMyShopProfile();
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

    await WebViewCookieManager().clearCookies();
    await _headlessController.loadRequest(Uri.parse(_loginUrl));
  }

  void _reloadLoginForm() {
    _isLoginPageReady = false;
    _pageReadyCompleter = Completer<void>();
    _headlessController.loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _scrapeMyShopProfile() async {
    final cleanId = _idController.text.trim();
    await _headlessController.runJavaScript('''
      (function() {
        try {
          var bodyText = document.body ? document.body.innerText : '';
          var nameEl = document.querySelector('.xans-myshop-asyncbenefit .name, .xans-member-var-name, strong.name, .txtEm');
          var groupEl = document.querySelector('.xans-myshop-asyncbenefit .group, .xans-member-var-group_name');
          var pointEl = document.querySelector('#xans_myshop_bankbook_avail_mileage, .avail_mileage');
          var couponEl = document.querySelector('#xans_myshop_bankbook_coupon_cnt, .couponCount');

          Cafe24LoginBridge.postMessage(JSON.stringify({
            type: 'profile',
            name: nameEl ? nameEl.innerText.trim() : '',
            groupName: groupEl ? groupEl.innerText.trim() : '수지씨앤엘 정회원',
            points: pointEl ? pointEl.innerText.replace(/[^0-9]/g, '') : '0',
            coupons: couponEl ? couponEl.innerText.replace(/[^0-9]/g, '') : '0'
          }));
        } catch (e) {
          Cafe24LoginBridge.postMessage(JSON.stringify({
            type: 'profile',
            name: '',
            groupName: '수지씨앤엘 정회원',
            points: '0',
            coupons: '0'
          }));
        }
      })();
    ''');
    // 만약 브릿지 응답이 1.5초 내 오지 않으면 기본 로그인 유저로 완료 처리
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_loginCompleter != null && !_loginCompleter!.isCompleted) {
        _loginCompleter!.complete(
          User(
            id: cleanId,
            name: cleanId,
            email: cleanId.contains('@') ? cleanId : '$cleanId@suzicnl.com',
            groupName: '수지씨앤엘 정회원',
            isCafe24Member: true,
          ),
        );
      }
    });
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
      } else if (type == 'profile') {
        final cleanId = _idController.text.trim();
        final rawName = data['name']?.toString().trim() ?? '';
        final rawGroup = data['groupName']
                ?.toString()
                .replaceAll(RegExp(r'[\[\]]'), '')
                .trim() ??
            '수지씨앤엘 정회원';
        final points = int.tryParse(data['points']?.toString() ?? '0') ?? 0;
        final coupons = int.tryParse(data['coupons']?.toString() ?? '0') ?? 0;

        final user = User(
          id: cleanId,
          name: rawName.isNotEmpty ? rawName : cleanId,
          email: cleanId.contains('@') ? cleanId : '$cleanId@suzicnl.com',
          groupName: rawGroup.isNotEmpty ? rawGroup : '수지씨앤엘 정회원',
          points: points,
          coupons: coupons,
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

                  const SizedBox(height: 14),

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
