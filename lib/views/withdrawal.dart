import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 수지씨앤엘 쇼핑몰 회원탈퇴 페이지 (Cafe24 AuthSSL 연동)
class WithdrawalPage extends ConsumerStatefulWidget {
  const WithdrawalPage({super.key});

  @override
  ConsumerState<WithdrawalPage> createState() => _WithdrawalPageState();
}

enum _WithdrawStep {
  idle,
  loggingInToVerify,
  executingModifyDel,
}

class _WithdrawalPageState extends ConsumerState<WithdrawalPage> {
  static const String _loginForModifyUrl =
      'https://suzicnl.com/member/login.html?noMemberOrder&returnUrl=%2Fmember%2Fmodify.html';

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _customReasonController = TextEditingController();

  late final WebViewController _headlessController;
  bool _isLoginPageReady = false;
  Completer<void>? _pageReadyCompleter;
  Completer<bool>? _withdrawCompleter;
  _WithdrawStep _currentStep = _WithdrawStep.idle;

  final List<String> _reasons = const [
    '원하는 상품이나 재고가 부족해요',
    '배송·교환·환불 서비스가 아쉬워요',
    '쇼핑몰 이용 빈도가 낮아요',
    '개인정보 및 보안이 걱정돼요',
    '다른 쇼핑몰을 이용하려고 해요',
    '기타 (직접 입력)',
  ];

