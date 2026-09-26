import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  int _currentBannerIndex = 0;
  final PageController _bannerController = PageController();

  // 배너 데이터
  final List<_BannerItem> _banners = [
    _BannerItem(
      title: '자연과 함께하는\n편안한 매트',
      subtitle: '롤매트 / 인조잔디 전문몰',
      color: const Color(0xFF388E3C),
      icon: Icons.grass,
    ),
    _BannerItem(
      title: '현관을 더 깔끔하게\n현관발매트',
      subtitle: '다양한 디자인 매트 모음',
      color: const Color(0xFF1976D2),
      icon: Icons.door_front_door,
    ),
    _BannerItem(
      title: '생활을 편리하게\n청소용품',
      subtitle: '합리적인 가격의 청소용품',
      color: const Color(0xFFF57C00),
      icon: Icons.cleaning_services,
    ),
  ];

  // 카테고리 데이터
  final List<_CategoryItem> _categories = [
    _CategoryItem(label: '전체상품', icon: Icons.grid_view),
    _CategoryItem(label: '롤매트', icon: Icons.view_column),
    _CategoryItem(label: '현관발매트', icon: Icons.door_front_door),
    _CategoryItem(label: '인조잔디', icon: Icons.grass),
    _CategoryItem(label: '청소용품', icon: Icons.cleaning_services),
    _CategoryItem(label: '생활주방', icon: Icons.kitchen),
    _CategoryItem(label: '침구', icon: Icons.king_bed),
    _CategoryItem(label: '할인특가', icon: Icons.local_offer),
  ];

  // 신상품 데이터
  final List<Product> _newProducts = ProductDataService.newProducts;

  // 베스트상품 데이터
  final List<Product> _bestProducts = ProductDataService.bestProducts;



  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ───────────── AppBar ─────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title:  Text(
          '수지씨앤엘',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon:  Icon(Icons.search, color: Theme.of(context).primaryColor),
            onPressed: () {},
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF212121)),
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
                    color: Color(0xFF4CAF50),
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

      // ───────────── Body ─────────────
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 배너 슬라이더
            _buildBannerSlider(),
            const SizedBox(height: 24),

            // 카테고리
            _buildCategoryRow(),
            const SizedBox(height: 28),

            // 신상품 섹션
            _buildSectionTitle('신상품', '더보기'),
            const SizedBox(height: 12),
            _buildProductGrid(_newProducts),
            const SizedBox(height: 28),

            // 베스트상품 섹션
            _buildSectionTitle('베스트 상품', '더보기'),
            const SizedBox(height: 12),
            _buildProductGrid(_bestProducts),
            const SizedBox(height: 28),

            // 공지사항 배너
            _buildNoticeBanner(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ─── 배너 슬라이더 ───
  Widget _buildBannerSlider() {
    return SizedBox(
      height: 200,
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
                  color: banner.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              banner.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              banner.subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: banner.color,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('바로가기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      Icon(banner.icon, size: 80, color: Colors.white.withValues(alpha: 0.3)),
                    ],
                  ),
                ),
              );
            },
          ),
          // 페이지 인디케이터
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
                  width: _currentBannerIndex == index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentBannerIndex == index ? Colors.white : Colors.white.withValues(alpha: 0.5),
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

  // ─── 카테고리 가로 스크롤 ───
  Widget _buildCategoryRow() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          return GestureDetector(
            onTap: () {},
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFDCEDC8), width: 1),
                  ),
                  child: Icon(cat.icon, color: const Color(0xFF388E3C), size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  cat.label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF424242), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── 섹션 타이틀 ───
  Widget _buildSectionTitle(String title, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
          ),
          GestureDetector(
            onTap: () {},
            child: Row(
              children: const [
                Text('더보기', style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
                Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 상품 그리드 ───
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
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductCard(product: product);
        },
      ),
    );
  }

  // ─── 공지사항 배너 ───
  Widget _buildNoticeBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCEDC8)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('공지', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '평일 09:00~17:00 고객센터 운영 | 031-528-3266',
              style: TextStyle(fontSize: 13, color: Color(0xFF424242)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
        ],
      ),
    );
  }
}

// ─── 상품 카드 위젯 ───
class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/products/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상품 이미지 영역 (플레이스홀더)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 130,
                    color: const Color(0xFFF5F5F5),
                    child: Icon(product.icon, size: 60, color: const Color(0xFFBDBDBD)),
                  ),
                  // 태그
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: product.tagColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        product.tag,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  // 할인율 뱃지
                  if (product.discountRate > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${product.discountRate}%',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 상품 정보
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF212121), height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (product.discountRate > 0) ...[
                    Text(
                      product.formattedOriginalPrice,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 1),
                  ],
                  Text(
                    product.formattedSalePrice,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
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

// ─── 데이터 모델 ───
class _BannerItem {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  _BannerItem({required this.title, required this.subtitle, required this.color, required this.icon});
}

class _CategoryItem {
  final String label;
  final IconData icon;
  _CategoryItem({required this.label, required this.icon});
}
