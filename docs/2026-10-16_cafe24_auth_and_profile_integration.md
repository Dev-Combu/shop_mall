# 🔐 Cafe24 쇼핑몰 일반 Auth(회원가입·로그인·회원정보 확인·회원탈퇴) 전체 구현 정리

**최종 업데이트**: 2026-10-17  
**작업 브랜치**: `feat/auth`  
**관련 쇼핑몰**: 수지씨앤엘 (`suzicnl.com` / 몰 아이디: `suzicnl1`)

---

## 1. 개요 및 추진 배경

수지씨앤엘 모바일 앱(`shopmall`)에서 외부 브라우저나 투박한 웹뷰 팝업을 띄우지 않고, **100% Flutter 네이티브 UI**를 유지하면서 실제 Cafe24 쇼핑몰(`suzicnl.com`)의 회원 DB와 완벽하게 연동되는 일반 인증(Auth) 시스템을 구축했습니다.

### 해결한 핵심 기술적 과제
1. **`"잘못된 요청입니다."` 오류 해결 (`AuthSSLManager` 암호화)**:
   - Cafe24 프론트 서버(`/exec/front/Member/login/` 및 회원가입 처리 엔드포인트)는 평문 `POST` 요청을 거부하며, 반드시 페이지 내 `AuthSSLManager`를 통해 폼 데이터를 일회용 SSL 공개키로 암호화(`encrypt_type=AuthSSL`)해야만 정상 처리됩니다.
   - 이를 해결하기 위해 화면 하단에 **비가시성(`1x1`, `Opacity: 0.0`, `IgnorePointer`) WebKit 엔진**을 배치하여 백그라운드에서 공식 `AuthSSLManager` 암호화 및 jQuery 검증 스크립트를 실행하도록 구현했습니다.
2. **회원정보 수정 페이지(`/member/modify.html`)의 개인정보 비동기 복호화 폴링**:
   - Cafe24의 `/member/modify.html`은 보안상 초기 정적 HTML 소스에 휴대폰 번호(`mobile[]`), 이메일(`email1`), 실명(`name`)의 `value=""`를 비워둔 상태로 내려보내고, **실제 브라우저 DOM 로드 직후 `AuthSSLManager`가 비동기로 암호화 데이터를 복호화하여 input에 주입**합니다.
   - 단순 `fetch('/member/modify.html')`나 즉시 파싱(`0ms`) 시 휴대폰 번호가 빈 값(`미등록`)으로 나오는 문제를 해결하기 위해, **라이브 WebView DOM에서 `AuthSSLManager` 복호화가 완료될 때까지 `200ms` 간격으로 폴링(Polling) 대기 후 추출**하도록 고도화했습니다.
3. **세션 영속성 및 로컬 디렉토리 병합(`Cafe24CustomerAuthService`)**:
   - 회원가입 또는 로그인 시 획득한 회원 프로필(아이디, 실명, 이메일, 휴대폰 번호, 등급, 적립금, 쿠폰)을 `FlutterSecureStorage`에 암호화 저장하고, 재로그인 시에도 누락된 필드가 없도록 자동 병합(`_keyMemberDirectory`)합니다.

---

## 2. 일반 Auth 전체 아키텍처 및 파일 구성

