import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';

class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({super.key});

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  int _selectedIndex = 0;

  final List<_MainCategoryData> _mainCategories = [
    _MainCategoryData(
      id: 'cat_all',
      name: '전체보기',
      icon: Icons.grid_view_rounded,
      bannerTitle: '수지씨앤엘 전상품',
      bannerSub: '다양한 매트와 생활용품을 한눈에!',
      bannerColor: AppTheme.primary,
      subCategories: [
        _SubCategoryData(name: '롤매트', icon: Icons.view_column, count: 24),
        _SubCategoryData(name: '현관발매트', icon: Icons.door_front_door, count: 18),
        _SubCategoryData(name: '인조잔디', icon: Icons.grass, count: 15),
        _SubCategoryData(name: '청소용품', icon: Icons.cleaning_services, count: 32),
        _SubCategoryData(name: '생활주방', icon: Icons.kitchen, count: 29),
        _SubCategoryData(name: '침구', icon: Icons.king_bed, count: 12),
        _SubCategoryData(name: '할인특가', icon: Icons.local_offer, count: 9),
      ],
      tags: ['#전상품무료배송', '#신상품', '#베스트', '#특가할인'],
    ),
    _MainCategoryData(
      id: 'cat_roll',
      name: '롤매트',
      icon: Icons.view_column_rounded,
      bannerTitle: '층간소음 방지\n프리미엄 롤매트',
      bannerSub: '원하는 길이만큼 싹둑! 맞춰 깔아요',
      bannerColor: const Color(0xFF0F172A),
      subCategories: [
        _SubCategoryData(name: 'DIY 롤매트', icon: Icons.cut, count: 12),
        _SubCategoryData(name: '거실용 롤매트', icon: Icons.tv, count: 8),
        _SubCategoryData(name: '복도/주방 매트', icon: Icons.straighten, count: 6),
        _SubCategoryData(name: '유아/애견 매트', icon: Icons.pets, count: 10),
        _SubCategoryData(name: '퍼즐/조립 매트', icon: Icons.extension, count: 5),
      ],
      tags: ['#층간소음완화', '#방수코팅', '#친환경EVA', '#도톰한15mm'],
    ),
    _MainCategoryData(
      id: 'cat_door',
      name: '현관발매트',
      icon: Icons.door_front_door_rounded,
      bannerTitle: '깔끔한 첫인상\n디자인 발매트',
      bannerSub: '먼지 흡수 및 미끄럼 방지 완벽 지원',
      bannerColor: const Color(0xFF334155),
      subCategories: [
        _SubCategoryData(name: '극세사 발매트', icon: Icons.dry_cleaning, count: 9),
        _SubCategoryData(name: '규조토 매트', icon: Icons.water_drop, count: 6),
        _SubCategoryData(name: '코일 먼지 매트', icon: Icons.grain, count: 7),
        _SubCategoryData(name: '항균 발매트', icon: Icons.clean_hands, count: 4),
        _SubCategoryData(name: '야외 현관매트', icon: Icons.deck, count: 5),
      ],
      tags: ['#초강력수분흡수', '#물세탁가능', '#미끄럼방지', '#모던디자인'],
    ),
    _MainCategoryData(
      id: 'cat_grass',
      name: '인조잔디',
      icon: Icons.grass_rounded,
      bannerTitle: '사계절 푸른\n리얼 인조잔디',
      bannerSub: '베란다·테라스 감성 인테리어 완성',
      bannerColor: const Color(0xFF1E293B),
      subCategories: [
        _SubCategoryData(name: '롤 인조잔디', icon: Icons.view_headline, count: 8),
        _SubCategoryData(name: '조립식 잔디타일', icon: Icons.grid_on, count: 5),
        _SubCategoryData(name: '베란다/옥상 잔디', icon: Icons.balcony, count: 6),
        _SubCategoryData(name: '조경용 잔디', icon: Icons.park, count: 4),
      ],
      tags: ['#UV상쇄코팅', '#배수구멍처리', '#손쉬운셀프시공', '#리얼풀높이'],
    ),
    _MainCategoryData(
      id: 'cat_clean',
      name: '청소용품',
      icon: Icons.cleaning_services_rounded,
      bannerTitle: '청소가 쉬워지는\n스마트 청소 아이템',
      bannerSub: '손쉬운 탈착과 우수한 세척력',
      bannerColor: const Color(0xFF475569),
      subCategories: [
        _SubCategoryData(name: '대걸레/밀대', icon: Icons.cleaning_services, count: 11),
        _SubCategoryData(name: '먼지털이/브러시', icon: Icons.brush, count: 8),
        _SubCategoryData(name: '청소포/수세미', icon: Icons.soap, count: 14),
        _SubCategoryData(name: '세정제/스프레이', icon: Icons.opacity, count: 9),
      ],
      tags: ['#360도회전', '#극세사패드', '#올인원세트', '#가성비갑'],
    ),
    _MainCategoryData(
      id: 'cat_kitchen',
      name: '생활주방',
      icon: Icons.kitchen_rounded,
      bannerTitle: '매일 만드는 기쁨\n주방 인테리어',
      bannerSub: '편리하고 깔끔한 주방 라이프',
      bannerColor: const Color(0xFF1E293B),
      subCategories: [
        _SubCategoryData(name: '주방 쿠션매트', icon: Icons.space_dashboard, count: 10),
        _SubCategoryData(name: '수납정리함', icon: Icons.inventory_2, count: 15),
        _SubCategoryData(name: '식기건조대', icon: Icons.countertops, count: 7),
      ],
      tags: ['#방수주방매트', '#설거지양말', '#공간활용수납'],
    ),
    _MainCategoryData(
      id: 'cat_bed',
      name: '침구',
      icon: Icons.king_bed_rounded,
      bannerTitle: '포근한 숙면\n프리미엄 침구',
      bannerSub: '부드러운 감촉의 극세사 라인업',
      bannerColor: const Color(0xFF334155),
      subCategories: [
        _SubCategoryData(name: '차렵이불 세트', icon: Icons.bed, count: 6),
        _SubCategoryData(name: '극세사 이불', icon: Icons.single_bed, count: 8),
        _SubCategoryData(name: '토퍼/패드', icon: Icons.layers, count: 5),
      ],
      tags: ['#알러지케어', '#극세사100%', '#사계절용'],
    ),
    _MainCategoryData(
      id: 'cat_sale',
      name: '할인특가',
      icon: Icons.local_offer_rounded,
      bannerTitle: '오늘만 이 가격!\n특가 한정수량',
      bannerSub: '최대 50% 파격 할인 기획전',
      bannerColor: AppTheme.point,
      subCategories: [
        _SubCategoryData(name: '오늘의 특가', icon: Icons.timer, count: 4),
        _SubCategoryData(name: '1+1 기획전', icon: Icons.exposure_plus_1, count: 6),
        _SubCategoryData(name: '창고대출동', icon: Icons.warehouse, count: 8),
      ],
      tags: ['#한정수량', '#무료배송', '#파격할인'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final currentCat = _mainCategories[_selectedIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          '카테고리 탐색',
          style: TextStyle(
            fontSize: 20,
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
                      style: TextStyle(
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
      body: Row(
        children: [
          _buildLeftSidebar(),
          Expanded(
            child: _buildRightContent(currentCat),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar() {
    return Container(
      width: 100,
      color: AppTheme.background,
      child: ListView.builder(
        itemCount: _mainCategories.length,
        itemBuilder: (context, index) {
          final cat = _mainCategories[index];
          final isSelected = index == _selectedIndex;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedIndex = index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : AppTheme.background,
                border: Border(
                  left: BorderSide(
                    color: isSelected
                        ? AppTheme.primary
                        : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 24,
                    color: isSelected
                        ? AppTheme.primary
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.primary
                          : const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRightContent(_MainCategoryData currentCat) {
    final products = currentCat.name == '전체보기'
        ? ProductDataService.all.take(4).toList()
        : ProductDataService.all
            .where((p) =>
                p.category == currentCat.name ||
                (currentCat.name == '할인특가' && p.discountRate > 0))
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryBanner(currentCat),
          const SizedBox(height: 20),
          _buildTagChips(currentCat.tags),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${currentCat.name} 세부 카테고리',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSubCategoryGrid(currentCat.subCategories),
          const SizedBox(height: 24),
          const Text(
            '인기 추천 상품',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '등록된 대표 상품이 준비 중입니다.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            _buildCategoryProductList(products),
        ],
      ),
    );
  }

  Widget _buildCategoryBanner(_MainCategoryData cat) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cat.bannerColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cat.bannerColor.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cat.bannerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                cat.bannerSub,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(
              cat.icon,
              size: 54,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChips(List<String> tags) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.chipBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubCategoryGrid(List<_SubCategoryData> subCategories) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: subCategories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final sub = subCategories[index];
        return GestureDetector(
          onTap: () {
            context.push('/search');
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(sub.icon, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  sub.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${sub.count}개',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryProductList(List<Product> products) {
    return Column(
      children: products.map((product) {
        return GestureDetector(
          onTap: () => context.push('/products/${product.id}'),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
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
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.chipBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(product.icon, size: 30, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (product.discountRate > 0) ...[
                            Text(
                              '-${product.discountRate}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.point,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
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
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MainCategoryData {
  final String id;
  final String name;
  final IconData icon;
  final String bannerTitle;
  final String bannerSub;
  final Color bannerColor;
  final List<_SubCategoryData> subCategories;
  final List<String> tags;

  _MainCategoryData({
    required this.id,
    required this.name,
    required this.icon,
    required this.bannerTitle,
    required this.bannerSub,
    required this.bannerColor,
    required this.subCategories,
    required this.tags,
  });
}

class _SubCategoryData {
  final String name;
  final IconData icon;
  final int count;

  _SubCategoryData({
    required this.name,
    required this.icon,
    required this.count,
  });
}
