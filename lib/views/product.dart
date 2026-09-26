import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';

/// 상품 상세 & 구매 페이지
///
/// GoRouter Shell 외부 라우트(`/products/:id`)로 등록되어,
/// BottomNavigationBar 없이 전체 화면으로 표시됩니다.
class ProductPage extends StatefulWidget {
  final String productId;

  const ProductPage({super.key, required this.productId});

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _quantity = 1;
  bool _isFavorite = false;

  // 상품 데이터 (ID로 조회)
  Product? _product;

  // 브랜드 색상
  static const _green = Color(0xFF4CAF50);
  static const _darkGreen = Color(0xFF388E3C);
  static const _red = Color(0xFFE53935);
  static const _textDark = Color(0xFF212121);
  static const _textGray = Color(0xFF9E9E9E);
  static const _bgGray = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _product = ProductDataService.findById(widget.productId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── 수량 조절 ───
  void _decreaseQty() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  void _increaseQty() {
    if (_quantity < 99) setState(() => _quantity++);
  }

  @override
  Widget build(BuildContext context) {
    // 상품을 찾을 수 없을 때
    if (_product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('상품 정보')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: _textGray),
              SizedBox(height: 16),
              Text(
                '상품 정보를 찾을 수 없습니다.',
                style: TextStyle(color: _textGray, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final product = _product!;
    final hasDiscount = product.discountRate > 0;
    final formattedTotal = product.formattedTotalPrice(_quantity);

    return Scaffold(
      backgroundColor: Colors.white,

      // ───────────── AppBar ─────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          product.category,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => context.go('/cart'),
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ───────────── Body ─────────────
      body: Column(
        children: [
          // 스크롤 가능 영역
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── 상품 이미지 영역 ──
                SliverToBoxAdapter(child: _buildImageSection(product)),

                // ── 상품 정보 영역 ──
                SliverToBoxAdapter(child: _buildInfoSection(product, hasDiscount)),

                // ── 구분선 ──
                const SliverToBoxAdapter(
                  child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                ),

                // ── 배송 정보 ──
                SliverToBoxAdapter(child: _buildShippingSection()),

                // ── 구분선 ──
                const SliverToBoxAdapter(
                  child: Divider(height: 8, thickness: 8, color: Color(0xFFF5F5F5)),
                ),

                // ── 수량 선택 ──
                SliverToBoxAdapter(child: _buildQuantitySection()),

                // ── 구분선 ──
                const SliverToBoxAdapter(
                  child: Divider(height: 8, thickness: 8, color: Color(0xFFF5F5F5)),
                ),

                // ── 탭 (상세정보 / 리뷰) ──
                SliverToBoxAdapter(child: _buildTabSection(product)),
              ],
            ),
          ),

          // ───────────── 하단 구매 버튼 ─────────────
          _buildBottomBar(formattedTotal),
        ],
      ),
    );
  }

