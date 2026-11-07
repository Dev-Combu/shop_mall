# 🛠️ Cafe24 상품 옵션 시스템 구축 및 장바구니·주문서 결제 연동 안정화

- **작성일자**: 2026-11-07
- **관련 커밋/영역**: `models`, `services`, `views/product.dart`, `views/cart.dart`, `views/cafe24_order_webview.dart`, `views/share/cafe24_checkout_launcher.dart`
- **핵심 목표**:
  1. Front API 기반 필수/추가 상품 옵션 시스템 전면 구축
  2. 음수 차감 옵션 금액(-26,400원 등) 및 단가 정밀 계산 동기화
  3. 장바구니 새로고침 시 옵션 정보 영구 보존 및 대괄호 중복 정리
  4. WebKit JS 구문 오류 및 "선택된 상품이 없습니다" / "주문서로 이동할 수 없습니다" 오류 원천 차단
  5. Cafe24 안전결제 웹뷰 화면의 상품 썸네일 이미지 및 상품명 복원

---

## 1. 배경 및 주요 해결 과제

| 번호 | 주요 이슈 | 원인 분석 | 해결 방안 |
| :--- | :--- | :--- | :--- |
| **1** | 상품 옵션 미표시 및 임의 자동선택 | 상세 화면에 옵션 선택 UI가 없고, 스크립트가 첫 번째 옵션을 무조건 강제 선택함 | Front API (`/api/v2/products/{id}/options`) 연동 및 필수/추가 드롭다운 UI 구현, 사용자 선택 옵션만 1:1 매칭 |
| **2** | 추가 상품 옵션 강제 필수화 | `required_option == 'F'`인 선택 옵션을 구분하지 않고 검증함 | `required_option` 속성 판별하여 필수 옵션만 검증하고 '선택 안 함' 지원 |
| **3** | 장바구니 새로고침 시 옵션 증발 | 원격 스냅샷 파싱 시 기존 로컬 품목의 `selectedOptions`와 `optionAdditionalAmount`를 누락함 | `_parseRawWebItems`에서 기존 장바구니 품목과 1:1 매칭하여 옵션 및 금액 영구 보존 |
| **4** | 장바구니와 주문서 간 가격 불일치 | 옵션 차감금액(`-26,400원`)이 장바구니 단가에 미반영되어 본품가(32,000원)로 표시됨 | `optionAdditionalAmount` 음수 차감액 계산 및 `item.unitSalePrice` 단가 바인딩 |
| **5** | 옵션 문구 중복 (`[[옵션: ...]]`) | 스냅샷의 `[옵션: ...]`에 UI의 `'옵션: ...'`이 덧붙여져 대괄호가 중복 표시됨 | `formattedOptionsText` 및 `_cleanOptionText` 정규화로 깔끔한 옵션명만 추출 |
| **6** | WebKit JS 구문 에러 및 주문 실패 | `s.replace(/[\s\-_/]/g, '')` 정규식의 문자 클래스 범위 역순 문법 에러로 `addItem` 폭발 | `s.replace(/\s+/g, '').replace(/[-_/]/g, '')`로 안전 분리하여 구문 에러 0% 방어 |
| **7** | "선택된 상품이 없습니다" / "이동 불가" | 체크박스 ID 불일치로 미체크 상태에서 주문 함수 호출, 빈 장바구니 상태 주문서 요청 | 실제 노출된 "전체상품주문"(`btnSubmit`) 직접 클릭 및 비어있을 시 상품 자동 보충 가드 추가 |
| **8** | 주문서 내 상품 이미지 빈 박스 현상 | 외부 이동 링크 차단용 CSS `a[href*="/product/"] { display: none }`가 썸네일 `<a>`까지 숨김 | 전역 숨김 제거, 썸네일 `img` 표시 보장 및 `pointer-events: none` 클릭 차단으로 변경 |

---

## 2. 세부 구현 및 변경 내역

### 2.1 상품 옵션 모델링 및 Front API 연동
- **[`lib/models/product_option.dart`](../lib/models/product_option.dart)**
  - `ProductOptionValue`: 옵션값 텍스트, 추가/차감 금액(`additionalAmount`), valueNo 파싱. 텍스트 내 `(-26,400)` 형태의 금액을 정규식으로 감지하여 음수 차감액도 완벽 파싱.
  - `formattedAdditionalAmount`: 양수는 `(+5,000원)`, 음수는 `(-26,400원)` 형식 지원.
  - `ProductOptionGroup`: `required_option == 'T'`인 경우만 필수(`isRequired = true`), `'F'`인 경우 비필수 선택 옵션으로 분류.
  - `ProductOptionsData`: 필수 옵션 그룹(`requiredGroups`)과 추가 상품 옵션 그룹(`additionalGroups`) 분리 제공.
- **[`lib/services/cafe24_api_service.dart`](../lib/services/cafe24_api_service.dart)**
  - `fetchProductOptions(String productNo)`: Cafe24 Front API (`GET /api/v2/products/{product_no}/options`) 연동.

