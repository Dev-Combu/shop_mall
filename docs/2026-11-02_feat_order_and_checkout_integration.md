# 🛒 2026-11-02: `feat/order` 주문·결제·장바구니 시스템 및 Cafe24 실시간 연동 완료

본 문서는 `feat/order` 브랜치에서 진행된 **장바구니 실시간 양방향 동기화, Cafe24 공식 주문서 자동 채움 및 PG 결제 웹뷰 연동, 결제창 이탈 방지 가드, 주문 내역 및 실시간 배송 추적 시스템 구축**의 전체 작업 내용을 정리한 문서입니다.

---

## 📌 주요 마일스톤 및 성과 요약

| 구분 | 주요 구현 및 개선 내용 | 관련 파일 |
| :--- | :--- | :--- |
| **장바구니 실시간 연동** | WebKit 백그라운드 세션(`/order/basket.html`)과 앱 장바구니 실시간 양방향 동기화, 이중 백업 저장소 구축, 비회원 장바구니 로그인 자동 병합 | [`cafe24_web_cart_service.dart`](../lib/services/cafe24_web_cart_service.dart)<br>[`cart_viewmodel.dart`](../lib/viewmodels/cart_viewmodel.dart) |
| **장바구니 꼬임 방지 안전망** | 일시적 빈 스냅샷 수신 시 로컬 데이터 삭제 차단, 서버로 품목 자동 재적재(Push) 복구, HTML 테이블 DOM 스크래핑 폴백 적용 | [`cart_viewmodel.dart`](../lib/viewmodels/cart_viewmodel.dart)<br>[`cafe24_web_cart_service.dart`](../lib/services/cafe24_web_cart_service.dart) |
| **통합 결제 런처** | 주문서 진입 전 웹 세션 유효성 검증 및 백그라운드 무자각 자동 재로그인(카카오싱크/네이버/일반 AuthSSL), 세션 복구 시트 연결 | [`cafe24_checkout_launcher.dart`](../lib/views/share/cafe24_checkout_launcher.dart) |
| **주문서 작성 페이지** | 단품 바로구매 및 장바구니 선택 주문 네이티브 폼, 다음 우편번호 검색 시트 연동, 적립금 사용, 회원 기본 배송지 자동 반영 | [`checkout.dart`](../lib/views/checkout.dart)<br>[`postcode_search_sheet.dart`](../lib/views/share/postcode_search_sheet.dart) |
| **Cafe24 공식 결제 웹뷰** | 단건 옵션 선택 바로구매(`product_submit(1)`), 다건 품목 검사 및 장바구니 주문(`Basket.orderSelectBasket`), 배송지·결제수단·약관 자동 주입 | [`cafe24_order_webview.dart`](../lib/views/cafe24_order_webview.dart) |
| **결제 웹뷰 화면 이탈 차단** | 주문서 도달 후 로고·GNB·푸터 CSS 숨김(`display: none`), 주문서 외 쇼핑몰 홈/상품/마이페이지 이동 네비게이션 가드 차단 | [`cafe24_order_webview.dart`](../lib/views/cafe24_order_webview.dart) |
| **PG 결제 앱 연동** | 카드사 앱카드, 간편결제(카카오페이/토스/ISP 등), Android `intent://`, fallback URL 처리 및 OS 권한 설정 | `AndroidManifest.xml`<br>`Info.plist` |
| **주문 관리 및 배송 추적** | 결제 완료 주문번호 영구 기록, Cafe24 Admin API 연동 주문 목록/상세 조회, 실시간 택배 배송조회 바텀 시트 | [`orders.dart`](../lib/views/orders.dart)<br>[`order_detail.dart`](../lib/views/order_detail.dart)<br>[`delivery_tracking_sheet.dart`](../lib/views/share/delivery_tracking_sheet.dart) |

---

## 1. 장바구니 시스템 전면 고도화 & Cafe24 실시간 동기화

### 1-1. Cafe24 웹 장바구니 서비스 신설 ([`Cafe24WebCartService`](../lib/services/cafe24_web_cart_service.dart))
* **백그라운드 WebKit 세션 연동**:
  * 비가시성 WebViewController를 통해 `https://suzicnl.com/order/basket.html` 세션을 유지하고, 단일 큐(`_enqueue`) 직렬 처리를 통해 동시 페이지 이동 및 스크립트 충돌을 방지했습니다.
  * 상품 추가(`addItem`), 수량 수정(`updateQuantity`), 삭제(`deleteItem`), 전체 비우기(`clearBasket`)를 WebKit 세션에 직접 반영합니다.
