import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/config/theme/theme.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/viewmodels/saved_products_viewmodel.dart';

/// 찜한 상품 목록 화면
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SavedProductsView(
      title: '찜한 상품',
      emptyIcon: Icons.favorite_border,
      emptyText: '찜한 상품이 없습니다.\n상품 상세에서 하트를 눌러 담아보세요.',
      products: ref.watch(favoritesProvider),
      onRemove: (p) => ref.read(favoritesProvider.notifier).remove(p.id),
      onClear: () => ref.read(favoritesProvider.notifier).clear(),
      clearLabel: '전체 삭제',
    );
  }
}

/// 최근 본 상품 목록 화면
class RecentProductsPage extends ConsumerWidget {
  const RecentProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SavedProductsView(
      title: '최근 본 상품',
      emptyIcon: Icons.history,
      emptyText: '최근 본 상품이 없습니다.',
      products: ref.watch(recentProvider),
      onRemove: (p) => ref.read(recentProvider.notifier).remove(p.id),
      onClear: () => ref.read(recentProvider.notifier).clear(),
      clearLabel: '전체 삭제',
    );
  }
}

class _SavedProductsView extends StatelessWidget {
  final String title;
  final IconData emptyIcon;
  final String emptyText;
  final List<Product> products;
  final void Function(Product) onRemove;
  final VoidCallback onClear;
  final String clearLabel;

  const _SavedProductsView({
    required this.title,
    required this.emptyIcon,
    required this.emptyText,
    required this.products,
    required this.onRemove,
    required this.onClear,
    required this.clearLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.primary, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (products.isNotEmpty)
            TextButton(
              onPressed: onClear,
              child: Text(clearLabel,
                  style: const TextStyle(color: Color(0xFF64748B))),
            ),
        ],
      ),
      body: products.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(emptyIcon, size: 56, color: const Color(0xFFCBD5E1)),
                  const SizedBox(height: 12),
                  Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = products[i];
                return _ProductTile(
                  product: p,
                  onRemove: () => onRemove(p),
                );
              },
            ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onRemove;

  const _ProductTile({required this.product, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/products/${product.id}', extra: product),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: product.imageUrl != null
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (product.discountRate > 0) ...[
                        Text('${product.discountRate}%',
                            style: const TextStyle(
                                color: AppTheme.point,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(width: 6),
                      ],
                      Text(product.formattedSalePrice,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.chipBackground,
        child: Icon(product.icon, color: const Color(0xFF94A3B8)),
      );
}