### 2.2 상품 상세 화면 옵션 선택 UI 구축
- **[`lib/views/product.dart`](../lib/views/product.dart)**
  - `_buildOptionsSection`:
    - **본품 옵션 드롭다운**: 필수 항목(`*`)과 선택 항목 구분.
    - **추가 상품 옵션 드롭다운**: `'선택 안 함 (구매 안 함)'` 기본값 제공으로 강제 구매 방지.
    - **선택 내역 및 추가금액 카드**: 선택된 옵션 항목별 명칭과 개당 추가/차감 금액 실시간 표시.
  - `_effectiveUnitSalePrice`: 본품 판매가에 옵션 추가/차감액(`_totalOptionAdditionalAmount`)을 합산한 실시간 단가 계산.
  - `_validateRequiredOptions`: `group.isRequired == true`인 필수 옵션만 유효성 검사 수행.
  - [장바구니 담기] 및 [바로 구매] 버튼에 `selectedOptions` 및 `optionAdditionalAmount` 전달 연결.

### 2.3 장바구니 단가·옵션 표기 및 동기화 개선
- **[`lib/models/cart_item.dart`](../lib/models/cart_item.dart)**
  - `unitSalePrice`: `product.salePrice + optionAdditionalAmount` (차감 옵션 시 정상 차감 단가 반환).
  - `formattedOptionsText`: 대괄호 중복(`[[...]]`) 및 불필요한 접두사를 자동 제거하는 정규화 게터 구현.
- **[`lib/views/cart.dart`](../lib/views/cart.dart)**
  - 품목 카드 단가 영역에 본품 원가 대신 옵션이 적용된 실제 단가(`item.unitSalePrice`) 바인딩.
  - 정가와 실판매가가 다를 경우 취소선과 할인가 강조 노출.
- **[`lib/viewmodels/cart_viewmodel.dart`](../lib/viewmodels/cart_viewmodel.dart)**
  - `_parseRawWebItems`: 원격 장바구니 실제 판매단가(`rawPrice ~/ qty`)와 본품 할인가의 차액을 비교하여 `optionAdditionalAmount`에 음수 차감액(-26,400원)을 정확히 반영.
  - 동일한 `product_id`를 가진 복수 옵션 품목을 `usedRefs` 집합을 통해 1:1로 고유 매칭 및 보존.

### 2.4 웹뷰 장바구니 담기 및 주문서 결제 안정화
- **[`lib/services/cafe24_web_cart_service.dart`](../lib/services/cafe24_web_cart_service.dart)**
  - `clean` 헬퍼 함수의 정규식 문법 오류 해결:
    ```javascript
    // AS-IS (WebKit SyntaxError: Range out of order in character class)
    s.replace(/[\s\-_/]/g, '')

    // TO-BE (안전 분리)
    s.replace(/\s+/g, '').replace(/[-_/]/g, '').trim().toLowerCase()
    ```
  - `addItem`: 본품 select와 추가상품 select(`add_option`)를 명확히 분리하여, 사용자가 선택한 옵션만 1:1 매칭하고 미선택 추가옵션은 자동 선택을 철저히 차단.
- **[`lib/views/cafe24_order_webview.dart`](../lib/views/cafe24_order_webview.dart)**
  - **"선택된 상품이 없습니다" 오류 해결**: 장바구니 주문 제출 시 숨겨진 더미 버튼이 아닌 화면에 노출된 **"전체상품주문"**(`a.btnSubmit, [onclick*="Basket.orderAll"]`) 버튼을 직접 클릭 트리거.
  - **"주문서로 이동할 수 없습니다" 오류 해결**: 원격 장바구니가 비어있는 경우 상세페이지를 경유하여 자동 보충 후 주문서로 넘어가도록 방어하고, 안전 타임아웃 링크에도 공식 파라미터(`orderform.html?basket_type=all_buy`) 적용.
  - **상품 이미지 및 상품명 복원**: 주문서 전용 스타일에서 `a[href*="/product/"] { display: none }`를 제거하고, 썸네일 이미지(`thumb img`)는 정상 노출(`visibility: visible !important; display: block;`)을 보장하며 `pointer-events: none`으로 클릭 이동만 비활성화.
- **[`lib/views/share/cafe24_checkout_launcher.dart`](../lib/views/share/cafe24_checkout_launcher.dart)**
  - 세션 복구 및 주문서 진입 시 기존 장바구니 품목의 `basketProductNo`, `selectedOptions`, 음수 차감액(`optionAdditionalAmount != 0`)을 1:1 매칭으로 유실 없이 보존.

---

## 3. 결과 및 검증

1. **상세 화면**: 필수 옵션과 추가 상품 옵션이 분리되어 표시되며, 미선택 상태에서도 정상 구매 가능.
2. **장바구니 화면**: `테두리엣지추가 (-26,400원)` 옵션 품목이 `5,600원`으로 정확히 표시되고, 대괄호 중복 없이 깔끔한 옵션명 노출.
3. **주문서 결제 화면**:
   - `PlatformException(FWFEvaluateJavaScriptError)` 없이 장바구니에서 주문서로 즉시 매끄럽게 전환.
   - 주문서에 상품 썸네일 이미지 및 상품명이 정상 표시되며, 실제 결제 금액(5,600원 등)이 장바구니와 1원도 틀리지 않고 정확히 일치.

