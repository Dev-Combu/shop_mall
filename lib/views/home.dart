import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/home_products_viewmodel.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  int _currentBannerIndex = 0;
  final PageController _bannerController = PageController();

  // 메인 배너: 수지씨앤엘 실제 전문 품목 (미끄럼방지매트, 행사장 매트 대량문의, 롤매트/인조잔디)
  final List<_BannerItem> _banners = [
    _BannerItem(
      tag: '안전 사고 예방',
      title: '미끄럼방지 안전매트\n공간별 맞춤 솔루션',
      subtitle: '욕실 · 현관 · 수영장 · 사업장 미끄럼 방지',
      bgColor: const Color(0xFF0F172A),
      icon: Icons.shield_outlined,
    ),
    _BannerItem(
      tag: '기업 · 관공서 특판',
      title: '행사장 · 공사장 바닥재\n대량 주문 및 견적 안내',
      subtitle: '파이텍스, 파단매트, 야자매트 도매 직공급',
      bgColor: const Color(0xFF1E293B),
      icon: Icons.domain_rounded,
    ),
    _BannerItem(
      tag: '공장 직영 출고',
      title: '원하는 길이 맞춤 재단\n프리미엄 롤매트 & 인조잔디',
      subtitle: '친환경 무독성 인증 · 당일 퀵/화물 배송',
      bgColor: const Color(0xFF1E3A5F),
      icon: Icons.grass_rounded,
    ),
  ];

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newProductsAsync = ref.watch(newProductsProvider);
    final bestProductsAsync = ref.watch(bestProductsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          '수지씨앤엘',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.primary),
            onPressed: () => context.push('/search'),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary),
                onPressed: () => ref
                    .read(bottomNavProvider.notifier)
                    .setIndex(BottomNavIndex.cart),
              ),
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
                  child: const Center(
                    child: Text(
                      '3',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // 1. 메인 배너 (미끄럼방지매트, 행사장 매트 대량문의 등)
            _buildMainBanner(),
            const SizedBox(height: 20),

            // 2. 카테고리 퀵 메뉴 (기존 UI 스타일의 단정하고 편안한 원형 메뉴)
            _buildCategoryQuickMenu(),
            const SizedBox(height: 28),

            // 3. 신상품 (NEW PRODUCT)
            _buildSectionHeader('신상품', 'NEW PRODUCT', () {
              final uri = Uri(path: '/category/products', queryParameters: {'name': '신상품'});
              context.push(uri.toString());
            }),
            const SizedBox(height: 12),
            _buildProductSection(newProductsAsync),
            const SizedBox(height: 32),

            // 4. 베스트 상품 (BEST MAT TOP 10)
            _buildSectionHeader('베스트 상품', 'BEST MAT TOP', () {
              final uri = Uri(path: '/category/products', queryParameters: {'name': '베스트'});
              context.push(uri.toString());
            }),
            const SizedBox(height: 12),
            _buildProductSection(bestProductsAsync),
            const SizedBox(height: 32),

            // 5. 기타 추천 상품 (OTHER - 갈대발, 마포걸레, 데크타일 등)
            _buildOtherRecommendedSection(),
            const SizedBox(height: 32),

            // 6. 이벤트 배너 (EVENT - 대량구매 / 무료견적)
            _buildEventBanner(),
            const SizedBox(height: 32),

            // 7. 실시간 베스트 리뷰 (REVIEW)
            _buildRealtimeReviewSection(),
            const SizedBox(height: 32),

            // 고객센터 푸터 바
            _buildCustomerServiceBar(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 1. 메인 배너: 차분하고 신뢰감 있는 다크 네이비 톤
  Widget _buildMainBanner() {
    return SizedBox(
      height: 195,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            itemCount: _banners.length,
            onPageChanged: (index) => setState(() => _currentBannerIndex = index),
            itemBuilder: (context, index) {
              final banner = _banners[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: banner.bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                banner.tag,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              banner.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.35,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              banner.subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: () {
                                ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.category);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '바로가기',
                                      style: TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 14,
                                      color: AppTheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        banner.icon,
                        size: 72,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _banners.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentBannerIndex == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentBannerIndex == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. 카테고리 퀵 메뉴: 기존 UI와 유사한 정갈한 서클 아이콘 (과한 3D/그라디언트 배제)
  Widget _buildCategoryQuickMenu() {
    final items = [
      _QuickCategoryItem(
        label: '롤매트',
        categoryNo: 181,
        icon: Icons.view_column_rounded,
      ),
      _QuickCategoryItem(
        label: '인조잔디',
        categoryNo: 44,
        icon: Icons.grass_rounded,
      ),
      _QuickCategoryItem(
        label: '현관발매트',
        categoryNo: 42,
        icon: Icons.door_front_door_rounded,
      ),
      _QuickCategoryItem(
        label: '청소용품',
        categoryNo: 45,
        icon: Icons.cleaning_services_rounded,
      ),
      _QuickCategoryItem(
        label: '기타·생활',
        categoryNo: 46,
        icon: Icons.grid_view_rounded,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((item) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final targetName = item.label == '기타·생활' ? '생활 주방용품' : item.label;
              final uri = Uri(
                path: '/category/products',
                queryParameters: {
                  'name': targetName,
                  if (item.categoryNo != null) 'no': item.categoryNo.toString(),
                },
              );
              context.push(uri.toString());
            },
            child: SizedBox(
              width: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.chipBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Icon(
                      item.icon,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155),
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String engSub, VoidCallback onMore) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              engSub,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onMore,
            child: const Row(
              children: [
                Text('더보기', style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8))),
                Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection(AsyncValue<List<Product>> productsAsync) {
    return productsAsync.when(
      data: (products) => _buildProductGrid(products.take(4).toList()),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '상품을 불러오지 못했습니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
      ),
    );
  }

  Widget _buildProductGrid(List<Product> products) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.74,
        ),
        itemBuilder: (context, index) {
          return _ProductCard(product: products[index]);
        },
      ),
    );
  }

  /// 5. 기타 추천 상품 (OTHER - 갈대발, 마포걸레, 데크타일 등 가로 스크롤 카드)
  Widget _buildOtherRecommendedSection() {
    final otherProductsAsync = ref.watch(otherProductsProvider);
    final otherProducts = otherProductsAsync.value ?? ProductDataService.otherProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('기타 추천 상품', 'OTHER ITEMS', () {
          final uri = Uri(
            path: '/category/products',
            queryParameters: {'name': '생활 주방용품', 'no': '46'},
          );
          context.push(uri.toString());
        }),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: otherProducts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final product = otherProducts[index];
              return GestureDetector(
                onTap: () => context.push('/products/${product.id}', extra: product),
                child: Container(
                  width: 135,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                        child: Container(
                          width: 135,
                          height: 110,
                          color: AppTheme.chipBackground,
                          child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                              ? Image.network(
                                  product.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(product.icon, size: 36, color: const Color(0xFF94A3B8)),
                                )
                              : Icon(product.icon, size: 36, color: const Color(0xFF94A3B8)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              product.formattedSalePrice,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 6. 이벤트 배너 (EVENT - 대량구매 / 무료견적)
  Widget _buildEventBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'EVENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.point,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '사업자 · 대량구매 특별 견적',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 3),
                Text(
                  '행사장 · 시공업체 대량 발주 시 도매가 및 세금계산서 지원',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  /// 7. 실시간 베스트 리뷰 (REVIEW)
  Widget _buildRealtimeReviewSection() {
    final reviews = [
      _ReviewItem(
        productName: '친환경 롤매트 2m',
        author: '김*은 고객님',
        rating: 5,
        content: '두께 10mm로 주문했는데 복원력도 좋고 냄새가 전혀 없네요. 아이 방에 완벽합니다!',
      ),
      _ReviewItem(
        productName: '행사장 파이텍스 매트',
        author: '이*호 고객님',
        rating: 5,
        content: '박람회 부스 시공용으로 대량 주문했습니다. 재단도 깔끔하고 빠른 출고 감사해요.',
      ),
      _ReviewItem(
        productName: '천연 갈대발 햇빛가리개',
        author: '박*수 고객님',
        rating: 5,
        content: '베란다 창가에 걸어두니 바람도 잘 통하고 햇빛도 자연스럽게 가려줘서 분위기 최고예요.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('실시간 베스트 리뷰', 'REALTIME REVIEW', () {}),
        const SizedBox(height: 12),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final r = reviews[index];
              return Container(
                width: 250,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Row(
                          children: List.generate(
                            r.rating,
                            (_) => const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          r.author,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.productName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.content,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerServiceBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.chipBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.headset_mic_outlined, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '고객센터 031-528-3266 (평일 09:00~17:00)',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '문의하기',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('/products/${product.id}', extra: product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 130,
                    color: const Color(0xFFF8FAFC),
                    child: hasImage
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(product.icon, size: 40, color: const Color(0xFFCBD5E1)),
                            ),
                          )
                        : Center(
                            child: Icon(product.icon, size: 40, color: const Color(0xFFCBD5E1)),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (product.tag == 'NEW' || product.isNew)
                            ? const Color(0xFF16A34A)
                            : (product.tag == 'SALE' ? AppTheme.point : AppTheme.primary),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (product.tag == 'NEW' || product.isNew) ? 'NEW' : product.tag,
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (product.discountRate > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppTheme.point,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${product.discountRate}%',
                          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (product.discountRate > 0) ...[
                    Text(
                      product.formattedOriginalPrice,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF94A3B8),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 1),
                  ],
                  Text(
                    product.formattedSalePrice,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerItem {
  final String tag;
  final String title;
  final String subtitle;
  final Color bgColor;
  final IconData icon;

  _BannerItem({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.icon,
  });
}

class _QuickCategoryItem {
  final String label;
  final int? categoryNo;
  final IconData icon;

  _QuickCategoryItem({
    required this.label,
    this.categoryNo,
    required this.icon,
  });
}

class _ReviewItem {
  final String productName;
  final String author;
  final int rating;
  final String content;

  _ReviewItem({
    required this.productName,
    required this.author,
    required this.rating,
    required this.content,
  });
}