* **iOS WebKit 예외 방지**:
  * `WKWebView.evaluateJavaScript`에서 Promise 반환 시 발생하는 `PlatformException(FWFEvaluateJavaScriptError)`을 방지하기 위해 모든 브라우저 스크립트를 동기식 즉시실행함수(`(function() { ... })()`) 구조로 표준화했습니다.
* **HTML 테이블 DOM 스크래핑 폴백**:
  * Cafe24 스킨의 비동기 스크립트 지연으로 전역 변수 `aBasketProductData`가 비어있는 경우에도, 실제 장바구니 테이블 체크박스(`basket_chk_id_`)와 상품 링크(`product_no=`), 수량 인풋을 직접 파싱하여 품목을 100% 누락 없이 수집합니다.
* **웹 세션 유효성 감지 및 무자각 자동 복구**:
  * `CAPP_ASYNC_METHODS.IS_LOGIN`, `iscache=F` 쿠키, 로그아웃 링크를 통해 웹 세션을 판별하고, 만료 시 백그라운드에서 카카오싱크(`@k`), 네이버(`@n`), 일반 ID/PW(`MemberAction.login`) 계정의 무자각 재로그인을 수행합니다.

### 1-2. 장바구니 ViewModel 고도화 ([`CartViewModel`](../lib/viewmodels/cart_viewmodel.dart))
* **이중 저장소(`_storageKey` & `_backupStorageKey`) 구축**:
  * 로컬 보안 저장소(`FlutterSecureStorage`)에 회원별 키(`cafe24_db_cart_${memberId}`)와 안전 백업 키(`${key}_backup`)를 함께 유지하여 기기 재부팅이나 비정상 상태에서도 복원할 수 있도록 안전망을 마련했습니다.
* **비회원 장바구니 자동 병합**:
  * 비회원 상태에서 장바구니에 담아둔 상품이 있다면 로그인 성공 시 회원 장바구니로 자동 수량 합산 및 병합(`mergedGuestItems`)합니다.
* **장바구니 꼬임 방지 안전망 (핵심 결함 수정)**:
  * 원격 스냅샷이 일시적 세션 오류 등으로 0개(`webItemsParsed.isEmpty`)로 수신되더라도, 사용자가 앱에서 직접 '전체 비우기'를 누른 것이 아니라면 **로컬 장바구니를 절대 지우지 않고 유지**합니다.
  * 오히려 세션 불일치로 판단하여 로컬에 보관된 품목들을 Cafe24 서버로 **즉시 재전송(Push)하여 서버 장바구니를 자동 복구**합니다.
  * 로컬이 비어있고 원격에 상품이 있는 경우에는 원격 상품을 삭제하지 않고 로컬로 가져와 복원합니다.
* **품목 누락 방지 (기본 Product 객체 폴백 생성)**:
  * Admin API 상품 상세 조회가 지연되거나 실패하더라도 스냅샷의 상품명과 가격을 이용해 기본 `Product` 객체를 생성하여 품목이 증발하지 않도록 보장했습니다.

### 1-3. 장바구니 화면 UX 개선 ([`CartPage`](../lib/views/cart.dart))
* 무료배송(30,000원 기준) 달성 프로그레스 게이지 바 및 잔여 금액 안내.
* 전체 선택 / 선택 삭제 / 수량 증감 실시간 결제 예정 금액 합산.
* 웹 세션 단절 시 상단에 **`[다시 연결]`** 원클릭 안내 배너([`_buildSessionReconnectBanner`](../lib/views/cart.dart)) 노출.
* 상단 새로고침 아이콘 및 당겨서 새로고침(`RefreshIndicator`) 시 강제 리로드(`refreshFromCafe24(forceReload: true)`).
* 상품 상세에서 장바구니 담기 완료 시 장바구니 바로가기 모달([`CartAddedModal`](../lib/views/share/cart_added_modal.dart)) 노출.

---

## 2. 주문서 작성 및 통합 결제 프로세스

### 2-1. 통합 결제 런처 ([`cafe24_checkout_launcher.dart`](../lib/views/share/cafe24_checkout_launcher.dart))
* 결제 웹뷰 진입 전 쇼핑몰 회원 세션의 유효성을 선검증하고, 필요 시 무자각 자동 복구를 실행하는 공통 헬퍼([`ensureCheckoutWebSession`](../lib/views/share/cafe24_checkout_launcher.dart)) 구현.
* OAuth 쿠키까지 만료된 경우 계정 유형에 맞게 카카오싱크 모달 시트([`KakaoSyncAuthSheet`](../lib/views/share/kakao_sync_auth_sheet.dart)), 네이버 모달 시트([`NaverAuthSheet`](../lib/views/share/naver_auth_sheet.dart)), 또는 로그인 페이지로 연결하여 세션을 복구한 뒤 결제를 진행합니다.
* 결제 창을 닫거나 취소하고 나왔을 때도 즉시 `refreshFromCafe24()`를 호출하여 장바구니와 주문 상태를 동기화합니다.

