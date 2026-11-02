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
| **2026-10-16 ~ 10-17** | Cafe24 일반 Auth 전체 구축: 회원가입·로그인(`AuthSSL`), 회원 정보 확인(휴대폰 번호 복호화 폴링), 회원탈퇴 | [2026-10-16_cafe24_auth_and_profile_integration.md](./2026-10-16_cafe24_auth_and_profile_integration.md) |
| **2026-11-02** | `feat/order`: 장바구니 실시간 동기화 & 꼬임 방지, Cafe24 공식 주문서 자동 채움 및 PG 결제 웹뷰 연동, 결제창 이탈 방지 가드, 주문 내역 및 배송 추적 | [2026-11-02_feat_order_and_checkout_integration.md](./2026-11-02_feat_order_and_checkout_integration.md) |

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

---

## 6. 2026-10-16 ~ 2026-10-17: Cafe24 일반 Auth 전체 구축 (회원가입·로그인·회원정보 확인·회원탈퇴)
> 상세 내역: [`docs/2026-10-16_cafe24_auth_and_profile_integration.md`](./2026-10-16_cafe24_auth_and_profile_integration.md)

- **Cafe24 실시간 회원가입 및 관리자 DB 연동 ([`SignUpPage`](../lib/views/signup.dart))**:
  - 100% 네이티브 UI 뒤에서 비가시성(`1x1`) WebKit 엔진이 Cafe24 공식 `AuthSSLManager` 일회용 SSL 암호화를 수행하여 `"잘못된 요청입니다."` 오류를 원천 해결
  - 가입 완료 즉시 Cafe24 쇼핑몰 관리자(`고객 관리 > 회원 조회`)에 신규 회원이 실시간 등록되고 앱 내 자동 로그인 세션 생성
- **Cafe24 실시간 회원 로그인 및 휴대폰 번호 복호화 폴링 ([`LoginPage`](../lib/views/login.dart))**:
  - 웹뷰 팝업 없이 네이티브 UI에서 아이디/비밀번호 입력 시 Cafe24 `MemberAction.login` 암호화 로그인 수행
  - 1단계로 마이쇼핑(`/myshop/index.html`)에서 등급, 적립금, 쿠폰 수를 파싱하고, 2단계로 회원정보 수정(`/member/modify.html`)으로 이동하여 `AuthSSLManager`가 비동기로 복호화해 채워 넣는 휴대폰 번호(`mobile[]`), 이메일(`email1`), 실명(`name`)을 `200ms` 간격 폴링으로 정확히 추출
- **회원 정보 확인 전용 페이지 ([`ProfilePage`](../lib/views/profile.dart))**:
  - 회원 기본 정보(아이디, 실명, 이메일, 휴대폰 번호, 등급), 쇼핑 혜택(적립금, 쿠폰, 주문 내역), Cafe24 연동 상태 카드 제공
  - 페이지 진입 및 새로고침(`Pull-to-Refresh`) 시 백그라운드에서 `/member/modify.html`의 `AuthSSLManager` 복호화 필드를 폴링하여 최신 연락처·이메일·적립금 실시간 동기화
- **회원탈퇴 기능 ([`WithdrawalPage`](../lib/views/withdrawal.dart))**:
  - 네이티브 UI에서 탈퇴 유의사항 안내, 탈퇴 사유 선택, 비밀번호 재확인을 거쳐 Cafe24 서버의 `memberLeaveAction` 탈퇴 처리 및 로컬 보안 세션(`FlutterSecureStorage` & WebKit 쿠키) 완전 파기

---

## 7. 2026-11-02: `feat/order` 주문·결제·장바구니 시스템 및 Cafe24 실시간 연동 완료
> 상세 내역: [`docs/2026-11-02_feat_order_and_checkout_integration.md`](./2026-11-02_feat_order_and_checkout_integration.md)

- **장바구니 실시간 양방향 동기화 & 꼬임 방지 안전망 ([`Cafe24WebCartService`](../lib/services/cafe24_web_cart_service.dart) & [`CartViewModel`](../lib/viewmodels/cart_viewmodel.dart))**:
  - 백그라운드 WebKit 세션(`/order/basket.html`)과 실시간으로 상품 추가, 수량 변경, 삭제 연동.
  - 일시적 빈 스냅샷 수신 시 로컬 데이터 삭제 차단, 서버로 품목 자동 재적재(Push) 복구 및 이중 백업 저장소 구축.
  - HTML 테이블 DOM 스크래핑 폴백 적용으로 `aBasketProductData` 미로딩 시에도 100% 품목 추출.
  - 웹 세션 만료 시 무자각 자동 재로그인 및 장바구니 상단 `[다시 연결]` 안내 배너 제공.
- **통합 결제 런처 및 네이티브 주문서 작성 화면 ([`cafe24_checkout_launcher.dart`](../lib/views/share/cafe24_checkout_launcher.dart) & [`CheckoutPage`](../lib/views/checkout.dart))**:
  - 결제 전 회원 세션 선검증 및 무자각 복구, 다음 우편번호 검색 시트([`PostcodeSearchSheet`](../lib/views/share/postcode_search_sheet.dart)) 연동, 적립금 사용, 회원 기본 배송지 자동 동기화.
- **Cafe24 공식 주문서 + PG 안전결제 웹뷰 ([`Cafe24OrderWebViewPage`](../lib/views/cafe24_order_webview.dart))**:
  - 단건 옵션 선택 바로구매(`product_submit(1)`), 다건 품목 검사 및 장바구니 주문(`Basket.orderSelectBasket`), 수령인/배송지/결제수단/약관 자동 채움.
  - **결제 웹뷰 화면 이탈 차단**: 주문서 도달 후 로고·GNB·푸터 CSS 숨김(`display: none`), 주문서 외 쇼핑몰 홈/상품/마이페이지 이동 네비게이션 가드 차단.
  - 카드사 앱카드, 간편결제(카카오페이/토스/ISP 등), Android `intent://` 외부 앱 호출 및 OS 권한(`AndroidManifest.xml`, `Info.plist`) 보강.
- **주문 내역 관리 및 실시간 배송 추적 ([`OrdersPage`](../lib/views/orders.dart) & [`DeliveryTrackingSheet`](../lib/views/share/delivery_tracking_sheet.dart))**:
  - Cafe24 Admin API 연동 실시간 주문 목록/상세 조회, 결제 완료 주문번호 영구 기록, 택배사 공식 실시간 배송조회 바텀 시트 구현.



