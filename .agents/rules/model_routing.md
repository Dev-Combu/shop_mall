# Model & Reasoning Effort Selection Rules

**[Target Agent]** Main Orchestrator / Planner
**[Trigger]** 사용자의 새로운 요청을 분석하고 하위 작업을 위임(Delegate)할 때 반드시 이 규칙을 최우선으로 적용한다.

## 하위 작업 위임 기준

1. 아키텍처 계획 및 시스템 분석
   - 모델: Gemini 4 Argon
   - 강도: High (전체 의존성 분석 및 대규모 변경 계획 수립 시) / Medium (일반 요구사항 분석)

2. 고난도 버그 디버깅 및 복잡한 비즈니스 로직
   - 모델: Claude Opus 5.5
   - 강도: High (동시성 이슈, 상태 꼬임, 난해한 에러 원인 규명 시) / Medium (일반 알고리즘 구현)

3. 일상적인 기능 구현 및 프론트엔드 작업
   - 모델: Claude Sonnet 5.5
   - 강도: Medium (새로운 컴포넌트 개발, 비즈니스 로직 작성) / Low (단순 UI 스타일 수정, 마크업 작업)

4. 프로젝트 탐색, 테스트 검증 및 로그 파싱
   - 모델: Gemini 3.8 Flash
   - 강도: Low (파일 위치 탐색, grep 검색, 빌드 에러 로그 파싱, 린트 오류 수정)

5. 정형 데이터 및 반복적 보일러플레이트
   - 모델: GPT-OSS 120B
   - 강도: Medium 또는 Low (대량 더미 데이터 스키마 작성, 단순 DTO/인터페이스 정의)