### 2-2. 네이티브 주문서 작성 화면 ([`CheckoutPage`](../lib/views/checkout.dart))
* **주문 정보 확인 및 배송지 입력**:
  * 수령인 이름, 연락처, 우편번호, 기본 주소, 상세 주소, 배송 요청사항 입력 폼 제공.
  * 다음(Daum) 우편번호 검색 서비스 바텀 시트([`PostcodeSearchSheet`](../lib/views/share/postcode_search_sheet.dart)) 연동.
  * 주문 시 입력/수정한 배송지 정보를 Cafe24 서버 회원 배송지 주소록(`upsertCustomerShippingAddress`)에 비동기 자동 반영.
* **적립금/포인트 사용**:
  * 회원의 보유 포인트 조회, 전액 사용 버튼 및 결제 금액 한도 내 유효성 검사.
* **결제 수단 선택 및 테스트 결제 모드**:
  * 신용/체크카드, 카카오페이, 네이버페이, 무통장입금 및 개발/심사용 모의 테스트 결제 모드(`placeDemoOrder`) 지원.

---

## 3. Cafe24 공식 주문서 + PG 안전결제 웹뷰 ([`Cafe24OrderWebViewPage`](../lib/views/cafe24_order_webview.dart))

### 3-1. 스마트 주문 진입 파이프라인
* **단건 바로구매 (`!fromCart && items.length == 1`)**:
  * 상품 상세페이지(`/product/detail.html?product_no=...`)로 직행하여 필수 옵션(구분선/플레이스홀더 제외) 자동 선택 및 수량 지정 후 `product_submit(1)`을 실행해 공식 주문서로 다이렉트 진입합니다.
* **다건 장바구니 주문 (`fromCart || items.length > 1`)**:
  * `/order/basket.html`에 진입하여 현재 장바구니 상태를 점검하고, 누락된 품목이 있다면 상세페이지에서 자동 보충한 뒤 선택 품목에 대한 `Basket.orderSelectBasket`을 실행해 주문서로 진입합니다.

### 3-2. 주문서 사전 정보 자동 주입 (`_prefillOrderForm`)
* 공식 주문서(`/order/orderform.html`) 도달 시 배송지 수령인, 우편번호, 주소, 휴대폰 번호, 이메일, 주문 요청사항, 적립금 사용액, 선택 결제수단을 DOM에 자동 매핑합니다.
* 결제 진행 필수 약관 전체 동의를 자동으로 체크합니다.

### 3-3. 결제 웹뷰 내부 화면 이탈 방지 (Navigation Guard & CSS 인젝션)
* **주문서 외 페이지 이동 차단 (Navigation Guard)**:
  * 주문서 화면(`_isOrderFormReady`)에 도달한 후, 쇼핑몰 홈(`/index.html`), 상품 상세(`/product/...`), 장바구니(`/order/basket`), 마이페이지(`/myshop`) 등 주문과 무관한 페이지 링크 클릭을 `NavigationDecision.prevent`로 자동 차단합니다.
  * 사용자가 링크 터치 시 `"주문 및 결제 진행 중에는 다른 페이지로 이동할 수 없습니다."` 스낵바를 표시합니다.
  * PG 결제사(카카오페이, 네이버페이, 토스, 카드사 안심클릭, KCP, 이니시스 등), 주소검색 레이어, 결제 완료/실패 페이지는 화이트리스트로 정상 허용합니다.
* **불필요한 헤더/푸터 UI 숨김 (CSS 주입)**:
  * 주문서가 로드되는 즉시 상단 쇼핑몰 로고, GNB 햄버거 메뉴, 장바구니 아이콘, 푸터 링크를 CSS(`display: none !important`)로 숨겨 **앱 전용 결제창처럼 결제 폼만 깔끔하게 노출**시켰습니다.

### 3-4. 외부 PG 결제 앱 호출 및 딥링크 지원
* 카드사 앱카드, 간편결제 앱(카카오페이, 네이버페이, 토스, ISP 등) 및 Android `intent://` URL 파싱, 플레이스토어 fallback, 마켓 스킴 연동을 구현했습니다.
* `android/app/src/main/AndroidManifest.xml`에 금융/결제사 패키지 `<queries>` 및 intent filter 전면 추가.
* `ios/Runner/Info.plist`에 `LSApplicationQueriesSchemes` 등록 완료.

---

## 4. 주문 내역 관리 및 실시간 배송 추적

