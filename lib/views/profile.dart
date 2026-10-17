import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 수지씨앤엘 쇼핑몰 회원 정보 확인 및 상세 조회 페이지
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const String _modifyUrl = 'https://suzicnl.com/member/modify.html';

  late final WebViewController _syncController;
  Completer<void>? _syncCompleter;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _initProfileSyncEngine();
  }

  /// 백그라운드에서 Cafe24 회원정보 수정 페이지(/member/modify.html) 및 마이쇼핑(/myshop/index.html)을 조회하여
  /// 휴대폰 번호(mobile[]), 이메일(email1), 실명(name), 적립금, 쿠폰을 최신 상태로 동기화
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
            if (url.contains('/member/modify.html')) {
              _extractFromModifyPage();
            } else if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
              _syncCompleter!.complete();
            }
          },
        ),
      );

    // 페이지 진입 시 자동으로 Cafe24 서버에서 최신 전화번호/이메일/적립금 동기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider);
      if (user != null && user.id != 'suzicnl1') {
        _syncController.loadRequest(Uri.parse(_modifyUrl));
      }
    });
  }

  /// Cafe24의 /member/modify.html은 개인정보(휴대폰 번호, 이메일, 실명)를 페이지 로드 후
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
              setTimeout(checkDecryptedFields, 200);
              return;
            }

            fetch('/myshop/index.html', { credentials: 'include' })
              .then(function(res) { return res.text(); })
              .then(function(html) {
                var parser = new DOMParser();
                var doc = parser.parseFromString(html, 'text/html');
                var groupEl = doc.querySelector('.xans-myshop-asyncbenefit .group, .xans-member-var-group_name');
                var pointEl = doc.querySelector('#xans_myshop_bankbook_avail_mileage, .avail_mileage');
                var couponEl = doc.querySelector('#xans_myshop_bankbook_coupon_cnt, .couponCount');

                Cafe24ProfileBridge.postMessage(JSON.stringify({
                  name: nameVal,
                  email: emailVal,
                  phone: phoneStr,
                  groupName: groupEl ? groupEl.innerText.trim() : '',
                  points: pointEl ? pointEl.innerText.replace(/[^0-9]/g, '') : '',
                  coupons: couponEl ? couponEl.innerText.replace(/[^0-9]/g, '') : ''
                }));
              })
              .catch(function() {
                Cafe24ProfileBridge.postMessage(JSON.stringify({
                  name: nameVal,
                  email: emailVal,
                  phone: phoneStr,
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
      final syncedName = data['name']?.toString().trim() ?? '';
      final syncedEmail = data['email']?.toString().trim() ?? '';
      final syncedPhone = data['phone']?.toString().trim() ?? '';
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
          const Text(
            '기본 회원 정보',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
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
          _buildInfoRow(
            label: '회원 등급',
            value: user.groupName,
            icon: Icons.workspace_premium_outlined,
          ),
        ],
      ),
    );
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