| 구분 | 파일 경로 | 핵심 역할 |
| :--- | :--- | :--- |
| **Model** | [`lib/models/user.dart`](../lib/models/user.dart) | 회원 데이터 모델 (`id`, `name`, `email`, `phone`, `groupName`, `points`, `coupons`, `orders`, `isCafe24Member`) 및 JSON 직렬화 |
| **Service** | [`lib/services/cafe24_customer_auth_service.dart`](../lib/services/cafe24_customer_auth_service.dart) | `FlutterSecureStorage` 기반 세션 저장/복원, 회원별 프로필 디렉토리 병합(`saveSession`), 로그아웃/탈퇴 시 세션 및 WebKit 쿠키 초기화 |
| **ViewModel** | [`lib/viewmodels/auth_viewmodel.dart`](../lib/viewmodels/auth_viewmodel.dart) | Riverpod `Notifier<User?>` 전역 인증 상태 관리 (`setAuthenticatedUser`, `loginWithDemo`, `logout`, `withdrawAccount`) |
| **View (회원가입)** | [`lib/views/signup.dart`](../lib/views/signup.dart) | 100% 네이티브 회원가입 UI + 백그라운드 `AuthSSLManager` 가입 엔진 (`memberJoinAction`) |
| **View (로그인)** | [`lib/views/login.dart`](../lib/views/login.dart) | 100% 네이티브 로그인 UI + 백그라운드 `MemberAction.login` 암호화 실행 + `/myshop/index.html` 및 `/member/modify.html` 복호화 폴링 |
| **View (회원정보)** | [`lib/views/profile.dart`](../lib/views/profile.dart) | 회원 정보 상세 확인 페이지, 실시간 새로고침(`Pull-to-Refresh`), `/member/modify.html` 백그라운드 동기화 |
| **View (회원탈퇴)** | [`lib/views/withdrawal.dart`](../lib/views/withdrawal.dart) | 네이티브 회원탈퇴 화면, 비밀번호 재확인 및 탈퇴 사유 선택 후 Cafe24 `memberLeaveAction` 실행 |
| **Router & MyPage** | [`lib/config/router/router.dart`](../lib/config/router/router.dart)<br>[`lib/views/my_page.dart`](../lib/views/my_page.dart) | `/login`, `/signup`, `/profile`, `/withdrawal` 라우트 등록 및 마이페이지 대시보드 연동 |

---

## 3. 기능별 상세 구현 내역

### 1) 일반 계정 회원가입 ([`lib/views/signup.dart`](../lib/views/signup.dart))
- **네이티브 입력 폼 및 유효성 검증**:
  - 아이디(영문 소문자/숫자 4~16자), 비밀번호(Cafe24 정책: 영문 대소문자/숫자/특수문자 중 2가지 이상 조합 10~16자 또는 3가지 이상 조합 8~16자), 이름, 휴대폰 번호(`010-XXXX-XXXX` 자동 하이픈 포맷터), 이메일, 약관 동의(전체 동의 및 필수/선택 개별 동의) 구성.
- **백그라운드 Cafe24 `AuthSSLManager` 연동**:
  - `https://suzicnl.com/member/join.html`을 비가시성 WebView에서 로드.
  - 가입 버튼 클릭 시 네이티브 입력값을 Cafe24 DOM(`#member_id`, `#passwd`, `#user_passwd_confirm`, `#name`, `mobile[]`, `#email1`, `#agree_service_check0`, `#agree_privacy_check0`)에 주입하고 jQuery `blur`/`change` 이벤트를 트리거하여 아이디/이메일 중복검사를 통과시킨 후 `memberJoinAction()` 실행.
  - 가입 성공(`join_result.html` 도달) 시 즉시 `User` 세션을 생성하여 자동 로그인 처리 및 Cafe24 관리자(`고객 관리 > 회원 조회`)에 실시간 등록.

### 2) 일반 계정 로그인 및 휴대폰 번호 복호화 동기화 ([`lib/views/login.dart`](../lib/views/login.dart))
- **암호화 로그인 실행**:
  - `https://suzicnl.com/member/login.html`을 백그라운드에서 로드한 뒤, `#member_id`와 `#member_passwd`를 주입하고 `MemberAction.login(form.id)`을 호출하여 `AuthSSL` 암호화 로그인 수행.
  - 아이디/비밀번호 불일치 시 Cafe24 JS `alert()`을 `setOnJavaScriptAlertDialog`로 가로채어 네이티브 에러 배너로 표시.
- **2단계 실시간 프로필 수집 (`/myshop/index.html` ➔ `/member/modify.html`)**:
  1. **1단계 (`/myshop/index.html`)**: 로그인 성공 직후 마이쇼핑 화면에서 회원 등급(`groupName`), 가용 적립금(`avail_mileage`), 보유 쿠폰 수(`couponCount`), 기본 이름을 파싱하고 즉시 `/member/modify.html`로 이동.
  2. **2단계 (`/member/modify.html` 폴링)**: Cafe24의 `AuthSSLManager` 비동기 복호화 스크립트가 `#mobile1~3`(`mobile[]`), `#phone1~3`(`phone[]`), `#email1`, `#name` 값을 채울 때까지 `200ms` 간격(최대 2.8초)으로 폴링 대기한 뒤 추출하여 휴대폰 번호가 `미등록`으로 누락되지 않도록 보장.
