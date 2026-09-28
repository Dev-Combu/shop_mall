# 📝 작업 일지 & UI/UX 리팩토링 보고서 (2026-09-28)

## 📌 작업 개요
본 문서는 2026년 9월 28일에 진행된 **수지씨앤엘 (shopmall) Flutter 애플리케이션 화면 UI/UX 전면 개편 및 테마 시스템 구축 작업**의 상세 내역과 페이지별 핵심 기능 코드/위젯에 대한 기술 설명 보고서입니다.

---

## 🛠 주요 작업 내역 요약

| 구분 | 주요 변경 사항 | 파일 위치 |
| :--- | :--- | :--- |
| **디자인 테마 시스템** | 3단계 색상 시스템(Primary, Point, Surface) 정립 및 브랜드 레드 밸런스 조정 | `lib/config/theme/theme.dart` |
| **마이페이지 / 설정** | 로그인/비로그인 헤더 카드 분리 및 카테고리별 설정 리스트 구현 | `lib/views/my_page.dart` |
| **장바구니 (Cart)** | 상태 관리(Riverpod), 무료배송 진행 바, 수량변경, 결제예정금액 카드 구현 | `lib/views/cart.dart` <br> `lib/viewmodels/cart_viewmodel.dart` |
| **카테고리 탐색** | 기존 버튼 리스트에서 **2-Pane Split View** (사이드바 + 서브그리드) 개편 | `lib/views/category.dart` |
| **스마트 검색** | 최근 검색어, 실시간 인기 순위, 추천 태그, 실시간 검색 결과 필터링 구현 | `lib/views/search.dart` |
| **쉘 레이아웃** | 바텀 네비게이션 탭 아이콘 및 테마 색상 동기화 | `lib/views/share/scaffold_shell_layout.dart` |

---

## 🎨 1. 디자인 시스템 & 테마 구축 (`theme.dart`)

### 🎨 색상 체계 (Color System)
- **주요 색상 (Primary Color)**: `Color(0xFF1E293B)` (모던 딥 찰콜) - 앱바 타이틀, 메인 텍스트, 사이드바 선택 인디케이터
- **포인트 색상 (Point Accent Color)**: `Color(0xFFE53935)` (브라이트 포인트 레드) - 구매/주문 버튼, 할인율 뱃지, 카트 수량 뱃지
- **반전 및 배경 서브 색상 (Surface / Background)**: `Color(0xFFF8FAFC)`, `Color(0xFFF1F5F9)` (소프트 쿨그레이 / 크림 틴트)
- **상태 보조 색상 (Sub-Accent)**: `Color(0xFF10B981)` (소프트 에메랄드 그린 - 무료배송 혜택 바)

---

## � 2. 페이지별 핵심 기능 코드 & 위젯 가이드 (Key Functional Code & Widgets)

개발자 및 팀원이 각 페이지를 수정할 때 숙지하면 유용한 **핵심 비즈니스 로직, 상태 관리 Provider, 특수 위젯 구현 방식**입니다.

---

### ① 마이페이지 & 설정 (`lib/views/my_page.dart` & `auth_viewmodel.dart`)

#### 🔑 핵심 기능 코드: Riverpod `AuthViewModel`을 활용한 헤더 동적 분기
`authProvider`의 유저 데이터 존재 여부(`isLoggedIn = user != null`)에 따라 상단 헤더 카드를 완벽히 다른 2가지 뷰로 렌더링합니다.

```dart
// lib/viewmodels/auth_viewmodel.dart
class AuthViewModel extends Notifier<User?> {
  @override
  User? build() => User(id: '1', name: '홍길동', email: 'hong@example.com');

  void login() => state = User(id: '1', name: '홍길동', email: 'hong@example.com');
  void logout() => state = null;
  void toggleAuth() => state == null ? login() : logout(); // 개발 및 테스트용 토글
}

final authProvider = NotifierProvider<AuthViewModel, User?>(AuthViewModel.new);
```

#### 🧩 헤더 분기 위젯 코드
```dart
// lib/views/my_page.dart
final user = ref.watch(authProvider);
final isLoggedIn = user != null;

// 헤더 렌더링
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: isLoggedIn
      ? _buildLoggedInHeader(context, ref, user)   // 로그인 시: 프로필/뱃지/쿠폰/포인트 스탯
      : _buildLoggedOutHeader(context, ref),      // 비로그인 시: 로그인 안내 + 대형 로그인 버튼
)
```

---

### ② 장바구니 (`lib/views/cart.dart` & `cart_viewmodel.dart`)

