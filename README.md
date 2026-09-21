# shopmall

lib/
├── src/
│   ├── core/                        # 공통 인프라 (앱 전역 공통 모듈)
│   │   ├── constants/               # 앱 상수 (API URL, 키값 등)
│   │   ├── network/                 # Dio/Http 클라이언트
│   │   ├── router/                  # GoRouter 라우팅 설정
│   │   └── theme/                   # 테마 및 스타일
│   │
│   ├── features/                    # 기능별 MVVM 모듈
│   │   └── [feature_name]/          # 예: auth, product, profile
│   │       ├── models/              # [Model] 데이터 클래스 (Freezed/JSON)
│   │       ├── services/            # [Model] API 통신 / DB 접근 로직 (or repositories)
│   │       ├── viewmodels/          # [ViewModel] Riverpod Notifier (상태 및 비즈니스 로직)
│   │       └── views/               # [View] Screens 및 UI Widgets
│   │
│   └── app.dart                     # MaterialApp 설정
└── main.dart                        # 앱 진입점