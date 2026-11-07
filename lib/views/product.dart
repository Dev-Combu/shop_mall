import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/cart_item.dart';
import 'package:shopmall/models/order.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/models/product_option.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/cart_viewmodel.dart';
import 'package:shopmall/viewmodels/saved_products_viewmodel.dart';
import 'package:shopmall/views/share/cart_added_modal.dart';
import 'package:shopmall/views/share/product_detail_html_view.dart';
import 'package:shopmall/views/share/cafe24_checkout_launcher.dart';

/// 상품 상세 & 구매 페이지
///
/// GoRouter Shell 외부 라우트(`/products/:id`)로 등록되어,
/// BottomNavigationBar 없이 전체 화면으로 표시됩니다.
class ProductPage extends ConsumerStatefulWidget {
  final String productId;
  final Product? initialProduct;

  const ProductPage({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<ProductPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _quantity = 1;
  bool _isLoading = false;
  bool _detailLoaded = false; // 상세설명 조회 완료 여부
  List<_ReviewData> _liveReviews = [];

  // 상품 옵션 데이터 및 선택 상태
  ProductOptionsData? _optionsData;
  bool _loadingOptions = true;
  final Map<String, ProductOptionValue> _selectedRequiredOptions = {};
  final Map<String, ProductOptionValue> _selectedAdditionalOptions = {};

  // 상품 데이터 (전달받은 데이터 또는 ID로 조회)
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
    _product = widget.initialProduct ?? ProductDataService.findById(widget.productId);
    if (_product == null) {
      _fetchProductDetail();
    } else if (_product!.detailHtml.trim().isEmpty) {
      _fetchDetailHtml();
    } else {
      _detailLoaded = true;
    }
    _fetchReviews();
    _fetchOptions();
    _recordRecentView();
  }

  Future<void> _fetchOptions() async {
    try {
      final apiService = ref.read(cafe24ApiServiceProvider);
      final opt = await apiService.fetchProductOptions(widget.productId);
      if (mounted) {
        setState(() {
          _optionsData = opt;
          _loadingOptions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  int get _totalOptionAdditionalAmount {
    int sum = 0;
    for (final opt in _selectedRequiredOptions.values) {
      sum += opt.additionalAmount;
    }
    for (final opt in _selectedAdditionalOptions.values) {
      sum += opt.additionalAmount;
    }
    return sum;
  }

  int get _effectiveUnitSalePrice =>
      (_product?.salePrice ?? 0) + _totalOptionAdditionalAmount;

  List<String> get _selectedOptionsTextList {
    final list = <String>[];
    for (final entry in _selectedRequiredOptions.entries) {
      list.add('${entry.key}: ${entry.value.text}');
    }
    for (final entry in _selectedAdditionalOptions.entries) {
      list.add('[추가] ${entry.key}: ${entry.value.text}');
    }
    return list;
  }

  bool _validateRequiredOptions() {
    if (_optionsData != null && _optionsData!.requiredGroups.isNotEmpty) {
      for (final group in _optionsData!.requiredGroups) {
        if (group.isRequired && !_selectedRequiredOptions.containsKey(group.name)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('[필수] ${group.name} 옵션을 선택해주세요.'),
              backgroundColor: AppTheme.point,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return false;
        }
      }
    }
    return true;
  }

  /// 최근 본 상품에 기록 (빌드 이후 시점에 provider 갱신)
  void _recordRecentView() {
    Future.microtask(() {
      final p = _product;
      if (!mounted || p == null) return;
      ref.read(recentProvider.notifier).record(p);
    });
  }

  Future<void> _fetchReviews() async {
    try {
      final apiService = ref.read(cafe24ApiServiceProvider);
      final raw = await apiService.fetchProductReviews(widget.productId);
      if (raw.isNotEmpty && mounted) {
        setState(() {
          _liveReviews = raw.map((a) {
            return _ReviewData(
              name: a['writer']?.toString() ?? '구매고객',
              rating: int.tryParse(a['rating']?.toString() ?? '5') ?? 5,
              date: a['created_date']?.toString().split('T').first ?? '',
              comment: a['content']?.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim() ??
                  a['title']?.toString() ??
                  '만족스러운 구매였습니다.',
            );
          }).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchProductDetail() async {
    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(cafe24ApiServiceProvider);
      final p = await apiService.fetchProductDetail(widget.productId);
      if (p != null && mounted) {
        setState(() {
          _product = p;
          _isLoading = false;
          _detailLoaded = true;
        });
        _recordRecentView();
        return;
      }
    } catch (e) {
      debugPrint('[ProductPage] fetchProductDetail error: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 목록에서 전달받은 상품에 상세설명(HTML)이 없을 때 단건 조회로 보강
  Future<void> _fetchDetailHtml() async {
    try {
      final apiService = ref.read(cafe24ApiServiceProvider);
      final p = await apiService.fetchProductDetail(widget.productId);
      if (p != null && mounted) {
        final current = _product!;
        setState(() {
          _product = Product(
            id: current.id,
            name: current.name,
            originalPrice: current.originalPrice,
            discountRate: current.discountRate,
            tag: current.tag,
            tagColor: current.tagColor,
            category: current.category,
            icon: current.icon,
            imageUrl: current.imageUrl ?? p.imageUrl,
            description: current.description.isNotEmpty ? current.description : p.description,
            detailHtml: p.detailHtml,
            rating: current.rating,
            reviewCount: current.reviewCount,
            categoryNos: current.categoryNos,
            isNew: current.isNew,
            isRecommend: current.isRecommend,
            createdDate: current.createdDate,
          );
          _detailLoaded = true;
        });
        return;
      }
    } catch (e) {
      debugPrint('[ProductPage] fetchDetailHtml error: $e');
    }
    if (mounted) setState(() => _detailLoaded = true);
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('상품 정보')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
    final totalAmount = _effectiveUnitSalePrice * _quantity;
    final formattedTotal = '${_formatPrice(totalAmount)}원';

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
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () {
                  ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.cart);
                  context.go('/cart');
                },
              ),
              if (ref.watch(cartProvider).isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppTheme.point,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${ref.watch(cartProvider).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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

                // ── 옵션 선택 ──
                SliverToBoxAdapter(child: _buildOptionsSection(product)),

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
    final isFavorite = ref.watch(favoritesProvider).any((p) => p.id == product.id);
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 300,
          color: _bgGray,
          child: hasImage
              ? Image.network(
                  product.imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(product.icon, size: 120, color: const Color(0xFFBDBDBD)),
                    );
                  },
                )
              : Center(
                  child: Icon(
                    product.icon,
                    size: 120,
                    color: const Color(0xFFBDBDBD),
                  ),
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
            onTap: () => ref.read(favoritesProvider.notifier).toggle(product),
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
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? _red : _textGray,
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

  static String _formatPrice(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // ─── 옵션 선택 섹션 ───
  Widget _buildOptionsSection(Product product) {
    if (_loadingOptions) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('옵션 정보를 불러오는 중입니다...', style: TextStyle(fontSize: 13, color: _textGray)),
          ],
        ),
      );
    }

    final data = _optionsData;
    if (data == null || (data.requiredGroups.isEmpty && data.additionalGroups.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '옵션 선택',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark),
              ),
              const SizedBox(width: 6),
              if (data.requiredGroups.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.point.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '필수선택',
                    style: TextStyle(fontSize: 11, color: AppTheme.point, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. 본품 옵션 그룹
          ...data.requiredGroups.map((group) {
            final selected = _selectedRequiredOptions[group.name];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
                      ),
                      const SizedBox(width: 4),
                      if (group.isRequired)
                        const Text('*', style: TextStyle(color: AppTheme.point, fontWeight: FontWeight.bold))
                      else
                        const Text('(선택)', style: TextStyle(color: _textGray, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<ProductOptionValue?>(
                    value: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      hintText: group.isRequired
                          ? '${group.name} 선택 (필수)'
                          : '${group.name} (선택 안 함)',
                      hintStyle: const TextStyle(fontSize: 13, color: _textGray),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: selected != null ? AppTheme.primary : const Color(0xFFE0E0E0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                    ),
                    items: [
                      if (!group.isRequired)
                        const DropdownMenuItem<ProductOptionValue?>(
                          value: null,
                          child: Text(
                            '선택 안 함',
                            style: TextStyle(fontSize: 13, color: _textGray),
                          ),
                        ),
                      ...group.values.map((v) {
                        return DropdownMenuItem<ProductOptionValue?>(
                          value: v,
                          child: Text(
                            '${v.text}${v.formattedAdditionalAmount}',
                            style: const TextStyle(fontSize: 13, color: _textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        if (val != null) {
                          _selectedRequiredOptions[group.name] = val;
                        } else {
                          _selectedRequiredOptions.remove(group.name);
                        }
                      });
                    },
                  ),
                ],
              ),
            );
          }),

          // 2. 추가 상품 옵션 그룹
          if (data.additionalGroups.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  '추가 상품 선택',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '선택사항',
                    style: TextStyle(fontSize: 11, color: _textGray, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...data.additionalGroups.map((group) {
              final selected = _selectedAdditionalOptions[group.name];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<ProductOptionValue?>(
                      value: selected,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        hintText: '${group.name} (선택 안 함)',
                        hintStyle: const TextStyle(fontSize: 13, color: _textGray),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: selected != null ? AppTheme.primary : const Color(0xFFE0E0E0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<ProductOptionValue?>(
                          value: null,
                          child: Text(
                            '선택 안 함 (구매 안 함)',
                            style: TextStyle(fontSize: 13, color: _textGray),
                          ),
                        ),
                        ...group.values.map((v) {
                          return DropdownMenuItem<ProductOptionValue?>(
                            value: v,
                            child: Text(
                              '${v.text}${v.formattedAdditionalAmount}',
                              style: const TextStyle(fontSize: 13, color: _textDark),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          if (val == null) {
                            _selectedAdditionalOptions.remove(group.name);
                          } else {
                            _selectedAdditionalOptions[group.name] = val;
                          }
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          ],

          // 3. 선택된 옵션 요약 카드
          if (_selectedRequiredOptions.isNotEmpty || _selectedAdditionalOptions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '선택된 옵션 내역',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textDark),
                  ),
                  const SizedBox(height: 6),
                  ..._selectedRequiredOptions.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '[필수] ${e.key}: ',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark),
                            ),
                            Expanded(
                              child: Text(
                                '${e.value.text}${e.value.formattedAdditionalAmount}',
                                style: const TextStyle(fontSize: 12, color: _textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                  ..._selectedAdditionalOptions.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '[추가] ${e.key}: ',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                            ),
                            Expanded(
                              child: Text(
                                '${e.value.text}${e.value.formattedAdditionalAmount}',
                                style: const TextStyle(fontSize: 12, color: _textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedAdditionalOptions.remove(e.key);
                                });
                              },
                              child: const Icon(Icons.close, size: 16, color: _textGray),
                            ),
                          ],
                        ),
                      )),
                  if (_totalOptionAdditionalAmount > 0) ...[
                    const Divider(height: 12, color: Color(0xFFE5E7EB)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '옵션 추가금액 (개당)',
                          style: TextStyle(fontSize: 12, color: _textGray),
                        ),
                        Text(
                          '+${_formatPrice(_totalOptionAdditionalAmount)}원',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.point),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
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
        // 탭 내용 (상세정보 HTML은 높이가 가변이므로 선택된 탭만 렌더링)
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            if (_tabController.index == 0) return _buildDetailTab(product);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildReviewSummary(product),
                  const SizedBox(height: 16),
                  ..._buildSampleReviews(),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDetailTab(Product product) {
    final html = product.detailHtml.trim();
    if (html.isNotEmpty) {
      return ProductDetailHtmlView(key: ValueKey(product.id), html: html);
    }
    if (!_detailLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        product.description.trim().isNotEmpty
            ? product.description
            : '등록된 상세 설명이 없습니다.',
        style: const TextStyle(fontSize: 14, color: _textDark, height: 1.7),
      ),
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
    if (_liveReviews.isNotEmpty) {
      return _liveReviews.map((r) => _buildReviewItem(r)).toList();
    }
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
                if (_product == null) return;
                if (!_validateRequiredOptions()) return;
                addProductToCartWithModal(
                  context,
                  ref,
                  _product!,
                  quantity: _quantity,
                  selectedOptions: _selectedOptionsTextList,
                  optionAdditionalAmount: _totalOptionAdditionalAmount,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('장바구니 담기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          // 바로 구매 버튼
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                if (_product == null) return;
                if (!_validateRequiredOptions()) return;
                final checkoutArgs = CheckoutArgs(
                  items: [
                    CartItem(
                      product: _product!,
                      quantity: _quantity,
                      isSelected: true,
                      selectedOptions: _selectedOptionsTextList,
                      optionAdditionalAmount: _totalOptionAdditionalAmount,
                    ),
                  ],
                  fromCart: false,
                );
                launchCafe24Checkout(
                  context: context,
                  ref: ref,
                  args: checkoutArgs,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.point,
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
