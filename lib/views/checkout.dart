import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/viewmodels/auth_viewmodel.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:shopmall/viewmodels/order_viewmodel.dart';
import 'package:shopmall/views/cafe24_order_webview.dart';
import 'package:shopmall/views/share/cafe24_checkout_launcher.dart';
import 'package:shopmall/views/share/postcode_search_sheet.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  final CheckoutArgs args;

  const CheckoutPage({
    super.key,
    required this.args,
  });

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _zipController;
  late final TextEditingController _addressController;
  late final TextEditingController _detailAddressController;
  late final TextEditingController _pointController;

  String _selectedDeliveryMemo = '문 앞에 놓아주세요';
  String _selectedPaymentMethod = '신용/체크카드';
  int _usedPoints = 0;
  bool _agreedTerms = false;
  bool _isSubmitting = false;

  static const List<String> _deliveryMemos = [
    '문 앞에 놓아주세요',
    '경비실에 맡겨주세요',
    '배송 전에 미리 연락바랍니다',
    '부재 시 택배함에 넣어주세요',
  ];

  static const List<({String label, IconData icon})> _paymentMethods = [
    (label: '신용/체크카드', icon: Icons.credit_card_rounded),
    (label: '카카오페이', icon: Icons.chat_bubble_rounded),
    (label: '네이버페이', icon: Icons.account_balance_wallet_rounded),
    (label: '무통장입금', icon: Icons.account_balance_rounded),
    (label: '테스트 결제 (가상 승인)', icon: Icons.verified_user_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider);
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '010-');
    _zipController = TextEditingController(text: user?.zipCode ?? '');
    _addressController = TextEditingController(text: user?.address1 ?? '');
    _detailAddressController = TextEditingController(text: user?.address2 ?? '');
    _pointController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _zipController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    _pointController.dispose();
    super.dispose();
  }

  void _applyAllPoints(int availablePoints, int maxPayable) {
    final usable = availablePoints.clamp(0, maxPayable);
    setState(() {
      _usedPoints = usable;
      _pointController.text = usable.toString();
    });
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('주문 상품 정보 및 결제 진행에 동의해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fullAddress =
          '[${_zipController.text.trim()}] ${_addressController.text.trim()} ${_detailAddressController.text.trim()}'
              .trim();

      // 주문 시 입력/수정한 배송지 주소를 회원 기본 배송지 정보에도 자동 반영
      await ref.read(authProvider.notifier).updateMemberAddress(
            zipCode: _zipController.text.trim(),
            address1: _addressController.text.trim(),
            address2: _detailAddressController.text.trim(),
            phone: _phoneController.text.trim(),
          );
      if (!mounted) return;

      final user = ref.read(authProvider);
      final isDemo = user?.id == 'suzicnl1';
      final isTestPayment = _selectedPaymentMethod.startsWith('테스트 결제');

      final OrderRecord orderRecord;

      if (isDemo || isTestPayment) {
        // 테스트 모드(가상 승인) 또는 데모 계정: 실제 PG 결제 없이 모의 승인 주문 생성
        orderRecord = await ref.read(orderProvider.notifier).placeDemoOrder(
              args: widget.args,
              recipientName: _nameController.text.trim(),
              recipientPhone: _phoneController.text.trim(),
              address: fullAddress,
              deliveryMemo: _selectedDeliveryMemo,
              paymentMethod: _selectedPaymentMethod,
            );
      } else {
        // 주문서 웹뷰 진입 전 Cafe24 회원 웹뷰 세션 유효성 검증 및 자동 복구
        final sessionOk = await ensureCheckoutWebSession(context, ref);
        if (!sessionOk || !mounted) {
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }

        CheckoutArgs effectiveArgs = widget.args;
        if (widget.args.fromCart) {
          final selectedIds = {for (final it in widget.args.items) it.product.id};
          final refreshedItems = ref
              .read(cartProvider)
              .where((it) => selectedIds.contains(it.product.id))
              .toList();
          if (refreshedItems.isNotEmpty) {
            effectiveArgs = CheckoutArgs(items: refreshedItems, fromCart: true);
          }
        }

        // 실제 Cafe24 공식 주문서 + PG 결제 웹뷰 진입
        final prefill = Cafe24OrderPrefill(
          recipientName: _nameController.text.trim(),
          recipientPhone: _phoneController.text.trim(),
          zipCode: _zipController.text.trim(),
          address1: _addressController.text.trim(),
          address2: _detailAddressController.text.trim(),
          deliveryMemo: _selectedDeliveryMemo,
          paymentMethod: _selectedPaymentMethod,
          usedPoints: _usedPoints,
        );

        final orderResult = await Cafe24OrderWebViewPage.open(
          context,
          args: effectiveArgs,
          prefill: prefill,
        );

        if (!mounted) return;

        // 사용자가 결제를 완료하지 않고 닫았거나 취소한 경우
        if (orderResult == null || orderResult.isCanceled) {
          unawaited(ref.read(cartProvider.notifier).refreshFromCafe24());
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(orderResult?.message ?? '주문 및 결제가 취소되었습니다.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        // 결제 승인 실패한 경우
        if (orderResult.isFailure) {
          unawaited(ref.read(cartProvider.notifier).refreshFromCafe24());
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '결제 실패: ${orderResult.message ?? '승인 과정에서 오류가 발생했습니다.'}',
              ),
              backgroundColor: AppTheme.point,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        final cafe24OrderId = orderResult.orderId!;

        // Cafe24 결제 완료 후 발급된 실제 주문번호로 주문 기록 및 상태 동기화
        orderRecord = await ref.read(orderProvider.notifier).recordCafe24Order(
              cafe24OrderId: cafe24OrderId,
              args: effectiveArgs,
              recipientName: _nameController.text.trim(),
              recipientPhone: _phoneController.text.trim(),
              address: fullAddress,
              deliveryMemo: _selectedDeliveryMemo,
              paymentMethod: _selectedPaymentMethod,
              usedPoints: _usedPoints,
            );
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      await _showOrderCompleteDialog(orderRecord);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주문 처리 중 오류가 발생했습니다: $e'),
          backgroundColor: AppTheme.point,
        ),
      );
    }
  }

  Future<void> _showOrderCompleteDialog(OrderRecord record) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final firstItemName = record.items.isNotEmpty
            ? record.items.first.product.name
            : '주문 상품';
        final itemSummary = record.items.length > 1
            ? '$firstItemName 외 ${record.items.length - 1}건'
            : firstItemName;

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: AppTheme.successLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppTheme.success,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '주문이 정상적으로 완료되었습니다!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '주문번호: ${record.orderId}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildCompleteInfoRow('주문상품', itemSummary),
                      const SizedBox(height: 8),
                      _buildCompleteInfoRow('받는분', '${record.recipientName} (${record.recipientPhone})'),
                      const SizedBox(height: 8),
                      _buildCompleteInfoRow('결제수단', record.paymentMethod),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),
                      _buildCompleteInfoRow(
                        '최종 결제금액',
                        '${CartSummary.format(record.finalPaidAmount)}원',
                        isHighlight: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.push('/orders/${record.orderId}');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '배송/주문 상세',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.home);
                          context.go('/');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '쇼핑 계속하기',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompleteInfoRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: isHighlight ? 14.5 : 12.5,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              color: isHighlight ? AppTheme.point : AppTheme.primary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final availablePoints = user?.points ?? 0;
    final items = widget.args.items;
    final finalPayableAmount =
        (widget.args.finalPrice - _usedPoints).clamp(0, 999999999);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppTheme.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.args.fromCart ? '주문/결제 (장바구니)' : '주문/결제 (바로구매)',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            letterSpacing: -0.4,
          ),
        ),
        centerTitle: true,
      ),
      body: items.isEmpty
          ? const Center(child: Text('주문할 상품이 없습니다.'))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // 1. 주문 상품 목록 섹션
                          _buildOrderItemsSection(items),
                          const SizedBox(height: 10),

                          // 2. 배송지 정보 입력 섹션
                          _buildShippingAddressSection(),
                          const SizedBox(height: 10),

                          // 3. 적립금/포인트 사용 섹션 (로그인 회원)
                          if (user != null) ...[
                            _buildPointsSection(availablePoints, widget.args.finalPrice),
                            const SizedBox(height: 10),
                          ],

                          // 4. 결제 수단 선택 섹션
                          _buildPaymentMethodSection(),
                          const SizedBox(height: 10),

                          // 5. 최종 결제 금액 요약 섹션
                          _buildPriceSummarySection(finalPayableAmount),
                          const SizedBox(height: 10),

                          // 6. 약관 동의 섹션
                          _buildAgreementSection(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),

                // 하단 결제하기 고정 바
                _buildBottomPayBar(finalPayableAmount),
              ],
            ),
    );
  }

  Widget _buildOrderItemsSection(List<CartItem> items) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '주문 상품 (${items.length}개)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.chipBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.args.fromCart ? '장바구니 선택상품' : '단품 바로구매',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map((item) {
            final product = item.product;
            final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 64,
                      height: 64,
                      color: AppTheme.chipBackground,
                      child: hasImage
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                product.icon,
                                size: 28,
                                color: const Color(0xFF94A3B8),
                              ),
                            )
                          : Icon(
                              product.icon,
                              size: 28,
                              color: const Color(0xFF94A3B8),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '수량 ${item.quantity}개 · ${CartSummary.format(item.totalPrice)}원',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildShippingAddressSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '배송지 정보',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _nameController,
            label: '받는 분 성함',
            hint: '이름을 입력하세요',
            validator: (val) =>
                (val == null || val.trim().isEmpty) ? '받는 분 성함을 입력해주세요.' : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _phoneController,
            label: '연락처',
            hint: '010-0000-0000',
            keyboardType: TextInputType.phone,
            validator: (val) =>
                (val == null || val.trim().length < 9) ? '올바른 연락처를 입력해주세요.' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _zipController,
                  label: '우편번호',
                  hint: '우편번호 검색을 눌러주세요',
                  readOnly: true,
                  onTap: _openPostcodeSearch,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _openPostcodeSearch,
                  icon: const Icon(Icons.search_rounded, size: 17),
                  label: const Text(
                    '우편번호 검색',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _addressController,
            label: '기본 주소',
            hint: '우편번호 검색 시 자동 입력됩니다',
            onTap: _addressController.text.isEmpty ? _openPostcodeSearch : null,
            validator: (val) =>
                (val == null || val.trim().isEmpty) ? '주소를 입력해주세요.' : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _detailAddressController,
            label: '상세 주소',
            hint: '동/호수 또는 상세 위치를 입력하세요',
          ),
          const SizedBox(height: 14),
          const Text(
            '배송 요청사항',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedDeliveryMemo,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            items: _deliveryMemos
                .map((memo) => DropdownMenuItem(
                      value: memo,
                      child: Text(memo, style: const TextStyle(fontSize: 13.5)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedDeliveryMemo = val);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openPostcodeSearch() async {
    final result = await showPostcodeSearchSheet(context);
    if (result != null && mounted) {
      setState(() {
        _zipController.text = result.zipCode;
        _addressController.text = result.address;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  Widget _buildPointsSection(int availablePoints, int maxPayable) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '적립금 / 포인트 사용',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                '보유 ${CartSummary.format(availablePoints)}P',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _pointController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    suffixText: 'P',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    final clamped = parsed.clamp(0, availablePoints.clamp(0, maxPayable));
                    setState(() {
                      _usedPoints = clamped;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _applyAllPoints(availablePoints, maxPayable),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  '전액사용',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '결제 수단',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _paymentMethods.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.8,
            ),
            itemBuilder: (context, index) {
              final method = _paymentMethods[index];
              final isSelected = _selectedPaymentMethod == method.label;

              return GestureDetector(
                onTap: () => setState(() => _selectedPaymentMethod = method.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method.icon,
                        size: 18,
                        color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        method.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppTheme.primary : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummarySection(int finalPayableAmount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '결제 금액',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          _buildPriceRow('총 상품금액', '${CartSummary.format(widget.args.totalOriginalPrice)}원'),
          const SizedBox(height: 8),
          _buildPriceRow(
            '상품 할인',
            '-${CartSummary.format(widget.args.totalDiscount)}원',
            valueColor: AppTheme.point,
          ),
          if (_usedPoints > 0) ...[
            const SizedBox(height: 8),
            _buildPriceRow(
              '포인트 사용',
              '-${CartSummary.format(_usedPoints)}원',
              valueColor: AppTheme.success,
            ),
          ],
          const SizedBox(height: 8),
          _buildPriceRow(
            '배송비',
            widget.args.shippingFee == 0
                ? '0원 (무료배송)'
                : '+${CartSummary.format(widget.args.shippingFee)}원',
            valueColor: widget.args.shippingFee == 0 ? AppTheme.success : null,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '최종 결제금액',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                '${CartSummary.format(finalPayableAmount)}원',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.point,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildAgreementSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Checkbox(
            value: _agreedTerms,
            activeColor: AppTheme.primary,
            onChanged: (val) => setState(() => _agreedTerms = val ?? false),
          ),
          const Expanded(
            child: Text(
              '주문할 상품의 상품명, 가격, 배송정보를 확인하였으며 결제 진행에 동의합니다. (필수)',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPayBar(int finalPayableAmount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.point,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
                    : Text(
                        '${CartSummary.format(finalPayableAmount)}원 결제하기',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedPaymentMethod.startsWith('테스트 결제')
                  ? '실제 결제 승인 없이 테스트용 주문 데이터가 즉시 생성됩니다.'
                  : 'Cafe24 공식 결제 시스템을 통해 안전하게 결제됩니다.',
              style: TextStyle(
                fontSize: 11.5,
                color: _selectedPaymentMethod.startsWith('테스트 결제')
                    ? AppTheme.point
                    : const Color(0xFF94A3B8),
                fontWeight: _selectedPaymentMethod.startsWith('테스트 결제')
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

