import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/cafe24_api_service.dart';
import 'package:shopmall/services/product_data.dart';
import 'package:shopmall/viewmodels/bottom_nav_viewmodel.dart';
import 'package:shopmall/viewmodels/category_viewmodel.dart';
import 'package:shopmall/viewmodels/home_products_viewmodel.dart';

/// 카테고리별 상품 목록 전용 Provider
final categoryProductsListProvider =
    FutureProvider.family<List<Product>, ({int? categoryNo, String categoryName})>(
  (ref, arg) async {
    final api = ref.watch(cafe24ApiServiceProvider);
    final name = arg.categoryName.replaceAll('#', '').trim();
    final catNo = arg.categoryNo;

    // 1. 신상품 / 베스트 메인 진열 연동
    if (name == '신상품' || name == 'NEW') {
      return await ref.watch(newProductsProvider.future);
    }
    if (name == '베스트' || name == '베스트 상품' || name == 'BEST') {
      return await ref.watch(bestProductsProvider.future);
    }

    // 2. Cafe24 카테고리 번호(categoryNo)가 있는 경우 해당 카테고리 상품 직접 조회
    if (api.hasCredentials && catNo != null && catNo > 0 && catNo != 24) {
      try {
        final fetched = await api.fetchProducts(categoryNo: catNo, limit: 60);
        if (fetched.isNotEmpty) {
          return fetched;
        }
      } catch (e) {
        debugPrint('[categoryProductsListProvider] 카테고리($catNo) API 조회 실패: $e');
      }
    }

    // 3. 이름으로 카테고리 번호 역추적 후 API 조회 시도
    if (api.hasCredentials && name.isNotEmpty && name != '전체보기') {
      try {
        final allCats = await ref.watch(allCategoriesProvider.future);
        final cleanTarget = name.replaceAll('전체', '').replaceAll(' ', '').toLowerCase();
        final matchedCat = allCats
            .where(
              (c) =>
                  c.name.replaceAll(' ', '').toLowerCase() == cleanTarget ||
                  c.name.replaceAll(' ', '').toLowerCase().contains(cleanTarget),
            )
            .firstOrNull;

        if (matchedCat != null && matchedCat.id > 0 && matchedCat.id != 24) {
          final fetched = await api.fetchProducts(categoryNo: matchedCat.id, limit: 60);
          if (fetched.isNotEmpty) {
            return fetched;
          }
        }
      } catch (_) {}
    }

    // 4. 전체 상품 목록에서 카테고리/키워드 매칭 필터링
    final allProducts = await ref.watch(homeProductsProvider.future);
    if (name.isEmpty || name == '전체보기' || name.contains('무료배송')) {
      return allProducts;
    }

    final cleanQuery = name.replaceAll('전체', '').trim();
    final filtered = allProducts.where((p) {
      if (catNo != null && catNo > 0 && p.categoryNos.contains(catNo)) {
        return true;
      }
      return p.matchesCategory(cleanQuery);
    }).toList();

    return filtered.isNotEmpty ? filtered : ProductDataService.all.where((p) => p.matchesCategory(cleanQuery)).toList();
  },
);

enum _ProductSortOption {
  recommend('추천순'),
  newest('신상품순'),
  lowPrice('낮은가격순'),
  highPrice('높은가격순'),
  discount('할인율순');

  final String label;
  const _ProductSortOption(this.label);
}

/// 카테고리 상품 리스트 화면
class CategoryProductsPage extends ConsumerStatefulWidget {
  final String categoryName;
  final int? categoryNo;

  const CategoryProductsPage({
    super.key,
    required this.categoryName,
    this.categoryNo,
  });

  @override
  ConsumerState<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends ConsumerState<CategoryProductsPage> {
  _ProductSortOption _sortOption = _ProductSortOption.recommend;
  bool _isGridView = true;

  List<Product> _sortProducts(List<Product> items) {
    final sorted = List<Product>.from(items);
    switch (_sortOption) {
      case _ProductSortOption.recommend:
        break;
      case _ProductSortOption.newest:
        sorted.sort((a, b) {
          if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
          if (a.createdDate != null && b.createdDate != null) {
            return b.createdDate!.compareTo(a.createdDate!);
          }
          final aId = int.tryParse(a.id) ?? 0;
          final bId = int.tryParse(b.id) ?? 0;
          return bId.compareTo(aId);
        });
      case _ProductSortOption.lowPrice:
        sorted.sort((a, b) => a.salePrice.compareTo(b.salePrice));
      case _ProductSortOption.highPrice:
        sorted.sort((a, b) => b.salePrice.compareTo(a.salePrice));
      case _ProductSortOption.discount:
        sorted.sort((a, b) => b.discountRate.compareTo(a.discountRate));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      categoryProductsListProvider((
        categoryNo: widget.categoryNo,
        categoryName: widget.categoryName,
      )),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppTheme.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.categoryName.replaceAll('#', ''),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            letterSpacing: -0.4,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.primary),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary),
            onPressed: () {
              context.go('/cart');
              ref.read(bottomNavProvider.notifier).setIndex(BottomNavIndex.cart);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42, color: Color(0xFF94A3B8)),
                const SizedBox(height: 12),
                Text(
                  '상품 목록을 불러오지 못했습니다.\n$err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
        data: (rawProducts) {
          final products = _sortProducts(rawProducts);

          return Column(
            children: [
              // 상단 필터/정렬 툴바
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '총 ${products.length}개',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Spacer(),
                    // 정렬 선택 드롭다운 버튼
                    PopupMenuButton<_ProductSortOption>(
                      initialValue: _sortOption,
                      onSelected: (value) {
                        setState(() => _sortOption = value);
                      },
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _sortOption.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => _ProductSortOption.values
                          .map(
                            (opt) => PopupMenuItem<_ProductSortOption>(
                              value: opt,
                              child: Text(
                                opt.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _sortOption == opt ? FontWeight.bold : FontWeight.normal,
                                  color: _sortOption == opt ? AppTheme.primary : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: 8),
                    // 그리드 / 리스트 뷰 전환 토글
                    GestureDetector(
                      onTap: () => setState(() => _isGridView = !_isGridView),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Icon(
                          _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 상품 목록 영역
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text(
                              '해당 카테고리에 등록된 상품이 없습니다.',
                              style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    : _isGridView
                        ? GridView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: products.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.72,
                            ),
                            itemBuilder: (context, index) => _buildGridCard(products[index]),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: products.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) => _buildListCard(products[index]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGridCard(Product product) {
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
                    height: 140,
                    color: const Color(0xFFF8FAFC),
                    child: hasImage
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
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
              padding: const EdgeInsets.all(10),
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
                  const SizedBox(height: 6),
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
                      fontSize: 14,
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

  Widget _buildListCard(Product product) {
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('/products/${product.id}', extra: product),
      child: Container(
        padding: const EdgeInsets.all(12),
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
                width: 82,
                height: 82,
                color: AppTheme.chipBackground,
                child: hasImage
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(product.icon, size: 32, color: const Color(0xFF94A3B8)),
                      )
                    : Icon(product.icon, size: 32, color: const Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(width: 14),
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
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (product.discountRate > 0) ...[
                        Text(
                          '-${product.discountRate}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.point,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        product.formattedSalePrice,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