  // ─── 이미지 영역 ───
  Widget _buildImageSection(Product product) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 300,
          color: _bgGray,
          child: Icon(
            product.icon,
            size: 120,
            color: const Color(0xFFBDBDBD),
          ),
        ),
        // 태그 뱃지
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: product.tagColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              product.tag,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // 찜하기 버튼
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() => _isFavorite = !_isFavorite),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? _red : _textGray,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── 상품 정보 영역 ───
  Widget _buildInfoSection(Product product, bool hasDiscount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상품명
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _textDark,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),

          // 별점 & 리뷰
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < product.rating.floor()
                      ? Icons.star
                      : (i < product.rating ? Icons.star_half : Icons.star_border),
                  size: 16,
                  color: const Color(0xFFFFC107),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${product.rating} (리뷰 ${product.reviewCount}개)',
                style: const TextStyle(fontSize: 13, color: _textGray),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 가격
          if (hasDiscount) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 할인율
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${product.discountRate}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 할인가
                Text(
                  product.formattedSalePrice,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 정가 (취소선)
            Text(
              product.formattedOriginalPrice,
              style: const TextStyle(
                fontSize: 14,
                color: _textGray,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ] else ...[
            Text(
              product.formattedSalePrice,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 배송 정보 ───
  Widget _buildShippingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          _buildInfoRow(Icons.local_shipping_outlined, '배송', '무료배송 | 평균 2~3일 이내'),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.inventory_2_outlined, '판매자', '수지씨앤엘 (직판)'),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.loop_outlined, '교환/반품', '배송완료 후 7일 이내 가능'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _textGray),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _textGray),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: _textDark),
          ),
        ),
      ],
    );
  }

  // ─── 수량 선택 ───
  Widget _buildQuantitySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          const Text(
            '수량',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textDark),
          ),
          const Spacer(),
          // 감소 버튼
          _QtyButton(
            icon: Icons.remove,
            onTap: _decreaseQty,
            enabled: _quantity > 1,
          ),
          Container(
            width: 48,
            alignment: Alignment.center,
            child: Text(
              '$_quantity',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
          ),
          // 증가 버튼
          _QtyButton(
            icon: Icons.add,
            onTap: _increaseQty,
            enabled: _quantity < 99,
          ),
        ],
      ),
    );
  }

  // ─── 탭 (상세정보 / 리뷰) ───
  Widget _buildTabSection(Product product) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: _darkGreen,
          unselectedLabelColor: _textGray,
          indicatorColor: _green,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '상세정보'),
            Tab(text: '리뷰'),
          ],
        ),
        // 탭 내용 (고정 높이 — SliverList 안에서 NeverScrollable 사용)
        SizedBox(
          height: 320,
          child: TabBarView(
            controller: _tabController,
            children: [
              // ── 상세정보 탭 ──
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상품 설명
                    Text(
                      product.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textDark,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 스펙 박스 (장식)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FBE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDCEDC8)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_outlined, color: _darkGreen, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '품질 보증 | KC 인증 완료 제품',
                              style: TextStyle(
                                fontSize: 13,
                                color: _darkGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── 리뷰 탭 ──
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 리뷰 요약
                    _buildReviewSummary(product),
                    const SizedBox(height: 16),
                    // 리뷰 샘플 목록
                    ..._buildSampleReviews(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReviewSummary(Product product) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 평점 숫자
          Column(
            children: [
              Text(
                '${product.rating}',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < product.rating.floor() ? Icons.star : Icons.star_border,
                    size: 14,
                    color: const Color(0xFFFFC107),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${product.reviewCount}개 리뷰',
                style: const TextStyle(fontSize: 11, color: _textGray),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // 별점 바
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final ratio = star == 5 ? 0.6 : (star == 4 ? 0.3 : 0.1 / (6 - star));
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star', style: const TextStyle(fontSize: 11, color: _textGray)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: const Color(0xFFE0E0E0),
                            color: const Color(0xFFFFC107),
                            minHeight: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSampleReviews() {
    final reviews = [
      _ReviewData(name: '김지은', rating: 5, date: '2026.09.10', comment: '품질이 정말 좋아요! 배송도 빠르고 포장도 꼼꼼했어요.'),
      _ReviewData(name: '박현수', rating: 4, date: '2026.09.05', comment: '가성비 최고입니다. 다음에도 구매할 예정이에요.'),
      _ReviewData(name: '이수민', rating: 5, date: '2026.08.28', comment: '색감이 사진과 동일하고 제품 만족도 높아요.'),
    ];
    return reviews.map((r) => _buildReviewItem(r)).toList();
  }

  Widget _buildReviewItem(_ReviewData r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: _green.withValues(alpha: 0.2),
                child: Text(
                  r.name[0],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark)),
              const Spacer(),
              Text(r.date, style: const TextStyle(fontSize: 11, color: _textGray)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < r.rating ? Icons.star : Icons.star_border,
                size: 13,
                color: const Color(0xFFFFC107),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            r.comment,
            style: const TextStyle(fontSize: 13, color: _textDark, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ─── 하단 구매 버튼 바 ───
  Widget _buildBottomBar(String formattedTotal) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          // 장바구니 버튼
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('장바구니에 담았습니다 (수량: $_quantity)'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF424242),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _darkGreen,
                side: const BorderSide(color: _darkGreen, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('장바구니', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          // 바로 구매 버튼
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                // 구매 완료 다이얼로그
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Text('주문 확인', style: TextStyle(fontWeight: FontWeight.bold)),
                    content: Text(
                      '${_product!.name}\n수량: $_quantity개\n결제 금액: $formattedTotal',
                      style: const TextStyle(height: 1.6),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('취소', style: TextStyle(color: _textGray)),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('주문이 완료되었습니다!'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: _green,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('구매하기', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                '바로 구매  $formattedTotal',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 수량 버튼 위젯 ───
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? const Color(0xFFBDBDBD) : const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? const Color(0xFF212121) : const Color(0xFFBDBDBD),
        ),
      ),
    );
  }
}

// ─── 리뷰 데이터 모델 ───
class _ReviewData {
  final String name;
  final int rating;
  final String date;
  final String comment;
  _ReviewData({
    required this.name,
    required this.rating,
    required this.date,
    required this.comment,
  });
}