### 4-1. 주문 내역 상태 관리 ([`OrderRecord`](../lib/models/order.dart) & [`OrderViewModel`](../lib/viewmodels/order_viewmodel.dart))
* Cafe24 결제 완료 후 발급된 실제 주문번호(`YYYYMMDD-NNNNNNN`)를 기반으로 로컬 영구 보존.
* Cafe24 Admin API(`GET /api/v2/admin/orders`)를 통해 쇼핑몰 웹사이트에서 직접 주문한 내역까지 통합 조회하고 최신 배송 상태(송장번호, 택배사)를 실시간 동기화합니다.
* 주문 성공 시 전용 팝업 다이얼로그([`OrderCompleteDialog`](../lib/views/share/order_complete_dialog.dart)) 노출.

### 4-2. 주문 목록 및 상세 내역 화면
* **주문/배송 목록 페이지 ([`OrdersPage`](../lib/views/orders.dart))**:
  * 주문 상태별(전체, 입금전, 배송준비중, 배송중, 배송완료, 취소/교환/반품) 탭 필터링 및 주문별 상품 요약 카드 제공.
  * 당겨서 새로고침을 통해 Cafe24 최신 배송 상태 실시간 갱신.
* **주문 상세 내역 페이지 ([`OrderDetailPage`](../lib/views/order_detail.dart))**:
  * 주문 번호, 주문 일시, 주문 상품 상세, 결제 금액 명세(상품금액, 할인금액, 배송비, 적립금 사용, 최종 결제금액), 배송지 수령인 및 요청사항 상세 제공.

### 4-3. 실시간 택배 배송 추적 ([`DeliveryTrackingSheet`](../lib/views/share/delivery_tracking_sheet.dart))
* 주문 내역 및 상세 화면에서 배송 중/배송 완료 상품의 송장번호 클릭 시, 택배사 공식 배송조회 웹뷰 바텀 시트를 띄워 실시간 이동 경로 및 배송 기사 연락처를 바로 확인할 수 있도록 구현했습니다.

---

## 5. 변경 및 추가 파일 목록

### 📁 신규 생성 파일 (Untracked Files)
1. `lib/models/order.dart`: 주문 내역, 주문 상품, 배송지 및 결제 정보 모델
2. `lib/services/cafe24_web_cart_service.dart`: Cafe24 WebKit 세션 장바구니 조작 및 무자각 재로그인 엔진
3. `lib/viewmodels/order_viewmodel.dart`: 주문 내역 저장 및 Cafe24 Admin API 실시간 동기화 Notifier
4. `lib/views/cafe24_order_webview.dart`: Cafe24 공식 주문서 사전 채움, PG 안전결제, 이탈 방지 가드 웹뷰
5. `lib/views/checkout.dart`: 주문/결제 정보 입력 및 결제 수단 선택 화면
6. `lib/views/orders.dart`: 주문/배송 내역 목록 및 상태 필터링 화면
7. `lib/views/order_detail.dart`: 단일 주문 건의 상세 배송/결제 정보 확인 화면
8. `lib/views/share/cafe24_checkout_launcher.dart`: 세션 선검증 및 Cafe24 결제창 통합 런처
9. `lib/views/share/cart_added_modal.dart`: 장바구니 상품 추가 완료 바텀 시트
10. `lib/views/share/delivery_tracking_sheet.dart`: 실시간 택배 송장 배송조회 웹뷰 시트
11. `lib/views/share/order_complete_dialog.dart`: 주문 완료 안내 다이얼로그
12. `lib/views/share/postcode_search_sheet.dart`: 다음 우편번호 검색 웹뷰 바텀 시트

### 📝 주요 수정 파일 (Modified Files)
1. `lib/config/router/router.dart`: `/checkout`, `/orders`, `/orders/:id` 라우트 등록
2. `lib/viewmodels/cart_viewmodel.dart`: 장바구니 꼬임 방지, 이중 백업 저장소, 서버 재적재 복원 로직 추가
3. `lib/views/cart.dart`: 세션 단절 시 `[다시 연결]` 배너, 강제 새로고침 연동
4. `lib/views/product.dart`: 실시간 리뷰 연동 및 바로구매/장바구니 런처 연결
5. `lib/services/cafe24_api_service.dart`: 주문 목록, 주문 상세, 배송지 주소록, 상품 리뷰 API 연동
6. `lib/viewmodels/auth_viewmodel.dart`: 회원 배송지 정보 Cafe24 서버 DB 보강 연동
7. `android/app/src/main/AndroidManifest.xml`: PG 결제사 앱 스킴 및 intent 지원 설정
8. `ios/Runner/Info.plist`: PG사 및 간편결제 앱 URL 스킴 화이트리스트 등록