#### 🔑 핵심 기능 코드 1: 무료배송 계산 및 실시간 금액 합산 `cartSummaryProvider`
선택된 아이템만 골라내어 할인 적용가, 배송비(3만원 이상 시 무료), 최종 결제 금액을 실시간 계산합니다.

```dart
// lib/viewmodels/cart_viewmodel.dart
final cartSummaryProvider = Provider((ref) {
  final items = ref.watch(cartProvider);
  final selectedItems = items.where((item) => item.isSelected).toList();

  final int totalOriginalPrice = selectedItems.fold(0, (sum, item) => sum + item.totalOriginalPrice);
  final int totalSalePrice = selectedItems.fold(0, (sum, item) => sum + item.totalPrice);
  final int totalDiscount = totalOriginalPrice - totalSalePrice;

  // 30,000원 이상 시 무료배송 (미만 시 3,000원)
  final int freeShippingThreshold = 30000;
  final int shippingFee = (totalSalePrice >= freeShippingThreshold || selectedItems.isEmpty) ? 0 : 3000;
  final int finalPrice = totalSalePrice + shippingFee;

  return CartSummary(
    selectedCount: selectedItems.length,
    totalSalePrice: totalSalePrice,
    shippingFee: shippingFee,
    finalPrice: finalPrice,
    // ...
  );
});
```

#### 🧩 핵심 기능 위젯 2: 무료배송 달성률 동적 게이지 바 (`LinearProgressIndicator`)
구매 금액에 맞춰 0.0 ~ 1.0 비율로 늘어나는 파스텔 에메랄드 진행 바입니다.

```dart
// lib/views/cart.dart
final remainingForFree = summary.freeShippingThreshold - summary.totalSalePrice;
final double progress = summary.selectedCount == 0
    ? 0
    : (summary.totalSalePrice / summary.freeShippingThreshold).clamp(0.0, 1.0);

LinearProgressIndicator(
  value: progress,
  backgroundColor: const Color(0xFFA7F3D0),
  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
  minHeight: 6,
)
```

---

### ③ 카테고리 탐색 (`lib/views/category.dart`)

#### 🔑 핵심 기능 코드 & 위젯: 2-Pane Split View (사이드바 인디케이터 바)
화면을 `Row`로 분할하여 좌측 100px 사이드바와 우측 `Expanded` 상세 콘텐츠 영역을 결합했습니다. 좌측 선택 항목은 `AnimatedContainer`의 `left border`로 표현합니다.

```dart
// lib/views/category.dart
body: Row(
  children: [
    // 1. 좌측 탭 사이드바
    _buildLeftSidebar(),
    // 2. 우측 상세 영역
    Expanded(child: _buildRightContent(currentCat)),
  ],
)

// 좌측 사이드바 선택 위젯 패턴
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  decoration: BoxDecoration(
    color: isSelected ? Colors.white : AppTheme.background,
    border: Border(
      left: BorderSide(
        color: isSelected ? AppTheme.primary : Colors.transparent,
        width: 4, // 좌측 포인트 세로선
      ),
    ),
  ),
  child: Column(/* ... 아이콘 및 카테고리명 ... */),
)
```

---

### ④ 스마트 검색 (`lib/views/search.dart`)

#### 🔑 핵심 기능 코드 1: 최근 검색어 배열 가공 (중복 제거 및 최상단 삽입)
동일한 검색어가 다시 입력되면 이전 위치를 삭제하고 배열의 0번 인덱스로 올린 뒤 최대 10개만 유지합니다.

```dart
// lib/views/search.dart
void _executeSearch(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return;

  setState(() {
    _currentQuery = trimmed;
    _isSubmitted = true;

    // 중복 제거 후 가장 최근 검색어로 0번 인덱스에 추가
    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);
    if (_recentSearches.length > 10) _recentSearches.removeLast();
  });
}
```

#### 🔑 핵심 기능 코드 2: 검색어 멀티 조건 필터링 & 동적 정렬
상품의 이름(`name`), 카테고리(`category`), 설명(`description`), 태그(`tag`) 중 하나라도 매칭되면 필터링 후 지정된 옵션으로 정렬합니다.

```dart
// lib/views/search.dart
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
}
```

---

## 🚀 향후 발전 과제
1. **실제 API / DB 연동**: 더미 데이터에서 백엔드 REST/GraphQL API 클라이언트로 교체
2. **결제 PG 연동**: 장바구니 주문하기 버튼 클릭 시 결제 모듈(토스페이먼츠, 아임포트 등) 연동
3. **주문내역 / 배송조회 상세 페이지**: 마이페이지 주문/배송 조회 클릭 시 이동할 상세 페이지 구현

---
*작성일자: 2026년 9월 28일*  
*작성자: Antigravity Assistant*
