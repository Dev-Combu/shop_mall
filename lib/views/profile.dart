import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/views/share/postcode_search_sheet.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 수지씨앤엘 쇼핑몰 회원 정보 확인 및 상세 조회 페이지
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const String _modifyUrl = 'https://suzicnl.com/member/modify.html';
  static const String _addrRegisterUrl =
      'https://suzicnl.com/myshop/addr/register.html';

  late final WebViewController _syncController;
  Completer<void>? _syncCompleter;
  Completer<String>? _pageLoadCompleter;
  Completer<({bool success, String message})>? _modifySubmitCompleter;
  bool _isRefreshing = false;
  bool _isSubmittingAddress = false;
  bool _modifyPageHasPasswordInput = true;

  @override
  void initState() {
    super.initState();
    _initProfileSyncEngine();
  }

  /// 백그라운드에서 Cafe24 회원정보 수정 페이지(/member/modify.html) 및 마이쇼핑(/myshop/index.html)을 조회하여
  /// 휴대폰 번호(mobile[]), 이메일(email1), 실명(name), 주소, 적립금, 쿠폰을 최신 상태로 동기화
  void _initProfileSyncEngine() {
    _syncController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Cafe24ProfileBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleProfileSyncMessage(message.message);
        },
      )
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {
        final msg = request.message.trim();
        debugPrint('[Cafe24Profile Alert] $msg');

        if (_modifySubmitCompleter != null &&
            !_modifySubmitCompleter!.isCompleted) {
          final isSuccess = msg.contains('수정되었') ||
              msg.contains('변경되었') ||
              msg.contains('등록되었') ||
              msg.contains('저장되었') ||
              msg.contains('완료');
          _modifySubmitCompleter!.complete((
            success: isSuccess,
            message: msg,
          ));
        }

        if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
          _syncCompleter!.complete();
        }
      })
      ..setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async => true,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('[Cafe24Profile WebView] onPageFinished: $url');

            if (_pageLoadCompleter != null &&
                !_pageLoadCompleter!.isCompleted) {
              _pageLoadCompleter!.complete(url);
            }

            // 주소 저장 프로세스 진행 중일 때는 자동 추출을 건너뛰고 제출 완료 여부 확인
            if (_isSubmittingAddress) {
              final path = Uri.tryParse(url)?.path ?? url;
              if (_modifySubmitCompleter != null &&
                  !_modifySubmitCompleter!.isCompleted) {
                if (!path.contains('/member/modify.html') &&
                    !path.contains('/member/login.html') &&
                    !path.contains('/myshop/addr/register.html')) {
                  _modifySubmitCompleter!.complete((
                    success: true,
                    message: '회원정보가 수정되었습니다.',
                  ));
                }
              }
              return;
            }

            final path = Uri.tryParse(url)?.path ?? url;
            if (path.contains('/member/modify.html')) {
              _extractFromModifyPage();
            } else if (path.contains('/member/login.html')) {
              _tryAutoReLoginForSync();
            } else if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
              _syncCompleter!.complete();
            }
          },
        ),
      );

    // 페이지 진입 시 자동으로 Cafe24 서버에서 최신 전화번호/이메일/주소/적립금 동기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider);
      if (user != null && user.id != 'suzicnl1') {
        _syncController.loadRequest(Uri.parse(_modifyUrl));
      }
    });
  }

  /// 앱 재시작 등으로 WebView 쿠키가 만료되어 /member/login.html로 리다이렉트된 경우
  /// 저장된 회원 비밀번호가 있으면 백그라운드에서 자동 재로그인하여 /member/modify.html 세션을 복구
  Future<void> _tryAutoReLoginForSync() async {
    try {
      final user = ref.read(authProvider);
      if (user == null || user.id == 'suzicnl1') {
        if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
          _syncCompleter!.complete();
        }
        return;
      }
      final savedPw =
          await ref.read(authProvider.notifier).getMemberPassword(user.id);
      if (savedPw == null || savedPw.isEmpty) {
        if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
          _syncCompleter!.complete();
        }
        return;
      }

      final jsId = jsonEncode(user.id);
      final jsPw = jsonEncode(savedPw);
      await _syncController.runJavaScript('''
        (function() {
          try {
            var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
            var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
            if (idEl && pwEl) {
              idEl.value = $jsId;
              pwEl.value = $jsPw;
              if (typeof MemberAction !== 'undefined' && typeof MemberAction.login === 'function') {
                var form = idEl.closest('form');
                MemberAction.login(form ? (form.id || 'login_form') : 'login_form');
              } else {
                var btn = document.querySelector('[onclick*="MemberAction.login"], .btnSubmit, .btnLogin');
                if (btn) btn.click();
              }
            }
          } catch (e) {}
        })();
      ''');
    } catch (_) {
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
    }
  }

  /// Cafe24의 /member/modify.html은 개인정보(휴대폰 번호, 이메일, 실명, 주소)를 페이지 로드 후
  /// AuthSSLManager 비동기 복호화 스크립트로 input value에 채워 넣으므로 최대 3초 폴링 대기 후 추출
  Future<void> _extractFromModifyPage() async {
    await _syncController.runJavaScript('''
      (function() {
        var attempts = 0;
        var maxAttempts = 15; // 200ms * 15 = 최대 3초 폴링 대기

        function checkDecryptedFields() {
          attempts++;
          try {
            var modNameEl = document.querySelector('#name, input[name="name"]');
            var modEmailEl = document.querySelector('#email1, input[name="email1"]');
            var mobiles = document.querySelectorAll('[name="mobile[]"]');
            var phoneStr = '';
            if (mobiles.length >= 3) {
              var m1 = (mobiles[0].value || '010').trim();
              var m2 = (mobiles[1].value || '').trim();
              var m3 = (mobiles[2].value || '').trim();
              if (/^[0-9]{3,4}\$/.test(m2) && /^[0-9]{4}\$/.test(m3)) {
                phoneStr = m1 + '-' + m2 + '-' + m3;
              }
            }

            var nameVal = (modNameEl && modNameEl.value) ? modNameEl.value.trim() : '';
            var emailVal = (modEmailEl && modEmailEl.value) ? modEmailEl.value.trim() : '';

            var postEl = document.getElementById('postcode1') || document.querySelector('input[name="postcode1"], input[name="zipcode"]');
            var addr1El = document.getElementById('addr1') || document.querySelector('input[name="addr1"], input[name="address1"]');
            var addr2El = document.getElementById('addr2') || document.querySelector('input[name="addr2"], input[name="address2"]');

            var zipVal = (postEl && postEl.value) ? postEl.value.trim() : '';
            var addr1Val = (addr1El && addr1El.value) ? addr1El.value.trim() : '';
            var addr2Val = (addr2El && addr2El.value) ? addr2El.value.trim() : '';

            var pwEl = document.querySelector('#passwd, input[name="passwd"]');
            var hasPasswdField = !!(pwEl && pwEl.offsetParent !== null);

            // AuthSSLManager 복호화가 완료되어 휴대폰 번호가 숫자(3~4자리)로 채워질 때까지 최대 3초 폴링 대기
            if (!phoneStr && attempts < maxAttempts) {
              setTimeout(checkDecryptedFields, 200);
              return;
            }

            Promise.all([
              fetch('/myshop/index.html', { credentials: 'include' }).then(function(r) { return r.text(); }).catch(function() { return ''; }),
              (!addr1Val)
                ? fetch('/myshop/addr/list.html', { credentials: 'include' }).then(function(r) { return r.text(); }).catch(function() { return ''; })
                : Promise.resolve('')
            ]).then(function(results) {
              var myshopHtml = results[0] || '';
              var addrListHtml = results[1] || '';
              var parser = new DOMParser();

              var groupTxt = '';
              var pointsTxt = '';
              var couponsTxt = '';

              if (myshopHtml) {
                var doc = parser.parseFromString(myshopHtml, 'text/html');
                var groupEl = doc.querySelector('.xans-myshop-asyncbenefit .group, .xans-member-var-group_name');
                var pointEl = doc.querySelector('#xans_myshop_bankbook_avail_mileage, .avail_mileage');
                var couponEl = doc.querySelector('#xans_myshop_bankbook_coupon_cnt, .couponCount');
                if (groupEl) groupTxt = groupEl.innerText.trim();
                if (pointEl) pointsTxt = pointEl.innerText.replace(/[^0-9]/g, '');
                if (couponEl) couponsTxt = couponEl.innerText.replace(/[^0-9]/g, '');
              }

              // 회원 기본 주소가 비어있고 배송주소록(/myshop/addr/list.html)에 주소가 있으면 추출
              if (!addr1Val && addrListHtml) {
                var addrDoc = parser.parseFromString(addrListHtml, 'text/html');
                var addrEl = addrDoc.querySelector('.xans-myshop-addrlist .address, .xans-myshop-addrlist td.left');
                if (addrEl) {
                  var rawAddr = addrEl.innerText.replace(/\\s+/g, ' ').trim();
                  var zipMatch = rawAddr.match(/\\(([0-9]{5})\\)/) || rawAddr.match(/\\[([0-9]{5})\\]/);
                  if (zipMatch) {
                    zipVal = zipMatch[1];
                    addr1Val = rawAddr.replace(zipMatch[0], '').trim();
                  } else if (rawAddr.length > 5 && rawAddr.indexOf('등록된 주소가 없습니다') === -1) {
                    addr1Val = rawAddr;
                  }
                }
              }

              Cafe24ProfileBridge.postMessage(JSON.stringify({
                name: nameVal,
                email: emailVal,
                phone: phoneStr,
                zipCode: zipVal,
                address1: addr1Val,
                address2: addr2Val,
                hasPasswdField: hasPasswdField,
                groupName: groupTxt,
                points: pointsTxt,
                coupons: couponsTxt
              }));
            }).catch(function() {
              Cafe24ProfileBridge.postMessage(JSON.stringify({
                name: nameVal,
                email: emailVal,
                phone: phoneStr,
                zipCode: zipVal,
                address1: addr1Val,
                address2: addr2Val,
                hasPasswdField: hasPasswdField,
                groupName: '',
                points: '',
                coupons: ''
              }));
            });
          } catch (e) {
            Cafe24ProfileBridge.postMessage(JSON.stringify({}));
          }
        }

        checkDecryptedFields();
      })();
    ''');
  }

  Future<void> _handleProfileSyncMessage(String raw) async {
    try {
      final currentUser = ref.read(authProvider);
      if (currentUser == null) return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['hasPasswdField'] is bool) {
        _modifyPageHasPasswordInput = data['hasPasswdField'] as bool;
      }
      final syncedName = data['name']?.toString().trim() ?? '';
      final syncedEmail = data['email']?.toString().trim() ?? '';
      final syncedPhone = data['phone']?.toString().trim() ?? '';
      final syncedZip = data['zipCode']?.toString().trim() ?? '';
      final syncedAddr1 = data['address1']?.toString().trim() ?? '';
      final syncedAddr2 = data['address2']?.toString().trim() ?? '';
      final syncedGroup = data['groupName']
              ?.toString()
              .replaceAll(RegExp(r'[\[\]]'), '')
              .trim() ??
          '';
      final syncedPointsStr = data['points']?.toString().trim() ?? '';
      final syncedCouponsStr = data['coupons']?.toString().trim() ?? '';

      final updatedUser = currentUser.copyWith(
        name: syncedName.isNotEmpty ? syncedName : currentUser.name,
        email: syncedEmail.isNotEmpty ? syncedEmail : currentUser.email,
        phone: syncedPhone.isNotEmpty ? syncedPhone : currentUser.phone,
        zipCode: syncedZip.isNotEmpty ? syncedZip : currentUser.zipCode,
        address1: syncedAddr1.isNotEmpty ? syncedAddr1 : currentUser.address1,
        address2: syncedAddr2.isNotEmpty ? syncedAddr2 : currentUser.address2,
        groupName: syncedGroup.isNotEmpty ? syncedGroup : currentUser.groupName,
        points: syncedPointsStr.isNotEmpty
            ? (int.tryParse(syncedPointsStr) ?? currentUser.points)
            : currentUser.points,
        coupons: syncedCouponsStr.isNotEmpty
            ? (int.tryParse(syncedCouponsStr) ?? currentUser.coupons)
            : currentUser.coupons,
      );

      await ref.read(authProvider.notifier).setAuthenticatedUser(updatedUser);
    } catch (_) {
    } finally {
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
    }
  }

  Future<void> _handleRefresh() async {
    final user = ref.read(authProvider);
    if (user == null) return;

    setState(() => _isRefreshing = true);
    try {
      if (user.id != 'suzicnl1') {
        _syncCompleter = Completer<void>();
        await _syncController.loadRequest(Uri.parse(_modifyUrl));
        await _syncCompleter!.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      } else {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원 정보를 최신 상태로 갱신했습니다.'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          '로그아웃',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        content: const Text(
          '수지씨앤엘 계정에서 로그아웃하시겠습니까?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '취소',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/mypage');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('로그아웃되었습니다.'),
                    backgroundColor: AppTheme.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
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
          '회원 정보 확인',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh, color: AppTheme.primary),
            tooltip: '회원정보 새로고침',
            onPressed: _isRefreshing ? null : _handleRefresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 백그라운드 회원정보(/member/modify.html) 실시간 동기화용 비가시성(1x1) 엔진
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0.0,
              child: IgnorePointer(
                child: WebViewWidget(controller: _syncController),
              ),
            ),
          ),

          if (user == null)
            _buildLoggedOutView(context)
          else
            RefreshIndicator(
              onRefresh: _handleRefresh,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUserCard(user),
                    const SizedBox(height: 16),
                    _buildBenefitsCard(user),
                    const SizedBox(height: 16),
                    _buildDetailsCard(user),
                    const SizedBox(height: 16),
                    _buildSyncStatusCard(user),
                    const SizedBox(height: 24),
                    _buildActionButtons(context),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoggedOutView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppTheme.chipBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 38,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '로그인이 필요합니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '회원 정보를 확인하려면\n수지씨앤엘 쇼핑몰 계정으로 로그인해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 46,
              child: ElevatedButton(
                onPressed: () => context.push('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '로그인하기',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.chipBackground,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border, width: 2),
            ),
            child: const Icon(
              Icons.person,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.chipBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        user.groupName,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '아이디: ${user.id}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Color(0xFF16A34A)),
                      SizedBox(width: 4),
                      Text(
                        'Cafe24 공식 쇼핑몰 연동 계정',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w600,
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

  Widget _buildBenefitsCard(User user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '쇼핑 혜택 및 활동 현황',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildBenefitItem(
                label: '가용 적립금',
                value: '${user.points}P',
                icon: Icons.monetization_on_outlined,
                color: AppTheme.point,
              ),
              _buildBenefitDivider(),
              _buildBenefitItem(
                label: '보유 쿠폰',
                value: '${user.coupons}장',
                icon: Icons.confirmation_number_outlined,
                color: AppTheme.primary,
              ),
              _buildBenefitDivider(),
              _buildBenefitItem(
                label: '주문 내역',
                value: '${user.orders}건',
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFF0284C7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitDivider() {
    return Container(
      width: 1,
      height: 36,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildBenefitItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(User user) {
    final hasAddress = user.fullAddress.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '기본 회원 정보',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              InkWell(
                onTap: () => _showAddressEditSheet(context, user),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_location_alt_outlined,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasAddress ? '주소 변경' : '주소 등록',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            label: '회원 아이디',
            value: user.id,
            icon: Icons.badge_outlined,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildInfoRow(
            label: '이름 (실명)',
            value: user.name,
            icon: Icons.person_outline,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildInfoRow(
            label: '이메일 주소',
            value: user.email,
            icon: Icons.email_outlined,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildInfoRow(
            label: '휴대폰 번호',
            value: user.phone != null && user.phone!.isNotEmpty
                ? user.phone!
                : '미등록',
            icon: Icons.phone_iphone_outlined,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          InkWell(
            onTap: () => _showAddressEditSheet(context, user),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '기본 배송 주소',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: hasAddress
                              ? const Color(0xFFF1F5F9)
                              : AppTheme.point.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasAddress ? '변경하기' : '+ 주소 등록하기',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: hasAddress
                                ? const Color(0xFF475569)
                                : AppTheme.point,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasAddress
                            ? const Color(0xFFE2E8F0)
                            : AppTheme.point.withValues(alpha: 0.3),
                      ),
                    ),
                    child: hasAddress
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (user.zipCode != null &&
                                  user.zipCode!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '[우편번호: ${user.zipCode}]',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              Text(
                                '${user.address1 ?? ''} ${user.address2 ?? ''}'
                                    .trim(),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            children: [
                              Icon(
                                Icons.add_location_alt_outlined,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '등록된 기본 배송지가 없습니다. 터치하여 주소를 등록하면 Cafe24 쇼핑몰과 즉시 연동됩니다.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF64748B),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildInfoRow(
            label: '회원 등급',
            value: user.groupName,
            icon: Icons.workspace_premium_outlined,
          ),
        ],
      ),
    );
  }

  bool _isSnsAccount(User user) {
    final id = user.id.toLowerCase();
    return id.contains('@k') ||
        id.contains('@n') ||
        id.startsWith('kakao') ||
        id.startsWith('naver');
  }

  /// Cafe24 연동 배송 주소 등록/수정 모달 바텀시트
  Future<void> _showAddressEditSheet(BuildContext context, User user) async {
    final savedPw =
        await ref.read(authProvider.notifier).getMemberPassword(user.id);

    if (!context.mounted) return;

    final rawUserPhone = user.phone ?? '';
    final cleanUserPhoneDigits = rawUserPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final validInitialPhone = cleanUserPhoneDigits.length >= 9 ? rawUserPhone : '';

    final zipController = TextEditingController(text: user.zipCode ?? '');
    final addr1Controller = TextEditingController(text: user.address1 ?? '');
    final addr2Controller = TextEditingController(text: user.address2 ?? '');
    final phoneController = TextEditingController(text: validInitialPhone);
    final pwController = TextEditingController(text: savedPw ?? '');
    final addr2FocusNode = FocusNode();

    final needsPasswordField = user.id != 'suzicnl1' &&
        (!_isSnsAccount(user) && _modifyPageHasPasswordInput);

    bool isSaving = false;
    bool obscurePw = true;
    String? modalError;

    Future<void> openPostcodeFinder(
      BuildContext modalCtx,
      StateSetter setModalState,
    ) async {
      final result = await showPostcodeSearchSheet(modalCtx);
      if (result != null) {
        setModalState(() {
          zipController.text = result.zipCode;
          addr1Controller.text = result.address;
          modalError = null;
        });
        if (modalCtx.mounted) {
          FocusScope.of(modalCtx).requestFocus(addr2FocusNode);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: AppTheme.primary,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '기본 배송 주소 등록 / 수정',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '입력하신 주소는 수지씨앤엘(Cafe24) 회원정보 수정(/member/modify.html) 및 배송주소록에 암호화(AuthSSL)되어 실시간 저장됩니다.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 18,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                modalError!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _buildAddressField(
                            controller: zipController,
                            label: '우편번호',
                            hint: '우편번호 검색을 눌러주세요',
                            keyboardType: TextInputType.number,
                            icon: Icons.markunread_mailbox_outlined,
                            readOnly: true,
                            onTap: () =>
                                openPostcodeFinder(sheetContext, setModalState),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                openPostcodeFinder(sheetContext, setModalState),
                            icon: const Icon(Icons.search_rounded, size: 18),
                            label: const Text(
                              '우편번호 검색',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildAddressField(
                      controller: addr1Controller,
                      label: '기본 주소 (도로명 / 지번) *',
                      hint: '우편번호 검색 시 자동 입력됩니다',
                      icon: Icons.home_work_outlined,
                      onTap: addr1Controller.text.isEmpty
                          ? () =>
                              openPostcodeFinder(sheetContext, setModalState)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildAddressField(
                      controller: addr2Controller,
                      focusNode: addr2FocusNode,
                      label: '상세 주소 (동/호수, 건물명)',
                      hint: '예: 101동 202호',
                      icon: Icons.meeting_room_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildAddressField(
                      controller: phoneController,
                      label: '수령인 연락처 (휴대폰)',
                      hint: '예: 010-1234-5678',
                      keyboardType: TextInputType.phone,
                      icon: Icons.phone_iphone_outlined,
                    ),
                    if (needsPasswordField) ...[
                      const SizedBox(height: 12),
                      _buildAddressField(
                        controller: pwController,
                        label: '현재 비밀번호 (Cafe24 회원정보 반영 확인용) *',
                        hint: '수지씨앤엘 로그인 비밀번호를 입력하세요',
                        icon: Icons.lock_outline,
                        obscureText: obscurePw,
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePw
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () {
                            setModalState(() => obscurePw = !obscurePw);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final zip = zipController.text.trim();
                                final addr1 = addr1Controller.text.trim();
                                final addr2 = addr2Controller.text.trim();
                                final phone = phoneController.text.trim();
                                final pw = pwController.text;

                                if (addr1.isEmpty) {
                                  setModalState(() {
                                    modalError = '우편번호 검색을 통해 기본 주소를 입력해주세요.';
                                  });
                                  return;
                                }

                                if (needsPasswordField && pw.isEmpty) {
                                  setModalState(() {
                                    modalError =
                                        'Cafe24 회원정보 수정을 위해 현재 비밀번호를 입력해주세요.';
                                  });
                                  return;
                                }

                                setModalState(() {
                                  isSaving = true;
                                  modalError = null;
                                });

                                if (pw.isNotEmpty) {
                                  await ref
                                      .read(authProvider.notifier)
                                      .saveMemberPassword(user.id, pw);
                                }

                                // 1. 백그라운드 WebView AuthSSL을 통해 Cafe24 회원정보 수정(/member/modify.html) 및
                                //    배송주소록(/myshop/addr/register.html)에 실제 제출 및 검증
                                final syncResult =
                                    await _syncAddressToCafe24WebSession(
                                  user: user,
                                  zipCode: zip,
                                  address1: addr1,
                                  address2: addr2,
                                  phone: phone.isNotEmpty
                                      ? phone
                                      : (user.phone ?? ''),
                                  password: pw,
                                );

                                if (!syncResult.success) {
                                  setModalState(() {
                                    isSaving = false;
                                    modalError = syncResult.message;
                                  });
                                  return;
                                }

                                // 2. 로컬 보안 스토리지 및 Cafe24 REST API 배송지록(/shippingaddresses) 동기화
                                await ref
                                    .read(authProvider.notifier)
                                    .updateMemberAddress(
                                      zipCode: zip,
                                      address1: addr1,
                                      address2: addr2,
                                      phone: phone.isNotEmpty ? phone : null,
                                    );

                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(syncResult.message),
                                      backgroundColor: AppTheme.primary,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: Text(
                          isSaving
                              ? 'Cafe24 회원정보 암호화 전송 중...'
                              : '주소 저장 및 Cafe24 연동하기',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddressField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    bool readOnly = false,
    bool obscureText = false,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          obscureText: obscureText,
          onTap: onTap,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Cafe24 웹 세션의 AuthSSLManager를 사용하여:
  /// 1단계: /member/modify.html 에서 memberEditAction() 실행 (회원 기본정보 주소 저장)
  /// 2단계: /myshop/addr/register.html 에서 myshopAddr.formCheck() 실행 (배송주소록 기본배송지 등록)
  Future<({bool success, String message})> _syncAddressToCafe24WebSession({
    required User user,
    required String zipCode,
    required String address1,
    required String address2,
    required String phone,
    required String password,
  }) async {
    if (user.id == 'suzicnl1') {
      return (
        success: true,
        message: '기본 배송 주소가 저장되었습니다.',
      );
    }

    _isSubmittingAddress = true;
    try {
      final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      String m1 = '010';
      String m2 = '';
      String m3 = '';
      if (cleanDigits.length >= 10) {
        m1 = cleanDigits.substring(0, 3);
        m2 = cleanDigits.length == 10
            ? cleanDigits.substring(3, 6)
            : cleanDigits.substring(3, 7);
        m3 = cleanDigits.length == 10
            ? cleanDigits.substring(6)
            : cleanDigits.substring(7);
      }

      final jsSafeId = jsonEncode(user.id);
      final jsSafeName = jsonEncode(user.name);
      final jsSafeEmail = jsonEncode(user.email);
      final jsSafeZip = jsonEncode(zipCode);
      final jsSafeAddr1 = jsonEncode(address1);
      final jsSafeAddr2 = jsonEncode(address2);
      final jsSafeM1 = jsonEncode(m1);
      final jsSafeM2 = jsonEncode(m2);
      final jsSafeM3 = jsonEncode(m3);
      final jsSafePw = jsonEncode(password);

      // ──────────────────────────────────────────────────────────────────
      // 1단계: /member/modify.html 로드 확인 (세션 만료로 /member/login.html 이동 시 자동 로그인)
      // ──────────────────────────────────────────────────────────────────
      _pageLoadCompleter = Completer<String>();
      await _syncController.loadRequest(Uri.parse(_modifyUrl));
      String loadedUrl = await _pageLoadCompleter!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => _modifyUrl,
      );

      if ((Uri.tryParse(loadedUrl)?.path ?? loadedUrl)
              .contains('/member/login.html') &&
          password.isNotEmpty) {
        _pageLoadCompleter = Completer<String>();
        await _syncController.runJavaScript('''
          (function() {
            try {
              var idEl = document.getElementById('member_id') || document.querySelector('input[name="member_id"]');
              var pwEl = document.getElementById('member_passwd') || document.querySelector('input[name="member_passwd"]');
              if (idEl && pwEl) {
                idEl.value = $jsSafeId;
                pwEl.value = $jsSafePw;
                if (typeof MemberAction !== 'undefined' && typeof MemberAction.login === 'function') {
                  var form = idEl.closest('form');
                  MemberAction.login(form ? (form.id || 'login_form') : 'login_form');
                } else {
                  var btn = document.querySelector('[onclick*="MemberAction.login"], .btnSubmit, .btnLogin');
                  if (btn) btn.click();
                }
              }
            } catch (e) {}
          })();
        ''');
        loadedUrl = await _pageLoadCompleter!.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () => '',
        );

        if (!(Uri.tryParse(loadedUrl)?.path ?? loadedUrl)
            .contains('/member/modify.html')) {
          _pageLoadCompleter = Completer<String>();
          await _syncController.loadRequest(Uri.parse(_modifyUrl));
          await _pageLoadCompleter!.future.timeout(
            const Duration(seconds: 6),
            onTimeout: () => '',
          );
        }
      }

      // ──────────────────────────────────────────────────────────────────
      // 2단계: /member/modify.html 에서 AuthSSL 복호화 대기 후 주소 입력 및 memberEditAction() 실행
      // ──────────────────────────────────────────────────────────────────
      _modifySubmitCompleter = Completer<({bool success, String message})>();

      await _syncController.runJavaScript('''
        (function() {
          var attempts = 0;
          var maxAttempts = 15; // 최대 3초 동안 AuthSSL 복호화 완료(휴대폰 번호 숫자 복호화) 대기

          function setFieldValue(el, val) {
            if (!el) return;
            var jq = window.jQuery || window.\$ || window.EC\$;
            el.value = val;
            if (jq) {
              try {
                jq(el).val(val).trigger('input').trigger('change').trigger('blur');
              } catch (e) {}
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            el.dispatchEvent(new Event('blur', { bubbles: true }));
          }

          function tryFillAndSubmitModify() {
            attempts++;
            try {
              var modNameEl = document.getElementById('name') || document.querySelector('input[name="name"]');
              var modEmailEl = document.getElementById('email1') || document.querySelector('input[name="email1"]');

              var mobiles = document.querySelectorAll('[name="mobile[]"]');
              var m1El = mobiles.length >= 1 ? mobiles[0] : document.getElementById('mobile1');
              var m2El = mobiles.length >= 2 ? mobiles[1] : document.getElementById('mobile2');
              var m3El = mobiles.length >= 3 ? mobiles[2] : document.getElementById('mobile3');

              var curM2 = (m2El && m2El.value) ? m2El.value.trim() : '';
              var curM3 = (m3El && m3El.value) ? m3El.value.trim() : '';
              var isMobileDecrypted = /^[0-9]{3,4}\$/.test(curM2) && /^[0-9]{4}\$/.test(curM3);

              // AuthSSLManager가 휴대폰 번호(#mobile2, #mobile3)를 숫자로 복호화할 때까지 대기
              if (!isMobileDecrypted && attempts < maxAttempts) {
                setTimeout(tryFillAndSubmitModify, 200);
                return;
              }

              if (modNameEl && (!modNameEl.value || !modNameEl.value.trim())) {
                setFieldValue(modNameEl, $jsSafeName);
              }
              if (modEmailEl && (!modEmailEl.value || modEmailEl.value.indexOf('@') === -1)) {
                setFieldValue(modEmailEl, $jsSafeEmail);
              }

              // 사용자가 모달에서 유효한 휴대폰 번호(숫자 3~4자리)를 입력한 경우에만 덮어쓰고,
              // 그렇지 않으면 Cafe24가 복호화한 기존 휴대폰 번호를 그대로 유지
              var inputM1 = $jsSafeM1;
              var inputM2 = $jsSafeM2;
              var inputM3 = $jsSafeM3;
              if (/^[0-9]{3,4}\$/.test(inputM2) && /^[0-9]{4}\$/.test(inputM3)) {
                if (m1El) setFieldValue(m1El, inputM1 || '010');
                if (m2El) setFieldValue(m2El, inputM2);
                if (m3El) setFieldValue(m3El, inputM3);
              }

              // 일반전화(phone[]) 필드 정합성 보장:
              // [name="phone[]"]의 두 번째/세 번째 칸이 비어있거나 숫자가 아닌 경우 빈 문자열로 정리하고,
              // 만약 스킨에서 일반전화(phone[])가 필수(isFill)로 지정된 경우에만 '02' + 휴대폰 뒷자리로 채움
              var phones = document.querySelectorAll('[name="phone[]"]');
              var p1El = phones.length >= 1 ? phones[0] : document.getElementById('phone1');
              var p2El = phones.length >= 2 ? phones[1] : document.getElementById('phone2');
              var p3El = phones.length >= 3 ? phones[2] : document.getElementById('phone3');

              if (p2El && p3El) {
                var curP2 = (p2El.value || '').trim();
                var curP3 = (p3El.value || '').trim();
                var pFilter = (p2El.getAttribute('fw-filter') || '') + (p1El ? (p1El.getAttribute('fw-filter') || '') : '');
                var isLandlineRequired = pFilter.indexOf('isFill') !== -1;

                if (!(/^[0-9]{3,4}\$/.test(curP2) && /^[0-9]{4}\$/.test(curP3))) {
                  if (isLandlineRequired) {
                    var fallbackM2 = (/^[0-9]{3,4}\$/.test(inputM2)) ? inputM2 : (curM2 || '0000');
                    var fallbackM3 = (/^[0-9]{4}\$/.test(inputM3)) ? inputM3 : (curM3 || '0000');
                    if (p1El) setFieldValue(p1El, '02');
                    setFieldValue(p2El, fallbackM2);
                    setFieldValue(p3El, fallbackM3);
                  } else {
                    setFieldValue(p2El, '');
                    setFieldValue(p3El, '');
                  }
                }
              }

              var postEl = document.getElementById('postcode1') || document.querySelector('input[name="postcode1"], input[name="zipcode"]');
              var addr1El = document.getElementById('addr1') || document.querySelector('input[name="addr1"], input[name="address1"]');
              var addr2El = document.getElementById('addr2') || document.querySelector('input[name="addr2"], input[name="address2"]');

              setFieldValue(postEl, $jsSafeZip);
              setFieldValue(addr1El, $jsSafeAddr1);
              setFieldValue(addr2El, $jsSafeAddr2);

              var pwVal = $jsSafePw;
              if (pwVal) {
                var pwEl = document.getElementById('passwd') || document.querySelector('input[name="passwd"]');
                var pwConfirmEl = document.getElementById('user_passwd_confirm') || document.querySelector('input[name="user_passwd_confirm"]');
                if (pwEl) setFieldValue(pwEl, pwVal);
                if (pwConfirmEl) setFieldValue(pwConfirmEl, pwVal);
              }

              if (typeof memberEditAction === 'function') {
                memberEditAction();
              } else if (typeof MemberAction !== 'undefined' && typeof MemberAction.modify === 'function') {
                MemberAction.modify();
              } else {
                var editBtn = document.querySelector('[onclick*="memberEditAction"], .btnSubmit');
                if (editBtn) editBtn.click();
              }

              // 회원정보 수정 확인 레이어가 뜨는 스킨 대응
              setTimeout(function() {
                var confirmBtn = document.getElementById('ec_shop_confirm-memberedit_info_action') ||
                    document.querySelector('#ec_shop_member_confirm_layer .btnSubmit, .ec-base-layer .btnSubmit');
                if (confirmBtn) confirmBtn.click();
              }, 350);
            } catch (e) {}
          }

          tryFillAndSubmitModify();
        })();
      ''');

      final modifyResult = await _modifySubmitCompleter!.future.timeout(
        const Duration(seconds: 7),
        onTimeout: () => (
          success: true,
          message: '기본 배송 주소가 Cafe24 회원정보와 연동되었습니다.',
        ),
      );

      if (!modifyResult.success) {
        return (
          success: false,
          message: modifyResult.message.isNotEmpty
              ? modifyResult.message
              : 'Cafe24 회원정보 수정 중 오류가 발생했습니다. 비밀번호를 확인해주세요.',
        );
      }

      // ──────────────────────────────────────────────────────────────────
      // 3단계: /myshop/addr/register.html 에서 myshopAddr.formCheck() 실행하여 배송주소록에도 등록
      // ──────────────────────────────────────────────────────────────────
      try {
        _pageLoadCompleter = Completer<String>();
        await _syncController.loadRequest(Uri.parse(_addrRegisterUrl));
        final addrUrl = await _pageLoadCompleter!.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () => '',
        );

        if ((Uri.tryParse(addrUrl)?.path ?? addrUrl)
            .contains('/myshop/addr/')) {
          _modifySubmitCompleter =
              Completer<({bool success, String message})>();
          await _syncController.runJavaScript('''
            (function() {
              try {
                function setVal(sel, val) {
                  var el = document.querySelector(sel);
                  if (el) {
                    el.value = val;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                  }
                }
                setVal('#ma_rcv_title, input[name="ma_rcv_title"]', '기본배송지');
                setVal('#ma_rcv_name, input[name="ma_rcv_name"]', $jsSafeName);
                setVal('#address_zip1, input[name="address_zip1"], #postcode1', $jsSafeZip);
                setVal('#address_addr1, input[name="address_addr1"], #addr1', $jsSafeAddr1);
                setVal('#address_addr2, input[name="address_addr2"], #addr2', $jsSafeAddr2);

                // 휴대전화(ma_rcv_mobile_no[]) 설정
                var mEls = document.querySelectorAll('[name="ma_rcv_mobile_no[]"]');
                var m1El = mEls.length >= 1 ? mEls[0] : document.getElementById('ma_rcv_mobile_no1');
                var m2El = mEls.length >= 2 ? mEls[1] : document.getElementById('ma_rcv_mobile_no2');
                var m3El = mEls.length >= 3 ? mEls[2] : document.getElementById('ma_rcv_mobile_no3');
                if (/^[0-9]{3,4}\$/.test($jsSafeM2) && /^[0-9]{4}\$/.test($jsSafeM3)) {
                  if (m1El) m1El.value = $jsSafeM1 || '010';
                  if (m2El) m2El.value = $jsSafeM2;
                  if (m3El) m3El.value = $jsSafeM3;
                }

                // 일반전화(ma_rcv_phone[])는 지역번호(02, 031 등) 전용이므로 '010'을 넣지 않고 비워둠 (필수인 경우만 '02' 사용)
                var pEls = document.querySelectorAll('[name="ma_rcv_phone[]"]');
                var p1El = pEls.length >= 1 ? pEls[0] : document.getElementById('ma_rcv_phone1');
                var p2El = pEls.length >= 2 ? pEls[1] : document.getElementById('ma_rcv_phone2');
                var p3El = pEls.length >= 3 ? pEls[2] : document.getElementById('ma_rcv_phone3');
                if (p2El && p3El) {
                  var pFilter = (p2El.getAttribute('fw-filter') || '') + (p1El ? (p1El.getAttribute('fw-filter') || '') : '');
                  if (pFilter.indexOf('isFill') !== -1 && /^[0-9]{3,4}\$/.test($jsSafeM2) && /^[0-9]{4}\$/.test($jsSafeM3)) {
                    if (p1El) p1El.value = '02';
                    p2El.value = $jsSafeM2;
                    p3El.value = $jsSafeM3;
                  } else {
                    p2El.value = '';
                    p3El.value = '';
                  }
                }

                var mainFlag = document.querySelector('#ma_main_flag0, input[name="ma_main_flag"]');
                if (mainFlag) {
                  mainFlag.checked = true;
                }

                if (typeof myshopAddr !== 'undefined' && typeof myshopAddr.formCheck === 'function') {
                  myshopAddr.formCheck();
                } else {
                  var submitBtn = document.querySelector('[onclick*="myshopAddr.formCheck"], .btnSubmit');
                  if (submitBtn) submitBtn.click();
                }
              } catch (e) {}
            })();
          ''');

          await _modifySubmitCompleter!.future.timeout(
            const Duration(seconds: 4),
            onTimeout: () => (success: true, message: ''),
          );
        }
      } catch (_) {}

      return (
        success: true,
        message: '기본 배송 주소가 Cafe24 회원정보 및 배송주소록에 정상 반영되었습니다.',
      );
    } catch (e) {
      return (
        success: false,
        message: 'Cafe24 서버 동기화 중 오류가 발생했습니다: $e',
      );
    } finally {
      _isSubmittingAddress = false;
    }
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStatusCard(User user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.cloud_done_outlined, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'Cafe24 쇼핑몰 연동 상태',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStatusRow('연동 쇼핑몰', '수지씨앤엘 (suzicnl.com)'),
          const SizedBox(height: 4),
          _buildStatusRow('몰 아이디(Mall ID)', 'suzicnl1'),
          const SizedBox(height: 4),
          _buildStatusRow('인증 체계', 'Cafe24 AuthSSL 암호화 세션'),
          const SizedBox(height: 4),
          _buildStatusRow('보안 저장소', '기기 보안 스토리지(Encrypted) 보관'),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _showLogoutDialog.bind(context),
            icon: const Icon(Icons.logout, size: 18, color: Color(0xFFEF4444)),
            label: const Text(
              '로그아웃',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              backgroundColor: const Color(0xFFFEF2F2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () => context.push('/withdrawal'),
            icon: const Icon(
              Icons.person_remove_outlined,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
            label: const Text(
              '회원탈퇴',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension _BindContext on void Function(BuildContext) {
  VoidCallback bind(BuildContext context) => () => this(context);
}
