import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/user.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';

class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final isLoggedIn = user != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          '마이페이지 / 설정',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              if (isLoggedIn) {
                _showLogoutDialog(context, ref);
              } else {
                context.push('/login');
              }
            },
            icon: Icon(
              isLoggedIn ? Icons.logout : Icons.login,
              size: 18,
              color: AppTheme.primary,
            ),
            label: Text(
              isLoggedIn ? '로그아웃' : '로그인',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: isLoggedIn
                  ? _buildLoggedInHeader(context, ref, user)
                  : _buildLoggedOutHeader(context, ref),
            ),
            if (isLoggedIn) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildQuickMenuGrid(context),
              ),
              const SizedBox(height: 16),
              _buildSettingSection(
                title: '내 정보 및 계정 관리',
                items: [
                  _SettingItem(
                    icon: Icons.account_circle_outlined,
                    title: '회원 정보 확인',
                    subtitle: '아이디, 이름, 연락처 및 Cafe24 연동 상태',
                    onTap: () => context.push('/profile'),
                  ),
                  _SettingItem(
                    icon: Icons.person_remove_outlined,
                    title: '회원탈퇴',
                    subtitle: '수지씨앤엘 쇼핑몰 계정 영구 삭제',
                    onTap: () => context.push('/withdrawal'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _buildSettingSection(
              title: '주문 및 배송 관리',
              items: [
                _SettingItem(
                  icon: Icons.local_shipping_outlined,
                  title: '주문/배송 조회',
                  subtitle: isLoggedIn ? '총 ${user.orders}건 진행 중' : null,
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.history_outlined,
                  title: '취소/반품/교환 내역',
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.location_on_outlined,
                  title: '배송지 관리',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSettingSection(
              title: '혜택 및 이벤트',
              items: [
                _SettingItem(
                  icon: Icons.confirmation_number_outlined,
                  title: '쿠폰함',
                  trailingText: isLoggedIn ? '${user.coupons}장 보유' : null,
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.monetization_on_outlined,
                  title: '포인트 관리',
                  trailingText: isLoggedIn ? '${user.points}P' : null,
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.card_giftcard_outlined,
                  title: '진행 중인 이벤트',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSettingSection(
              title: '앱 설정',
              items: [
                _SettingItem(
                  icon: Icons.notifications_none_outlined,
                  title: '알림 설정',
                  subtitle: '쇼핑 혜택 및 배송 알림 받기',
                  trailingWidget: Switch(
                    value: true,
                    activeColor: AppTheme.point,
                    onChanged: (val) {},
                  ),
                ),
                _SettingItem(
                  icon: Icons.dark_mode_outlined,
                  title: '다크 모드',
                  trailingWidget: Switch(
                    value: false,
                    onChanged: (val) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSettingSection(
              title: '고객센터 & 지원',
              items: [
                _SettingItem(
                  icon: Icons.campaign_outlined,
                  title: '공지사항',
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.help_outline,
                  title: '자주 묻는 질문 (FAQ)',
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.headset_mic_outlined,
                  title: '1:1 문의하기',
                  subtitle: '평일 09:00~17:00 (031-528-3266)',
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Icons.description_outlined,
                  title: '약관 및 개인정보 처리방침',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildAppInfoSection(context, ref, isLoggedIn),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInHeader(BuildContext context, WidgetRef ref, User user) {
    return Container(
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
        children: [
          InkWell(
            onTap: () => context.push('/profile'),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.chipBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 36,
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
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.chipBackground,
                                borderRadius: BorderRadius.circular(12),
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
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${user.id} · ${user.email}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 24,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryStatItem('주문내역', '${user.orders}건', Icons.shopping_bag_outlined),
                _buildVerticalDivider(),
                _buildSummaryStatItem('쿠폰', '${user.coupons}장', Icons.confirmation_number_outlined),
                _buildVerticalDivider(),
                _buildSummaryStatItem('포인트', '${user.points}P', Icons.monetization_on_outlined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedOutHeader(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppTheme.chipBackground,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              size: 36,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '로그인이 필요합니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '수지씨앤엘 Cafe24 회원으로 로그인하고\n적립금, 쿠폰, 실시간 주문 내역을 확인해 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                context.push('/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '로그인 / 회원가입',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {},
            child: const Text(
              '비회원 주문 조회',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildSummaryStatItem(String label, String value, IconData icon) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppTheme.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMenuGrid(BuildContext context) {
    final menus = [
      _QuickMenuItem(icon: Icons.favorite_border, label: '찜한 상품'),
      _QuickMenuItem(icon: Icons.history, label: '최근 본 상품'),
      _QuickMenuItem(icon: Icons.rate_review_outlined, label: '상품 후기'),
      _QuickMenuItem(icon: Icons.support_agent, label: '1:1 문의'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: menus.map((menu) {
          return InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.chipBackground,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Icon(menu.icon, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  menu.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingSection({
    required String title,
    required List<_SettingItem> items,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
          ...items.map((item) => Column(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.chipBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, size: 20, color: const Color(0xFF475569)),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    subtitle: item.subtitle != null
                        ? Text(
                            item.subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          )
                        : null,
                    trailing: item.trailingWidget ??
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.trailingText != null) ...[
                              Text(
                                item.trailingText!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.point,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                    onTap: item.onTap,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 60),
                    child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildAppInfoSection(
      BuildContext context, WidgetRef ref, bool isLoggedIn) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                '앱 버전',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              Text(
                'v1.0.0 (최신버전)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          if (isLoggedIn) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  _showLogoutDialog(context, ref);
                },
                icon: const Icon(Icons.logout, size: 18, color: Color(0xFF64748B)),
                label: const Text(
                  '로그아웃',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('안전하게 로그아웃되었습니다.'),
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
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailingWidget;
  final VoidCallback? onTap;

  _SettingItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailingWidget,
    this.onTap,
  });
}

class _QuickMenuItem {
  final IconData icon;
  final String label;

  _QuickMenuItem({required this.icon, required this.label});
}
