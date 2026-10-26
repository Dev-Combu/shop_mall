import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/category.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/category_viewmodel.dart';
import 'package:shopmall/viewmodels/home_products_viewmodel.dart';

class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({super.key});

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  int _selectedIndex = 0;
  String? _selectedSubCategoryName;

  @override
  void initState() {
    super.initState();
    // 외부(홈 등)에서 선택된 카테고리 필터가 있다면 초기 진입 시 적용
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialFilter = ref.read(selectedCategoryFilterProvider);
      if (initialFilter != null) {
        final categoriesAsync = ref.read(categoriesProvider);
        final allCategoriesAsync = ref.read(allCategoriesProvider);
        final mainCategories = _getMappedCategories(
          categoriesAsync.value,
          allCategoriesAsync.value,
        );
        setState(() {
          _applyCategoryFilter(initialFilter, mainCategories);
        });
        ref.read(selectedCategoryFilterProvider.notifier).clear();
      }
    });
  }

  void _applyCategoryFilter(String filter, List<_MainCategoryData> mainCategories) {
    final cleanFilter = filter.replaceAll('#', '').trim();
    if (cleanFilter.isEmpty) return;

    if (cleanFilter == '신상품' || cleanFilter == 'NEW') {
      _selectedIndex = 0; // 전체보기
      _selectedSubCategoryName = '신상품';
      return;
    }
    if (cleanFilter == '베스트' || cleanFilter == 'BEST') {
      _selectedIndex = 0; // 전체보기
      _selectedSubCategoryName = '베스트';
      return;
    }
    if (cleanFilter.contains('특가') || cleanFilter.contains('할인')) {
      _selectedIndex = 0; // 전체보기
      _selectedSubCategoryName = '특가할인';
      return;
    }

    final matchedIndex = mainCategories.indexWhere(
      (c) => c.name == cleanFilter || c.name.contains(cleanFilter) || cleanFilter.contains(c.name),
    );

    if (matchedIndex != -1) {
      _selectedIndex = matchedIndex;
      _selectedSubCategoryName = null;
    } else {
      _selectedIndex = 0;
      _selectedSubCategoryName = cleanFilter;
    }
  }

  Color _getCategoryColor(String name) {
    if (name.contains('전체보기')) return AppTheme.primary;
    if (name.contains('롤매트')) return const Color(0xFF0F172A);
    if (name.contains('현관') || name.contains('발매트')) return const Color(0xFF312E81);
    if (name.contains('잔디')) return const Color(0xFF14532D);
    if (name.contains('청소')) return const Color(0xFF0E7490);
    if (name.contains('주방') || name.contains('생활')) return const Color(0xFF78350F);
    if (name.contains('침구') || name.contains('이불')) return const Color(0xFF581C87);
    if (name.contains('특가') || name.contains('할인')) return AppTheme.point;
    return const Color(0xFF1E293B);
  }

  String _getCategoryBannerSubtitle(String name) {
    if (name.contains('전체보기')) return '수지씨앤엘 전상품을 한눈에 둘러보세요';
    if (name.contains('롤매트')) return '원하는 길이만큼 맞춰 시공하는 프리미엄 롤매트';
    if (name.contains('현관') || name.contains('발매트')) return '먼지 흡수와 미끄럼 방지 완벽 지원';
    if (name.contains('잔디')) return '베란다·테라스 감성 인테리어 완성';
    if (name.contains('청소')) return '손쉬운 탈착과 우수한 세척력의 클리닝 라인';
    if (name.contains('주방') || name.contains('생활')) return '편리하고 깔끔한 라이프스타일 필수품';
    if (name.contains('침구') || name.contains('이불')) return '부드러운 감촉의 프리미엄 극세사 & 사계절 침구';
    return '수지씨앤엘 공식 보증 정품 라인업';
  }

  final List<_MainCategoryData> _fallbackCategories = [
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
      ],
      tags: ['#신상품', '#베스트', '#특가할인', '#전상품무료배송'],
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
      ],
      tags: ['#신상품', '#베스트', '#층간소음완화', '#방수코팅'],
    ),
  ];

  List<_MainCategoryData> _getMappedCategories(
    List<ShopCategory>? mainCats,
    List<ShopCategory>? allCats,
  ) {
    if (mainCats == null || mainCats.isEmpty) return _fallbackCategories;
    final all = allCats ?? mainCats;

    return mainCats.map((c) {
      List<_SubCategoryData> subs = [];

      if (c.id == 24 || c.name == '전체보기') {
        subs = all
            .where((sub) => sub.depth == 2)
            .map((sub) => _SubCategoryData(id: sub.id, name: sub.name, icon: sub.icon, count: 10))
            .toList();
      } else {
        // depth 3 카테고리 매핑 (parent_category_no == c.id)
        final children = all.where((sub) => sub.parentId == c.id).toList();
        if (children.isNotEmpty) {
          subs = children
              .map((sub) => _SubCategoryData(id: sub.id, name: sub.name, icon: sub.icon, count: 8))
              .toList();
        } else {
          subs = [
            _SubCategoryData(id: c.id, name: '${c.name} 전체', icon: c.icon, count: 12),
          ];
        }
      }

      final tags = c.name == '전체보기'
          ? ['#신상품', '#베스트', '#특가할인', '#전상품무료배송']
          : ['#신상품', '#베스트', '#${c.name}', '#무료배송'];

      return _MainCategoryData(
        id: 'cat_${c.id}',
        categoryNo: c.id,
        name: c.name,
        icon: c.icon,
        bannerTitle: c.name == '전체보기' ? '수지씨앤엘 전상품' : '${c.name} 전문관',
        bannerSub: _getCategoryBannerSubtitle(c.name),
        bannerColor: _getCategoryColor(c.name),
        subCategories: subs,
        tags: tags,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final allCategoriesAsync = ref.watch(allCategoriesProvider);
    final mainCategories = _getMappedCategories(
      categoriesAsync.value,
      allCategoriesAsync.value,
    );

    // 외부에서 변경된 카테고리 필터 감지
    ref.listen<String?>(selectedCategoryFilterProvider, (previous, next) {
      if (next != null && next != previous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _applyCategoryFilter(next, mainCategories);
          });
          ref.read(selectedCategoryFilterProvider.notifier).clear();
        });
      }
    });

    final activeIndex = _selectedIndex.clamp(0, mainCategories.isEmpty ? 0 : mainCategories.length - 1);
    final currentCat = mainCategories.isNotEmpty ? mainCategories[activeIndex] : _fallbackCategories[0];

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
          _buildLeftSidebar(mainCategories),
          Expanded(
            child: _buildRightContent(currentCat),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar(List<_MainCategoryData> categories) {
    return Container(
      width: 100,
      color: AppTheme.background,
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = index == _selectedIndex;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedIndex = index;
                _selectedSubCategoryName = null; // 대분류 변경 시 서브카테고리 선택 초기화
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
    final productsAsync = ref.watch(homeProductsProvider);
    final newProductsAsync = ref.watch(newProductsProvider);
    final bestProductsAsync = ref.watch(bestProductsProvider);
    final allProducts = productsAsync.value ?? ProductDataService.all;

    // 카테고리 및 선택된 세부카테고리에 맞춰 정밀 필터링
    List<Product> products = [];
    if (_selectedSubCategoryName != null) {
      final sub = _selectedSubCategoryName!;
      final base = currentCat.name == '전체보기'
          ? allProducts
          : allProducts.where((p) => p.matchesCategory(currentCat.name)).toList();

      if (sub == '신상품' || sub == 'NEW') {
        if (currentCat.name == '전체보기' &&
            newProductsAsync.value != null &&
            newProductsAsync.value!.isNotEmpty) {
          products = newProductsAsync.value!;
        } else {
          products = base.where((p) => p.isNew || p.tag == 'NEW').toList();
          if (products.isEmpty) {
            final sorted = List<Product>.from(base);
            sorted.sort((a, b) {
              if (a.createdDate != null && b.createdDate != null) {
                return b.createdDate!.compareTo(a.createdDate!);
              }
              final aId = int.tryParse(a.id) ?? 0;
              final bId = int.tryParse(b.id) ?? 0;
              return bId.compareTo(aId);
            });
            products = sorted.take(8).toList();
          }
        }
      } else if (sub == '베스트' || sub == 'BEST') {
        if (currentCat.name == '전체보기' &&
            bestProductsAsync.value != null &&
            bestProductsAsync.value!.isNotEmpty) {
          products = bestProductsAsync.value!;
        } else {
          products = base.where((p) => p.isRecommend || p.tag == 'BEST').toList();
          if (products.isEmpty) {
            final discounted = base.where((p) => p.discountRate > 0 || p.tag == 'SALE').toList();
            products = discounted.isNotEmpty ? discounted : base.take(8).toList();
          }
        }
      } else if (sub.contains('특가') || sub.contains('할인')) {
        products = base.where((p) => p.discountRate > 0 || p.tag == 'SALE').toList();
      } else {
        products = allProducts.where((p) => p.matchesCategory(sub)).toList();
      }
    } else if (currentCat.name == '전체보기') {
      products = allProducts;
    } else {
      products = allProducts
          .where((p) => p.matchesCategory(currentCat.name))
          .toList();
    }

    final displayProducts = products;

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
              if (_selectedSubCategoryName != null)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSubCategoryName = null;
                    });
                  },
                  child: const Text(
                    '선택 해제',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.point,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSubCategoryGrid(currentCat.subCategories),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedSubCategoryName != null
                    ? '$_selectedSubCategoryName 추천 상품'
                    : '${currentCat.name} 추천 상품',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                '총 ${displayProducts.length}개',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (displayProducts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '등록된 상품이 준비 중입니다.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            _buildCategoryProductList(displayProducts),
        ],
      ),
    );
  }

  void _navigateToCategoryProducts({required String name, int? categoryNo}) {
    final query = <String, String>{'name': name};
    if (categoryNo != null && categoryNo > 0) {
      query['no'] = categoryNo.toString();
    }
    final uri = Uri(path: '/category/products', queryParameters: query);
    context.push(uri.toString());
  }

  Widget _buildCategoryBanner(_MainCategoryData cat) {
    return GestureDetector(
      onTap: () => _navigateToCategoryProducts(
        name: cat.name,
        categoryNo: cat.categoryNo,
      ),
      child: Container(
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
      ),
    );
  }

  Widget _buildTagChips(List<String> tags) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        final cleanTag = tag.replaceAll('#', '').trim();
        final isSelected = _selectedSubCategoryName == cleanTag;

        return GestureDetector(
          onTap: () {
            _navigateToCategoryProducts(name: cleanTag);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary : AppTheme.chipBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.border,
              ),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : AppTheme.primary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
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
        final isSubSelected = _selectedSubCategoryName == sub.name;

        return GestureDetector(
          onTap: () {
            _navigateToCategoryProducts(
              name: sub.name,
              categoryNo: sub.id,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSubSelected ? AppTheme.primary.withValues(alpha: 0.05) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSubSelected ? AppTheme.primary : const Color(0xFFF1F5F9),
                width: isSubSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSubSelected ? AppTheme.primary : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    sub.icon,
                    color: isSubSelected ? Colors.white : AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sub.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSubSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSubSelected ? AppTheme.primary : const Color(0xFF334155),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${sub.count}개',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSubSelected ? AppTheme.primary : const Color(0xFF94A3B8),
                    fontWeight: isSubSelected ? FontWeight.w600 : FontWeight.normal,
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
          onTap: () => context.push('/products/${product.id}', extra: product),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: AppTheme.chipBackground,
                    child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(product.icon, size: 28, color: const Color(0xFF94A3B8)),
                          )
                        : Icon(product.icon, size: 28, color: const Color(0xFF94A3B8)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (product.tag == 'NEW' || product.isNew)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            )
                          else if (product.tag == 'BEST' || product.isRecommend)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'BEST',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
  final int? categoryNo;
  final String name;
  final IconData icon;
  final String bannerTitle;
  final String bannerSub;
  final Color bannerColor;
  final List<_SubCategoryData> subCategories;
  final List<String> tags;

  _MainCategoryData({
    required this.id,
    this.categoryNo,
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
  final int? id;
  final String name;
  final IconData icon;
  final int count;

  _SubCategoryData({
    this.id,
    required this.name,
    required this.icon,
    required this.count,
  });
}
