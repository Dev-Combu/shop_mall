# 📝 작업 일지 & Cafe24 API 연동 보고서 (2026-10-14)

## 📌 작업 개요
본 문서는 2026년 10월 14일에 진행된 **수지씨앤엘 (`suzicnl1`) Cafe24 쇼핑몰 OAuth 2.0(PKCE) 인증 구축 및 실시간 상품·카테고리 API 연동 작업**의 상세 내역과 핵심 구현 코드를 정리한 기술 보고서입니다.

---

## 🛠 주요 작업 내역 요약

| 구분 | 주요 변경 사항 | 파일 위치 |
| :--- | :--- | :--- |
| **환경변수 및 보안 설정** | `.env` 환경변수 구성(`Mall_ID`, `Client_ID`, `Access/Refresh Token`) 및 `.gitignore` 보호 | `.env` <br> `.gitignore` <br> `lib/main.dart` |
| **OAuth 2.0 (PKCE) 토큰 발급** | 모바일 앱 규격 PKCE (`code_verifier`, `code_challenge` S256) 인가 및 토큰 발급 스크립트 작성 | `scripts/get_cafe24_token.py` |
| **Cafe24 API 서비스 구축** | 상품 목록/단건 상세 조회, 전체 카테고리 조회(`limit=100`), 버전 헤더(`2026-09-01`) 및 예외 처리 | `lib/services/cafe24_api_service.dart` |
| **상품 모델 & 홈 연동** | `Product.fromCafe24Json` 파서 구현, 네트워크 이미지 렌더링, Fallback 더미 데이터 지원 | `lib/models/product.dart` <br> `lib/viewmodels/home_products_viewmodel.dart` <br> `lib/views/home.dart` |
| **상품 상세 페이지 연동** | 홈/카테고리에서 상품 클릭 시 `extra: product` 전달 및 단건 조회 API 연동 | `lib/config/router/router.dart` <br> `lib/views/product.dart` |
| **카테고리 모델 & 조회 연동** | `ShopCategory.fromCafe24Json` 구현, 전체(100개) 및 대분류(Depth 2) Provider 분리 | `lib/models/category.dart` <br> `lib/viewmodels/category_viewmodel.dart` |

---

## 🔑 1. Cafe24 OAuth 2.0 (PKCE) 인증 및 주의사항

- **PKCE 필수 적용**: Cafe24 Developers에서 모바일 앱으로 등록된 클라이언트는 인가 코드 요청 시 `code_challenge` (`S256`)와 토큰 교환 시 `code_verifier` 파라미터가 필수입니다.
- **Scope 구분자**: 다중 권한(`mall.read_product`, `mall.read_category`) 요청 시 콤마(`,`)가 아닌 공백(`%20`)으로 구분하여 인가받도록 처리했습니다.
- **API 버전 명시**: 요청 헤더에 `X-Cafe24-Api-Version: 2026-09-01`을 지정하여 최신 Cafe24 Admin API 규격과 호환되도록 설정했습니다.

---

## 🧩 2. 핵심 구현 코드 가이드

### ① Cafe24 상품 JSON 파싱 (`lib/models/product.dart`)
Cafe24 응답의 가격(`price`, `retail_price`), 할인율 자동 계산, 다중 이미지 필드(`list_image` → `detail_image` → `small_image` → `tiny_image`) 우선순위 파싱 및 프로토콜 보정(`//` → `https://`)을 수행합니다.

```dart
factory Product.fromCafe24Json(Map<String, dynamic> json) {
  final originalPriceDouble = double.tryParse(json['retail_price']?.toString() ?? '') ??
      double.tryParse(json['price']?.toString() ?? '0') ?? 0.0;
  final salePriceDouble = double.tryParse(json['price']?.toString() ?? '0') ?? 0.0;

  // 이미지 URL 우선순위 파싱
  String? rawImage = json['list_image'] as String?;
  if (rawImage == null || rawImage.isEmpty) rawImage = json['detail_image'] as String?;
  if (rawImage == null || rawImage.isEmpty) rawImage = json['small_image'] as String?;
  final imageUrl = _sanitizeImageUrl(rawImage);

  return Product(
    id: json['product_no']?.toString() ?? '',
    name: json['product_name']?.toString() ?? '상품명 없음',
    originalPrice: originalPrice,
    discountRate: discountRate,
    imageUrl: imageUrl,
    // ...
  );
}
```

### ② 상품 상세 페이지 즉시 전환 (`lib/config/router/router.dart` & `lib/views/product.dart`)
상품 카드 클릭 시 `context.push('/products/${product.id}', extra: product)`로 객체를 직접 전달하여 0ms 지연 없는 화면 렌더링을 보장하고, 딥링크 진입 시에는 `fetchProductDetail(productId)`로 단건 API를 호출합니다.

```dart
GoRoute(
  path: 'products/:id',
  builder: (BuildContext context, GoRouterState state) {
    final String id = state.pathParameters['id']!;
    final Product? extraProduct = state.extra as Product?;
    return ProductPage(productId: id, initialProduct: extraProduct);
  },
),
```

### ③ 전체 카테고리 트리 구조 분석 (`suzicnl1`)
`GET /api/v2/admin/categories?limit=100` 호출을 통해 총 100개의 카테고리를 수신하고 계층별로 분리했습니다.
- **Depth 1**: `24` (전체상품보기)
- **Depth 2 (대분류)**: `181` (롤매트), `42` (현관발매트), `44` (인조잔디), `45` (청소용품), `46` (생활 주방용품), `48` (침구)
- **Depth 3 (중분류)**: `parent_category_no`로 대분류와 연결된 세부 카테고리 (예: 쿠션롤매트, PVC롤매트, 카페트매트 등)
- **Depth 4 (소분류)**: 세부 품목 라인업

---
*작성일자: 2026년 10월 14일*

