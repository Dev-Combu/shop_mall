import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shopmall/models/product.dart';
import 'package:shopmall/services/product_data.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 검색 상태
  String _currentQuery = '';
  bool _isSubmitted = false;
  String _selectedSort = '추천순'; // 정렬 옵션: 추천순, 최신순, 낮은가격순, 높은가격순

  // 최근 검색어 데이터
  final List<String> _recentSearches = [
    '롤매트',
    '현관발매트',
    '인조잔디',
    '청소용품',
    '친환경 EVA',
  ];

  // 인기 검색어 순위 데이터
  final List<_TrendingKeyword> _trendingKeywords = [
    _TrendingKeyword(rank: 1, keyword: '롤매트 층간소음', isNew: true),
    _TrendingKeyword(rank: 2, keyword: '현관발매트 극세사', rankChange: 1),
    _TrendingKeyword(rank: 3, keyword: '베란다 인조잔디', rankChange: 0),
    _TrendingKeyword(rank: 4, keyword: '회전 대걸레 세트', rankChange: 2),
    _TrendingKeyword(rank: 5, keyword: '주방 쿠션매트', rankChange: -1),
    _TrendingKeyword(rank: 6, keyword: '친환경 EVA 폼', isNew: true),
    _TrendingKeyword(rank: 7, keyword: '규조토 발매트', rankChange: 0),
    _TrendingKeyword(rank: 8, keyword: '극세사 이불세트', rankChange: 3),
    _TrendingKeyword(rank: 9, keyword: '퍼즐매트 15mm', rankChange: -2),
    _TrendingKeyword(rank: 10, keyword: '할인특가 매트', rankChange: 1),
  ];

  // 추천 태그
  final List<String> _recommendTags = [
    '#층간소음방지',
    '#방수코팅',
    '#무료배송',
    '#1+1특가',
    '#극세사',
    '#인테리어잔디',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 검색 실행
  void _executeSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _currentQuery = trimmed;
      _searchController.text = trimmed;
      _isSubmitted = true;

      // 최근 검색어 업데이트 (중복 제거 및 최상단 배치)
      _recentSearches.remove(trimmed);
      _recentSearches.insert(0, trimmed);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
    });
    _focusNode.unfocus();
  }

  // 최근 검색어 개별 삭제
  void _removeRecentSearch(String keyword) {
    setState(() {
      _recentSearches.remove(keyword);
    });
  }

  // 최근 검색어 전체 삭제
  void _clearRecentSearches() {
    setState(() {
      _recentSearches.clear();
    });
  }

  // 검색 초기화 (초기 화면으로)
  void _clearSearchInput() {
    setState(() {
      _searchController.clear();
      _currentQuery = '';
      _isSubmitted = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ───────────── AppBar (스마트 검색바) ─────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
          onPressed: () {
            if (_isSubmitted) {
              _clearSearchInput();
            } else {
              context.pop();
            }
          },
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? const Color(0xFF388E3C)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14, color: Color(0xFF212121)),
              decoration: InputDecoration(
                hintText: '원하는 매트, 청소용품을 검색해보세요',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.cancel, size: 18, color: Color(0xFF9E9E9E)),
                        onPressed: _clearSearchInput,
                      )
                    : null,
              ),
              onChanged: (val) {
                setState(() {
                  _currentQuery = val;
                  if (val.isEmpty) {
                    _isSubmitted = false;
                  }
                });
              },
              onSubmitted: _executeSearch,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF388E3C)),
            onPressed: () => _executeSearch(_searchController.text),
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ───────────── Body ─────────────
      body: _isSubmitted
          ? _buildSearchResultView()
          : _buildBeforeSearchView(),
    );
  }

  // ─── 1. 검색 전 화면 (최근 검색어, 인기 검색어, 추천 태그) ───
  Widget _buildBeforeSearchView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. 최근 검색어
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '최근 검색어',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                GestureDetector(
                  onTap: _clearRecentSearches,
                  child: const Text(
                    '전체삭제',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((keyword) {
                return Container(
                  padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _executeSearch(keyword),
                        child: Text(
                          keyword,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF424242),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeRecentSearch(keyword),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 14, color: Color(0xFF9E9E9E)),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
          ],

          // B. 추천 키워드 태그
          const Text(
            '추천 태그',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recommendTags.map((tag) {
              return ActionChip(
                label: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF388E3C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: const Color(0xFFF1F8E9),
                side: const BorderSide(color: Color(0xFFDCEDC8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onPressed: () {
                  final cleanTag = tag.replaceAll('#', '');
                  _executeSearch(cleanTag);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // C. 실시간 인기 검색어 (1~10위)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Text(
                    '실시간 인기 검색어',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.local_fire_department, size: 18, color: Color(0xFFE53935)),
                ],
              ),
              Text(
                '${DateTime.now().hour}:00 기준',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2열 그리드로 인기 검색어 나열
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1~5위
              Expanded(
                child: Column(
                  children: _trendingKeywords
                      .sublist(0, 5)
                      .map((item) => _buildTrendingTile(item))
                      .toList(),
                ),
              ),
              const SizedBox(width: 16),
              // 6~10위
              Expanded(
                child: Column(
                  children: _trendingKeywords
                      .sublist(5, 10)
                      .map((item) => _buildTrendingTile(item))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 인기 검색어 항목 타일
  Widget _buildTrendingTile(_TrendingKeyword item) {
    return InkWell(
      onTap: () => _executeSearch(item.keyword),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            // 순위 숫자
            SizedBox(
              width: 22,
              child: Text(
                '${item.rank}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: item.rank <= 3
                      ? const Color(0xFF388E3C)
                      : const Color(0xFF616161),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 검색어 텍스트
            Expanded(
              child: Text(
                item.keyword,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF212121),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 순위 변동 표시 (NEW, Up, Down, 동일)
            if (item.isNew)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (item.rankChange > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_drop_up, size: 16, color: Color(0xFFE53935)),
                  Text(
                    '${item.rankChange}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFE53935)),
                  ),
                ],
              )
            else if (item.rankChange < 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF1976D2)),
                  Text(
                    '${item.rankChange.abs()}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF1976D2)),
                  ),
                ],
              )
            else
              const Text(
                '-',
                style: TextStyle(fontSize: 12, color: Color(0xFFBDBDBD)),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 2. 검색 결과 화면 (Query 검색 결과 표시) ───
  Widget _buildSearchResultView() {
    // 상품 필터링
    List<Product> results = ProductDataService.all.where((product) {
      final query = _currentQuery.toLowerCase();
      return product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query) ||
          product.tag.toLowerCase().contains(query);
    }).toList();

    // 정렬 적용
    if (_selectedSort == '낮은가격순') {
      results.sort((a, b) => a.salePrice.compareTo(b.salePrice));
    } else if (_selectedSort == '높은가격순') {
      results.sort((a, b) => b.salePrice.compareTo(a.salePrice));
    } else if (_selectedSort == '최신순') {
      results.sort((a, b) => (b.tag == 'NEW' ? 1 : 0).compareTo(a.tag == 'NEW' ? 1 : 0));
    }

    return Column(
      children: [
        // 검색 헤더 및 정렬 옵션
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Color(0xFF212121)),
                  children: [
                    TextSpan(
                      text: "'$_currentQuery'",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF388E3C),
                      ),
                    ),
                    const TextSpan(text: ' 검색 결과 '),
                    TextSpan(
                      text: '${results.length}개',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // 정렬 드롭다운 메뉴
              DropdownButton<String>(
                value: _selectedSort,
                underline: const SizedBox(),
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF616161)),
                style: const TextStyle(fontSize: 13, color: Color(0xFF616161)),
                items: ['추천순', '최신순', '낮은가격순', '높은가격순'].map((String sort) {
                  return DropdownMenuItem<String>(
                    value: sort,
                    child: Text(sort),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSort = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),

        // 검색 결과 상품 그리드 또는 Empty State
        Expanded(
          child: results.isEmpty
              ? _buildSearchResultEmpty()
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: results.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final product = results[index];
                    return _SearchResultProductCard(product: product);
                  },
                ),
        ),
      ],
    );
  }

  // 검색 결과 없음 UI
  Widget _buildSearchResultEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off,
                size: 40,
                color: Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "'$_currentQuery'에 대한 검색 결과가 없습니다.",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '단어의 철자가 정확한지 확인하시거나\n더 일반적인 단어로 다시 검색해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF757575),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _clearSearchInput,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF388E3C),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('전체 검색어로 돌아가기'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 검색 결과 상품 카드 ───
class _SearchResultProductCard extends StatelessWidget {
  final Product product;
  const _SearchResultProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/products/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 썸네일
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 120,
                    color: const Color(0xFFF5F5F5),
                    child: Icon(product.icon, size: 50, color: const Color(0xFFBDBDBD)),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: product.tagColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        product.tag,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 내용
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (product.discountRate > 0)
                    Text(
                      product.formattedOriginalPrice,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    product.formattedSalePrice,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
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

// ─── 인기 검색어 데이터 모델 ───
class _TrendingKeyword {
  final int rank;
  final String keyword;
  final int rankChange; // 0: 동일, >0: 상승, <0: 하강
  final bool isNew;

  _TrendingKeyword({
    required this.rank,
    required this.keyword,
    this.rankChange = 0,
    this.isNew = false,
  });
}
