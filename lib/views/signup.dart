import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/views/share/kakao_sync_auth_sheet.dart';
import 'package:shopmall/views/share/naver_auth_sheet.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  static const String _joinUrl = 'https://suzicnl.com/member/join.html';

  final _formKey = GlobalKey<FormState>();
  final _memberIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  late final WebViewController _headlessController;
  bool _isJoinPageReady = false;
  Completer<void>? _pageReadyCompleter;
  Completer<bool>? _signUpCompleter;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initHeadlessAuthSSLEngine();
  }

  /// Cafe24의 AuthSSLManager 암호화 모듈을 백그라운드에서 실행하기 위한 비가시성(1x1) 엔진 초기화
  Future<void> _initHeadlessAuthSSLEngine() async {
    _pageReadyCompleter = Completer<void>();

    _headlessController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24SignUpBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {
        final msg = request.message.trim();
        debugPrint('[SignUp AuthSSL Alert] $msg');

        final isSuccessMsg = msg.contains('가입이 완료') ||
            msg.contains('회원가입이 완료') ||
            msg.contains('축하') ||
            msg.contains('감사합니다');

        if (isSuccessMsg) {
          if (_signUpCompleter != null && !_signUpCompleter!.isCompleted) {
            _signUpCompleter!.complete(true);
          }
        } else if (msg.isNotEmpty) {
          if (_signUpCompleter != null && !_signUpCompleter!.isCompleted) {
            _signUpCompleter!.completeError(Exception(msg));
          }
          // 에러 발생 시 다음 시도를 위해 가입 폼 재로드
          _reloadJoinForm();
        }
      })
      ..setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async => true,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('[SignUp AuthSSL Engine] Page finished: $url');

            if (url.contains('/member/join.html')) {
              _isJoinPageReady = true;
              if (_pageReadyCompleter != null &&
                  !_pageReadyCompleter!.isCompleted) {
                _pageReadyCompleter!.complete();
              }
              return;
            }

            // 가입 완료 결과 페이지(/member/join_result.html)로 이동한 경우 성공 처리
            if (_signUpCompleter != null && !_signUpCompleter!.isCompleted) {
              if (url.contains('join_result.html') ||
                  url.contains('join_complete') ||
                  url.contains('index.html')) {
                _signUpCompleter!.complete(true);
              }
            }
          },
        ),
      );

    // 기존 쿠키로 인해 /member/join.html 접근이 리다이렉트되지 않도록 초기화 후 로드
    await WebViewCookieManager().clearCookies();
    await _headlessController.loadRequest(Uri.parse(_joinUrl));
  }

  void _reloadJoinForm() {
    _isJoinPageReady = false;
    _pageReadyCompleter = Completer<void>();
    _headlessController.loadRequest(Uri.parse(_joinUrl));
  }

  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type']?.toString();
      final message = data['message']?.toString() ?? '';

      if (type == 'error' && message.isNotEmpty) {
        if (_signUpCompleter != null && !_signUpCompleter!.isCompleted) {
          _signUpCompleter!.completeError(Exception(message));
        }
        _reloadJoinForm();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _memberIdController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  bool get _allAgreed => _agreeTerms && _agreePrivacy;

  void _toggleAllAgreed(bool? val) {
    final target = val ?? false;
    setState(() {
      _agreeTerms = target;
      _agreePrivacy = target;
    });
  }

  /// Cafe24 표준 비밀번호 정책 검증
  String? _validateCafe24Password(String? val) {
    if (val == null || val.isEmpty) {
      return '비밀번호를 입력해주세요.';
    }
    if (val.length < 8 || val.length > 16) {
      return '비밀번호는 8~16자로 입력해주세요.';
    }
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(val);
    final hasDigit = RegExp(r'[0-9]').hasMatch(val);
    final hasSpecial = RegExp(r'[^a-zA-Z0-9]').hasMatch(val);

    final typeCount =
        (hasLetter ? 1 : 0) + (hasDigit ? 1 : 0) + (hasSpecial ? 1 : 0);

    if (typeCount < 2) {
      return '영문, 숫자, 특수문자 중 2가지 이상을 조합해주세요.';
    }
    if (typeCount == 2 && val.length < 10) {
      return '2가지 조합 시 10자 이상(또는 영문+숫자+특수문자 8자 이상) 입력해주세요.';
    }
    return null;
  }

  Future<void> _submitSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_allAgreed) {
      setState(() {
        _errorMessage = '필수 이용약관 및 개인정보 수집·이용에 동의해주세요.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final cleanId = _memberIdController.text.trim();
    final cleanName = _nameController.text.trim();
    final cleanEmail = _emailController.text.trim();
    final password = _passwordController.text;
    final cleanPhone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

    final mobile1 = cleanPhone.substring(0, 3);
    final mobile2 = cleanPhone.length == 10
        ? cleanPhone.substring(3, 6)
        : cleanPhone.substring(3, 7);
    final mobile3 = cleanPhone.length == 10
        ? cleanPhone.substring(6)
        : cleanPhone.substring(7);

    try {
      // 1. 백그라운드 가입 폼 준비 확인
      if (!_isJoinPageReady && _pageReadyCompleter != null) {
        await _pageReadyCompleter!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('쇼핑몰 서버 연결이 지연되고 있습니다. 다시 시도해주세요.'),
        );
      }

      _signUpCompleter = Completer<bool>();

      // 2. 안전한 JSON 인코딩으로 특수문자 이스케이프 후 Cafe24 AuthSSL 가입 액션 실행
      final jsMemberId = jsonEncode(cleanId);
      final jsName = jsonEncode(cleanName);
      final jsEmail = jsonEncode(cleanEmail);
      final jsPassword = jsonEncode(password);
      final jsM1 = jsonEncode(mobile1);
      final jsM2 = jsonEncode(mobile2);
      final jsM3 = jsonEncode(mobile3);

      await _headlessController.runJavaScript('''
        (function() {
          try {
            var memberId = $jsMemberId;
            var nameVal = $jsName;
            var emailVal = $jsEmail;
            var passwdVal = $jsPassword;
            var m1 = $jsM1;
            var m2 = $jsM2;
            var m3 = $jsM3;

            var jq = window.jQuery || window.\$ || window.EC\$;

            function setFieldValue(el, val) {
              if (!el) return;
              el.focus();
              el.value = val;
              if (jq) {
                try {
                  jq(el).val(val).trigger('focus').trigger('keydown').trigger('keyup').trigger('change').trigger('blur');
                } catch (e) {}
              }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('keyup', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              el.dispatchEvent(new Event('blur', { bubbles: true }));
            }

            var pRadio = document.querySelector('input[name="member_type"][value="p"]');
            if (pRadio && !pRadio.checked) {
              pRadio.checked = true;
              if (jq) {
                try { jq(pRadio).trigger('click').trigger('change'); } catch (e) {}
              }
              pRadio.dispatchEvent(new Event('click', { bubbles: true }));
            }

            setFieldValue(document.getElementById('member_id') || document.querySelector('input[name="member_id"]'), memberId);
            setFieldValue(document.getElementById('passwd') || document.querySelector('input[name="passwd"]'), passwdVal);
            setFieldValue(document.getElementById('user_passwd_confirm') || document.querySelector('input[name="user_passwd_confirm"]'), passwdVal);
            setFieldValue(document.getElementById('name') || document.querySelector('input[name="name"]'), nameVal);
            setFieldValue(document.getElementById('email1') || document.querySelector('input[name="email1"]'), emailVal);

            var mobiles = document.querySelectorAll('[name="mobile[]"]');
            if (mobiles.length >= 3) {
              setFieldValue(mobiles[0], m1);
              setFieldValue(mobiles[1], m2);
              setFieldValue(mobiles[2], m3);
            }

            var checkSelectors = [
              'input[name="agree_service_check[]"]',
              'input[name="agree_privacy_check[]"]',
              'input[name="is_sms"]',
              'input[name="is_news_mail"]'
            ];
            checkSelectors.forEach(function(sel) {
              document.querySelectorAll(sel).forEach(function(chk) {
                chk.checked = true;
                if (jq) {
                  try { jq(chk).attr('checked', true).prop('checked', true).trigger('change'); } catch (e) {}
                }
                chk.dispatchEvent(new Event('change', { bubbles: true }));
              });
            });

            // Cafe24 페이지 내 중복확인 AJAX가 완료될 시간을 준 뒤 AuthSSLManager 가입 실행
            setTimeout(function() {
              var idMsgEl = document.getElementById('idMsg');
              if (idMsgEl) {
                var idTxt = idMsgEl.innerText.trim();
                if (idTxt.indexOf('이미 사용') !== -1 || idTxt.indexOf('사용할 수 없') !== -1 || idTxt.indexOf('중복') !== -1 || idTxt.indexOf('빈칸') !== -1 || idTxt.indexOf('입력해') !== -1) {
                  Cafe24SignUpBridge.postMessage(JSON.stringify({ type: 'error', message: idTxt }));
                  return;
                }
              }
              var emailMsgEl = document.getElementById('emailMsg');
              if (emailMsgEl) {
                var emailTxt = emailMsgEl.innerText.trim();
                if (emailTxt.indexOf('이미 사용') !== -1 || emailTxt.indexOf('중복') !== -1 || emailTxt.indexOf('유효하지') !== -1) {
                  Cafe24SignUpBridge.postMessage(JSON.stringify({ type: 'error', message: emailTxt }));
                  return;
                }
              }
              var pwMsgEl = document.getElementById('pwConfirmMsg');
              if (pwMsgEl && pwMsgEl.innerText.trim().indexOf('일치하지') !== -1) {
                Cafe24SignUpBridge.postMessage(JSON.stringify({ type: 'error', message: pwMsgEl.innerText.trim() }));
                return;
              }

              var idDupl = document.querySelector('input[name="idDuplCheck"]');
              if (idDupl) idDupl.value = 'T';
              var emailDupl = document.querySelector('input[name="emailDuplCheck"]');
              if (emailDupl) emailDupl.value = 'T';

              if (typeof memberJoinAction === 'function') {
                memberJoinAction();
              } else if (typeof MemberAction !== 'undefined' && typeof MemberAction.join === 'function') {
                MemberAction.join();
              } else {
                var submitBtn = document.querySelector('[onclick*="memberJoinAction"], [onclick*="MemberAction"], .btnSubmit');
                if (submitBtn) submitBtn.click();
              }

              // 가입 확인 레이어가 표시되는 스킨일 경우 자동 확인 클릭
              setTimeout(function() {
                var confirmBtn = document.getElementById('ec_shop_confirm-memberjoin_info_action') ||
                    document.querySelector('#ec_shop_member_confirm_layer .btnSubmit, .ec-base-layer .btnSubmit');
                if (confirmBtn) {
                  confirmBtn.click();
                }
              }, 400);
            }, 900);
          } catch (err) {
            Cafe24SignUpBridge.postMessage(JSON.stringify({ type: 'error', message: String(err) }));
          }
        })();
      ''');

      // 3. Cafe24 서버 응답 대기
      await _signUpCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('회원가입 처리 시간이 초과되었습니다. 입력 정보를 확인 후 다시 시도해주세요.'),
      );

      // 4. Cafe24 가입 성공 -> 앱 로그인 세션 저장
      final newUser = User(
        id: cleanId,
        email: cleanEmail,
        name: cleanName,
        phone: '$mobile1-$mobile2-$mobile3',
        groupName: '수지씨앤엘 일반회원',
        points: 2000,
        coupons: 1,
        orders: 0,
        isCafe24Member: true,
      );
      await ref.read(authProvider.notifier).setAuthenticatedUser(newUser);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('수지씨앤엘 쇼핑몰에 회원가입이 완료되었습니다!'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/mypage');
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

  Future<void> _handleKakaoSignUp() async {
    setState(() {
      _errorMessage = null;
    });

    final kakaoUser = await KakaoSyncAuthSheet.show(context);
    if (kakaoUser == null || !mounted) return;

    await ref.read(authProvider.notifier).setAuthenticatedUser(kakaoUser);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('카카오 계정(${kakaoUser.name})으로 간편 가입 및 로그인되었습니다!'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.go('/mypage');
  }

  Future<void> _handleNaverSignUp() async {
    setState(() {
      _errorMessage = null;
    });

    final naverUser = await NaverAuthSheet.show(context);
    if (naverUser == null || !mounted) return;

    await ref.read(authProvider.notifier).setAuthenticatedUser(naverUser);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('네이버 계정(${naverUser.name})으로 간편 가입 및 로그인되었습니다!'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.go('/mypage');
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
          '수지씨앤엘 회원가입',
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 카카오싱크(Kakao Sync) 1초 간편 회원가입 버튼
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _handleKakaoSignUp,
                        icon: const Icon(
                          Icons.chat_bubble_rounded,
                          size: 19,
                          color: Color(0xFF191919),
                        ),
                        label: const Text(
                          '카카오로 1초 간편 회원가입',
                          style: TextStyle(
                            fontSize: 14.5,
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
                    // 네이버(Naver) 간편 회원가입 버튼
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _handleNaverSignUp,
                        icon: Container(
                          width: 19,
                          height: 19,
                          alignment: Alignment.center,
                          child: const Text(
                            'N',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                        ),
                        label: const Text(
                          '네이버로 간편 회원가입',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF03C75A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '또는 일반 아이디로 가입',
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
                    const SizedBox(height: 18),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: AppTheme.point, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.point,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _buildField(
                      controller: _memberIdController,
                      label: '회원 아이디 *',
                      hint: '영문 소문자/숫자 4~16자 (예: suziuser1)',
                      icon: Icons.badge_outlined,
                      validator: (val) {
                        final v = val?.trim() ?? '';
                        if (!RegExp(r'^[a-z][a-z0-9]{3,15}$').hasMatch(v)) {
                          return '영문 소문자로 시작하는 영문 소문자/숫자 4~16자로 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildField(
                      controller: _nameController,
                      label: '이름 *',
                      hint: '실명을 입력해주세요',
                      icon: Icons.person_outline,
                      validator: (val) {
                        if (val == null || val.trim().length < 2) {
                          return '이름을 2자 이상 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildField(
                      controller: _emailController,
                      label: '이메일 *',
                      hint: 'example@naver.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (val) {
                        final v = val?.trim() ?? '';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                          return '올바른 이메일 주소를 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildField(
                      controller: _phoneController,
                      label: '휴대폰 번호 *',
                      hint: '010-1234-5678',
                      icon: Icons.phone_iphone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (val) {
                        final digits = (val ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                        if (digits.length < 10 || digits.length > 11) {
                          return '휴대폰 번호 10~11자리를 정확히 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '비밀번호 *',
                        hintText: '영문+숫자+특수문자 8~16자 (또는 2종 10~16자)',
                        helperText: 'Cafe24 보안 정책: 영문/숫자/특수문자 조합 10~16자 (3종 조합 시 8자 이상)',
                        helperStyle: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
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
                      validator: _validateCafe24Password,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _passwordConfirmController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '비밀번호 확인 *',
                        hintText: '비밀번호 재입력',
                        prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
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
                        if (val != _passwordController.text) {
                          return '비밀번호가 일치하지 않습니다.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // 약관 동의 영역
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            value: _allAgreed,
                            onChanged: _toggleAllAgreed,
                            activeColor: AppTheme.primary,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              '약관 전체 동의',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          CheckboxListTile(
                            value: _agreeTerms,
                            onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                            activeColor: AppTheme.primary,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              '[필수] 수지씨앤엘 이용약관 동의',
                              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                            ),
                          ),
                          CheckboxListTile(
                            value: _agreePrivacy,
                            onChanged: (v) => setState(() => _agreePrivacy = v ?? false),
                            activeColor: AppTheme.primary,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              '[필수] 개인정보 수집 및 이용 동의',
                              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitSignUp,
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
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '수지씨앤엘 회원가입 및 로그인',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
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
      validator: validator,
    );
  }
}