- **테스트 계정 1초 로그인**:
  - `suzicnl1` 테스트 계정 버튼을 통해 즉시 데모 세션으로도 로그인 가능.

### 3) 회원 정보 확인 페이지 ([`lib/views/profile.dart`](../lib/views/profile.dart))
- **구성 카드**:
  - **프로필 요약 카드**: 실명, 회원 등급 뱃지, 아이디, `Cafe24 공식 쇼핑몰 연동 계정` 인증 뱃지
  - **쇼핑 혜택 및 활동 현황 카드**: 가용 적립금(`P`), 보유 쿠폰(`장`), 주문 내역(`건`)
  - **기본 회원 정보 상세 카드**: 회원 아이디, 이름(실명), 이메일 주소, 휴대폰 번호, 회원 등급
  - **Cafe24 쇼핑몰 연동 상태 카드**: 연동 쇼핑몰(`suzicnl.com`), 몰 아이디(`suzicnl1`), 인증 체계(`Cafe24 AuthSSL 암호화 세션`), 보안 저장소 상태 표시
- **실시간 동기화 및 새로고침**:
  - 페이지 진입 시 및 상단 새로고침 버튼(`Pull-to-Refresh` 포함) 실행 시 백그라운드 WebView가 `/member/modify.html`을 로드하고, `AuthSSLManager` 복호화 완료 시점까지 폴링 대기 후 최신 휴대폰 번호·이메일·실명·적립금·쿠폰을 갱신.

### 4) 회원탈퇴 기능 ([`lib/views/withdrawal.dart`](../lib/views/withdrawal.dart))
- **네이티브 탈퇴 프로세스**:
  - 탈퇴 시 소멸되는 혜택(적립금, 쿠폰) 및 복구 불가 안내 고지.
  - 탈퇴 사유 선택, 상세 의견 입력, 현재 비밀번호 확인 및 최종 동의 체크박스 제공.
- **Cafe24 서버 탈퇴 실행 및 로컬 세션 파기**:
  - 백그라운드 WebView에서 `/member/modify.html`의 탈퇴 함수(`memberLeaveAction` / `#passwd` 검증)를 실행하여 실제 Cafe24 회원 탈퇴를 처리하고, 완료 즉시 `AuthViewModel.withdrawAccount()`를 통해 `FlutterSecureStorage` 세션 및 WebKit 쿠키를 완전 파기.

---

## 4. 트러블슈팅 요약

| 발생 이슈 | 원인 분석 | 해결 방법 |
| :--- | :--- | :--- |
| 회원가입/로그인 시 `"잘못된 요청입니다."` 발생 | Cafe24 서버가 `AuthSSLManager` 암호화 없는 직접 HTTP POST 요청을 차단함 | 비가시성(`1x1`) WebKit 엔진에서 공식 `memberJoinAction()` 및 `MemberAction.login()`을 실행하도록 구현 |
| 회원 정보에 휴대폰 번호가 있는데도 `'미등록'`으로 표시됨 | `/member/modify.html`의 초기 HTML에는 `mobile[]`의 `value=""`가 비어 있고, 페이지 로드 후 `AuthSSLManager`가 비동기로 복호화하여 주입함 | `fetch()` 정적 파싱 대신 라이브 WebView를 `/member/modify.html`로 이동시키고, `mobile[]` 값이 복호화될 때까지 `200ms` 간격으로 폴링 대기 후 추출 |
| Admin API 고객 조회 시 `403 Forbidden` 로그 발생 | 현재 발급된 토큰은 상품/카테고리 조회용 스코프만 포함하고 있어 `/api/v2/admin/customers` 호출 시 403 발생 | 불필요한 403 에러를 유발하는 Admin API 고객 호출을 제거하고, 회원 본인의 인증된 WebView 세션(`/member/modify.html`) 복호화 폴링으로 100% 처리 |
