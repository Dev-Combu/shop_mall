# 📅 수지씨앤엘 (shopmall) 날짜별 개발 진행사항 총괄

본 문서는 프로젝트 초기 구축부터 UI/UX 리팩토링, Cafe24 쇼핑몰 실시간 API 연동 및 OAuth 2.0 자동 갱신 시스템 구축까지의 **전체 진행 내역을 날짜별로 정리한 문서**입니다.

---

## 📌 날짜별 요약 타임라인

| 날짜 | 주요 마일스톤 | 상세 문서 링크 |
| :--- | :--- | :--- |
| **2026-09-21** | 프로젝트 초기 세팅, `GoRouter` & `Riverpod` 도입, 바텀 네비게이션 및 기본 화면 구성 | 본 문서 1절 참조 |
| **2026-09-26** | 네비게이션 디렉토리 구조 정리 및 페이지 라우팅 개선 | 본 문서 2절 참조 |
| **2026-09-28** | 전 화면 UI/UX 전면 리팩토링 및 3단계 브랜드 테마 시스템(`AppTheme`) 구축 | [2026-09-28_ui_and_theme_refactoring.md](./2026-09-28_ui_and_theme_refactoring.md) |
| **2026-10-14** | Cafe24 OAuth 2.0(PKCE) 인증, 실시간 상품/카테고리(100개) API 연동, 상세 페이지 연결 | [2026-10-14_cafe24_api_and_data_integration.md](./2026-10-14_cafe24_api_and_data_integration.md) |
| **2026-10-16** | 카테고리 탭 대·중분류 실시간 연동 및 OAuth 토큰 자동 리프레시(`FlutterSecureStorage`) 구현 | [2026-10-16_oauth_auto_refresh_and_category_sync.md](./2026-10-16_oauth_auto_refresh_and_category_sync.md) |

---

## 1. 2026-09-21: 프로젝트 초기 세팅 및 기본 구조 구축
- **아키텍처 및 상태 관리 도입**:
  - MVVM 패턴 기반 디렉토리 구조(`config`, `models`, `views`, `viewmodels`, `services`) 설계
  - `flutter_riverpod` 및 `go_router` 패키지 적용
- **공통 레이아웃 및 라우팅**:
  - `ScaffoldShellLayout`을 통한 하단 탭 바(`BottomNavigationBar`) 구성 (홈, 카테고리, 검색, 장바구니, 마이페이지)
  - `/`, `/products/:id`, `/search`, `/cart`, `/my_page`, `/contact` 등 주요 라우트 정의
- **기본 쇼핑몰 화면 프로토타입 구현**:
  - 홈 화면 배너, 카테고리, 상품 그리드 초기 레이아웃 작성

---

## 2. 2026-09-26: 라우팅 및 화면 모듈화 개선
- **디렉토리 및 컴포넌트 정리**:
  - 공통 위젯(`views/share/`) 분리 및 네비게이션 상태 관리(`BottomNavViewModel`) 고도화
  - 각 탭 화면 전환 시 상태 유지 및 라우팅 안정성 개선

---

## 3. 2026-09-28: UI/UX 전면 개편 및 디자인 테마 시스템 구축
> 상세 내역: [`docs/2026-09-28_ui_and_theme_refactoring.md`](./2026-09-28_ui_and_theme_refactoring.md)

- **브랜드 테마 정립 (`lib/config/theme/theme.dart`)**:
  - Primary(`#1E293B`), Point(`#E53935`), Surface(`#F8FAFC`) 3단계 컬러 팔레트 적용
- **화면별 고도화**:
  - **홈(`home.dart`)**: 자동 롤링 배너 슬라이더, 원형 카테고리 칩, 할인율이 반영된 상품 카드 UI
  - **카테고리(`category.dart`)**: 2-Pane Split View (좌측 대분류 사이드바 + 우측 배너 및 세부 카테고리 그리드)
  - **스마트 검색(`search.dart`)**: 최근 검색어 관리, 인기 검색어 순위, 다중 조건 필터 및 가격순 정렬
  - **장바구니(`cart.dart`)**: 무료배송(3만원 기준) 달성 게이지 바, 수량 조절 및 결제 예정 금액 실시간 합산
  - **마이페이지(`my_page.dart`)**: 로그인/비로그인 상태 분기 헤더 및 주문 현황 대시보드

---

## 4. 2026-10-14: Cafe24 쇼핑몰 실시간 API 연동
> 상세 내역: [`docs/2026-10-14_cafe24_api_and_data_integration.md`](./2026-10-14_cafe24_api_and_data_integration.md)

- **환경변수 및 OAuth 2.0 (PKCE) 구축**:
  - `.env` 기반 `suzicnl1` 쇼핑몰 인증 정보 관리 및 PKCE(`S256`) 기반 Access/Refresh Token 발급
  - `mall.read_product`, `mall.read_category` 권한 확보 및 불필요한 디버그 로그 정리
- **실시간 상품 연동 (`Cafe24ApiService` & `home_products_viewmodel.dart`)**:
  - `GET /api/v2/admin/products` 연동 및 `Product.fromCafe24Json` 모델 변환 구현
  - 홈 화면 신상품/베스트 섹션에 실제 Cafe24 상품 이미지 및 가격 바인딩
- **상품 상세 페이지(`product.dart`) 연동**:
  - 상품 클릭 시 `extra: product` 전달로 즉시 상세 화면을 표시하고, 수량 변경·장바구니 담기·바로 구매 인터랙션 연결
- **실시간 카테고리 API 연동 (`category_viewmodel.dart`)**:
  - `GET /api/v2/admin/categories?limit=100`으로 전체 100개 카테고리(Depth 1~4) 로드 및 대분류(Depth 2: 롤매트, 현관발매트, 인조잔디, 청소용품, 생활 주방용품, 침구) 추출

---

## 5. 2026-10-16: 카테고리 탭 완성 및 OAuth 토큰 자동 리프레시 구축
> 상세 내역: [`docs/2026-10-16_oauth_auto_refresh_and_category_sync.md`](./2026-10-16_oauth_auto_refresh_and_category_sync.md)

- **카테고리 탭(`category.dart`) 전체 카테고리 & 실시간 상품 연동**:
  - 좌측 대분류(Depth 2) 선택 시 해당 카테고리의 실제 하위 중분류(Depth 3) 목록을 그리드에 동적 매핑
  - 세부 카테고리 클릭 시 선택 강조 및 하단 추천 상품 실시간 필터링(`Product.matchesCategory`) 구현
  - 카테고리 탭 내 추천 상품에 Cafe24 실제 네트워크 이미지 표시 및 클릭 시 상세 페이지(`product.dart`) 즉시 이동 연결
- **OAuth 2.0 토큰 자동 리프레시 시스템 (`cafe24_api_service.dart`)**:
  - **선제적 갱신**: API 호출 전 만료 시각(`CAFE24_EXPIRES_AT`)을 체크하여 만료 시 자동 리프레시 수행
  - **401 자동 복구**: `401 (access_token time expired)` 발생 시 자동으로 `refresh_token`을 사용해 새 토큰을 발급받고 원래 API를 1회 재요청
  - **동시성 제어 & 영구 저장**: 다중 API 동시 호출 시 리프레시 중복 실행을 방지(`_refreshFuture`)하고, 재발급된 `access_token`과 `refresh_token`을 `FlutterSecureStorage`에 안전하게 영구 저장