  String _selectedReason = '쇼핑몰 이용 빈도가 낮아요';
  bool _agreedNotice = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initHeadlessEngine();
  }

  Future<void> _initHeadlessEngine() async {
    _pageReadyCompleter = Completer<void>();

    _headlessController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24WithdrawBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {
        final msg = request.message.trim();
        debugPrint('[Withdrawal AuthSSL Alert] (step: $_currentStep) $msg');

        if (_withdrawCompleter == null || _withdrawCompleter!.isCompleted) {
          return;
        }

        // 탈퇴 완료 관련 알림인 경우 성공 처리
        final isSuccessAlert = msg.contains('탈퇴가 완료') ||
            msg.contains('회원탈퇴가') ||
            msg.contains('탈퇴 처리') ||
            msg.contains('탈퇴되었') ||
            msg.contains('이용해 주셔서 감사합니다') ||
            msg.contains(' 정상적으로 탈퇴');

        if (isSuccessAlert) {
          _withdrawCompleter!.complete(true);
          return;
        }

        // 그 외 알림(비밀번호 불일치, 진행 중 주문 존재 등)은 에러로 전달
        if (msg.isNotEmpty) {
          _withdrawCompleter!.completeError(Exception(msg));
          _resetLoginForm();
        }
      })
      ..setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async {
          debugPrint('[Withdrawal AuthSSL Confirm] ${request.message}');
          return true; // "정말로 탈퇴하시겠습니까?" 등 모든 confirm 대화상자 자동 승인
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('[Withdrawal AuthSSL Engine] Page finished: $url (step: $_currentStep)');

            if (url.contains('/member/login.html')) {
              _isLoginPageReady = true;
              if (_pageReadyCompleter != null &&
                  !_pageReadyCompleter!.isCompleted) {
                _pageReadyCompleter!.complete();
              }
              return;
            }

            if (_withdrawCompleter == null || _withdrawCompleter!.isCompleted) {
              return;
            }

            // 1단계(로그인 본인확인) 완료 후 /member/modify.html 도달 시 2단계(회원탈퇴 실행) 수행
            if (_currentStep == _WithdrawStep.loggingInToVerify) {
              if (url.contains('/member/modify.html')) {
                _currentStep = _WithdrawStep.executingModifyDel;
                _executeCafe24MemberDel();
              } else if (!url.contains('/exec/front/Member/login')) {
                // 메인 등으로 리다이렉트된 경우 /member/modify.html로 명시적 이동
                _headlessController.loadRequest(
                  Uri.parse('https://suzicnl.com/member/modify.html'),
                );
              }
              return;
            }

            // 2단계(회원탈퇴 실행) 후 메인 페이지(/index.html 등)로 리다이렉트되면 탈퇴 성공
            if (_currentStep == _WithdrawStep.executingModifyDel) {
              if (!url.contains('/member/modify.html') &&
                  !url.contains('/exec/front/Member/del')) {
                _withdrawCompleter!.complete(true);
              }
            }
          },
        ),
      );

    await WebViewCookieManager().clearCookies();
    await _headlessController.loadRequest(Uri.parse(_loginForModifyUrl));
  }

  void _resetLoginForm() {
    _currentStep = _WithdrawStep.idle;
    _isLoginPageReady = false;
    _pageReadyCompleter = Completer<void>();
    WebViewCookieManager().clearCookies().then((_) {
      _headlessController.loadRequest(Uri.parse(_loginForModifyUrl));
    });
  }

  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type']?.toString();
      final msg = data['message']?.toString() ?? '';

      if (type == 'error' && msg.isNotEmpty) {
        if (_withdrawCompleter != null && !_withdrawCompleter!.isCompleted) {
          _withdrawCompleter!.completeError(Exception(msg));
        }
        _resetLoginForm();
      } else if (type == 'success') {
        if (_withdrawCompleter != null && !_withdrawCompleter!.isCompleted) {
          _withdrawCompleter!.complete(true);
        }
      }
    } catch (_) {}
  }

  /// /member/modify.html 페이지 내에서 Cafe24 회원탈퇴(memberDelAction) 실행
  Future<void> _executeCafe24MemberDel() async {
    final password = _passwordController.text;
    final reason = _selectedReason == '기타 (직접 입력)' &&
            _customReasonController.text.trim().isNotEmpty
        ? _customReasonController.text.trim()
        : _selectedReason;

    final jsPw = jsonEncode(password);
    final jsReason = jsonEncode(reason);

    await _headlessController.runJavaScript('''
      (function() {
        try {
          var jq = window.jQuery || window.\$ || window.EC\$;
          var pwVal = $jsPw;
          var reasonVal = $jsReason;

          // 비밀번호 입력 필드에 값 설정 (본인 확인 및 탈퇴 레이어 대비)
          var pwInputs = document.querySelectorAll('input[name="passwd"], input[name="member_passwd"], #passwd, #del_passwd');
          pwInputs.forEach(function(el) {
            el.value = pwVal;
            if (jq) {
              try { jq(el).val(pwVal).trigger('change'); } catch (e) {}
            }
          });

          // 탈퇴 사유 입력 필드에 값 설정
          var reasonInputs = document.querySelectorAll('#leave_reason, [name="leave_reason"], [name="del_reason"]');
          reasonInputs.forEach(function(el) {
            el.value = reasonVal;
            if (jq) {
              try { jq(el).val(reasonVal).trigger('change'); } catch (e) {}
            }
          });

          // 1차: memberDelAction() 또는 탈퇴 버튼 호출
          if (typeof memberDelAction === 'function') {
            memberDelAction(-1);
          } else if (typeof MemberAction !== 'undefined' && typeof MemberAction.memberDel === 'function') {
            MemberAction.memberDel();
          } else {
            var delBtn = document.querySelector('[onclick*="memberDelAction"], [onclick*="memberDel"], a[href*="memberDel"]');
            if (delBtn) {
              delBtn.click();
            } else {
              Cafe24WithdrawBridge.postMessage(JSON.stringify({
                type: 'error',
                message: '쇼핑몰 회원탈퇴 양식을 찾을 수 없습니다.'
              }));
              return;
            }
          }

          // 2차: 탈퇴 사유 레이어(#ec_shop_member_del_layer 등)가 팝업된 경우 내부 필드 채우고 최종 탈퇴 실행
          setTimeout(function() {
            var layerPwInputs = document.querySelectorAll('input[name="passwd"], input[name="member_passwd"], #passwd, #del_passwd');
            layerPwInputs.forEach(function(el) {
              el.value = pwVal;
            });
            var layerReasonInputs = document.querySelectorAll('#leave_reason, [name="leave_reason"], [name="del_reason"]');
            layerReasonInputs.forEach(function(el) {
              el.value = reasonVal;
            });

            var confirmDelBtn = document.getElementById('ec_shop_confirm-memberdel_info_action') ||
                document.querySelector('#ec_shop_member_del_layer .btnSubmit, .ec-base-layer .btnSubmit, [onclick*="memberDelSubmit"], [onclick*="delMember"]');
            if (confirmDelBtn) {
              confirmDelBtn.click();
            }
          }, 500);
        } catch (err) {
          Cafe24WithdrawBridge.postMessage(JSON.stringify({
            type: 'error',
            message: String(err)
          }));
        }
      })();
    ''');
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSubmitWithdrawal(User user) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedNotice) {
      setState(() {
        _errorMessage = '회원탈퇴 유의사항 및 혜택 소멸 안내에 동의해주세요.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.point, size: 22),
            SizedBox(width: 8),
            Text(
              '정말 탈퇴하시겠습니까?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        content: Text(
          '탈퇴 시 ${user.name}(${user.id}) 회원님의 적립금 ${user.points}P와 쿠폰 ${user.coupons}장이 즉시 소멸되며 복구할 수 없습니다.\n\n수지씨앤엘 쇼핑몰에서 정말 탈퇴하시겠습니까?',
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF475569),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              '취소',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.point,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _executeWithdrawal(user);
  }

  Future<void> _executeWithdrawal(User user) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final password = _passwordController.text;

    try {
      // 1. 데모 테스트 계정(suzicnl1)인 경우 비밀번호(123456) 검증 후 로컬 세션 탈퇴 처리
      if (user.id == 'suzicnl1') {
        if (password != '123456') {
          throw Exception('비밀번호가 일치하지 않습니다.');
        }
        await Future.delayed(const Duration(milliseconds: 600));
        await ref.read(authProvider.notifier).withdrawAccount();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('회원탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다.'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/mypage');
        return;
      }

      // 2. 실제 Cafe24 회원: 백그라운드 AuthSSL 엔진 준비 확인
      if (!_isLoginPageReady && _pageReadyCompleter != null) {
        await _pageReadyCompleter!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('쇼핑몰 서버 연결이 지연되고 있습니다. 다시 시도해주세요.'),
        );
      }

      _withdrawCompleter = Completer<bool>();
      _currentStep = _WithdrawStep.loggingInToVerify;

      final jsId = jsonEncode(user.id);
      final jsPw = jsonEncode(password);

      // 3. 먼저 아이디/비밀번호로 AuthSSL 로그인을 수행하여 비밀번호 본인 확인 및 /member/modify.html 진입
      await _headlessController.runJavaScript('''
        (function() {
          try {
            var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
            var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
            if (!idEl || !pwEl) {
              Cafe24WithdrawBridge.postMessage(JSON.stringify({
                type: 'error',
                message: '본인 확인 양식을 불러오는 중입니다. 다시 시도해주세요.'
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
            Cafe24WithdrawBridge.postMessage(JSON.stringify({
              type: 'error',
              message: String(err)
            }));
          }
        })();
      ''');

      // 4. Cafe24 회원탈퇴 완료 대기
      await _withdrawCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('회원탈퇴 처리 시간이 초과되었습니다. 비밀번호 및 진행 중인 주문 여부를 확인해주세요.'),
      );

      // 5. 로컬 세션 및 쿠키 완전 파기
      await ref.read(authProvider.notifier).withdrawAccount();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('수지씨앤엘 쇼핑몰 회원탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다.'),
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.primary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '회원탈퇴',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
      ),
      body: user == null
          ? const Center(child: Text('로그인된 회원 정보가 없습니다.'))
          : Stack(
              children: [
                // 백그라운드 Cafe24 AuthSSLManager 실행용 비가시성(1x1) 엔진
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
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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

                          // 1. 소멸 예정 혜택 요약 카드
                          _buildForfeitSummaryCard(user),
                          const SizedBox(height: 16),

                          // 2. 탈퇴 유의사항 안내 카드
                          _buildNoticeCard(),
                          const SizedBox(height: 16),

                          // 3. 탈퇴 사유 선택 카드
                          _buildReasonCard(),
                          const SizedBox(height: 16),

                          // 4. 본인 확인 비밀번호 입력 및 동의 카드
                          _buildPasswordAndAgreementCard(user),
                          const SizedBox(height: 24),

                          // 5. 하단 취소 / 탈퇴 버튼
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: OutlinedButton(
                                    onPressed: _isSubmitting ? null : () => context.pop(),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primary,
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      '취소 (계속 이용)',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => _confirmAndSubmitWithdrawal(user),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.point,
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
                                            '회원탈퇴',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildForfeitSummaryCard(User user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.point, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${user.name}(${user.id}) 님의 소멸 예정 혜택',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        '소멸 예정 적립금',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user.points}P',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.point,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: const Color(0xFFFECACA)),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        '소멸 예정 쿠폰',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user.coupons}장',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.point,
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

  Widget _buildNoticeCard() {
    const notices = [
      '회원탈퇴 시 보유하신 적립금, 쿠폰 및 회원 등급 혜택은 즉시 소멸되며 복구되지 않습니다.',
      '진행 중인 주문, 배송, 교환 또는 반품 건이 있는 경우 모든 처리가 완료된 후 탈퇴가 가능합니다.',
      '전자상거래 등에서의 소비자보호에 관한 법률에 따라 계약·대금결제 및 재화 공급 등의 거래 기록은 법정 보관 기간 동안 보관됩니다.',
      '탈퇴 후 동일 아이디로 재가입이 제한될 수 있습니다.',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '회원탈퇴 유의사항',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...notices.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '탈퇴 사유 선택',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ..._reasons.map(
            (reason) => RadioListTile<String>(
              value: reason,
              groupValue: _selectedReason,
              activeColor: AppTheme.primary,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                reason,
                style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              ),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedReason = val);
                }
              },
            ),
          ),
          if (_selectedReason == '기타 (직접 입력)') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _customReasonController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: '기타 탈퇴 사유를 입력해주세요 (선택)',
                hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordAndAgreementCard(User user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '본인 확인 및 탈퇴 동의',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '안전한 회원탈퇴 처리를 위해 현재 계정의 비밀번호를 입력해주세요.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '현재 비밀번호 *',
              hintText: '비밀번호 입력',
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
            validator: (val) {
              if (val == null || val.isEmpty) {
                return '본인 확인을 위해 비밀번호를 입력해주세요.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _agreedNotice,
            onChanged: (v) => setState(() => _agreedNotice = v ?? false),
            activeColor: AppTheme.point,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              '[필수] 위 유의사항 및 혜택 소멸 안내를 모두 확인하였으며 회원탈퇴에 동의합니다.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

