# TableMate

데이팅과 맛집을 결합한 서비스.

**현재 상태:** 백엔드 기반 골격(회원가입/로그인, 프로필, 스와이프/매칭, 실시간 채팅, 맛집 씨드 데이터)과 모바일(Flutter) 화면/리포지토리(로그인·회원가입, 스와이프, 매칭 목록, WebSocket 채팅)까지 구현 및 테스트 완료. 단, 화면들을 하나의 앱 내비게이션 흐름으로 연결하는 작업(`main.dart` 와이어링)은 이번 계획(Task 1-14)의 범위에 포함되지 않아 아직 없습니다 — 아래 "알려진 제약" 참고.

## 구조

- `backend/` — NestJS + PostgreSQL API 서버. **구현 완료:**
  - `auth/` — 회원가입/로그인 (JWT, bcrypt 비밀번호 해싱)
  - `users/`, `profiles/` — 사용자 및 프로필 관리
  - `swipes/`, `matches/` — 스와이프 및 상호 매칭 로직
  - `chat/` — WebSocket 채팅 게이트웨이 (JWT 인증 기반 소켓 identity)
  - `restaurants/` — 맛집 데이터 API 및 씨드 파이프라인
- `mobile/` — Flutter 앱 (iOS/Android/웹). **화면·리포지토리 구현 완료, 앱 와이어링은 미완:**
  - `lib/api/api_client.dart` — 공용 HTTP 클라이언트 (비-JSON 응답 방어 처리 포함)
  - `lib/auth/` — 로그인/회원가입 화면 + `AuthRepository`
  - `lib/discover/` — 스와이프(좋아요/패스) 화면 + `DiscoverRepository`
  - `lib/matches/` — 매칭 목록 화면 + `MatchesRepository`
  - `lib/chat/` — WebSocket 채팅 화면 + `ChatSocketClient` (연결 시 JWT를 소켓 handshake `auth`로 전달)
  - `lib/main.dart` — 아직 `flutter create`가 생성한 기본 카운터 앱 그대로임 (위 화면들을 라우팅/내비게이션으로 연결하는 작업은 계획에 없었음)
- `docs/superpowers/specs/` — 설계 문서
- `docs/superpowers/plans/` — 구현 계획 문서

## 로컬 실행

### 백엔드

```bash
cd backend
cp .env.example .env  # DB 접속정보 수정
npm install
npm run start:dev
```

### 맛집 씨드 데이터

```bash
# DuckDB로 Overture Maps에서 서울 지역 맛집 추출 (DuckDB CLI 설치 필요)
duckdb < backend/scripts/extract-overture-restaurants.sql
# PostgreSQL에 적재
npx ts-node backend/scripts/seed-restaurants.ts backend/scripts/output/seoul-restaurants.csv
```

맛집 데이터 출처: [Overture Maps Foundation](https://overturemaps.org/), CDLA Permissive v2.0 라이선스.
씨드 데이터는 서울 지역으로 한정되어 있으며, 실제 출시 지역(글로벌) 데이터로 교체가 필요합니다.

### 모바일

```bash
cd mobile
flutter pub get
flutter test   # 위젯/유닛 테스트 실행
flutter run    # 실행 (아래 "알려진 제약" 참고 — 아직 화면이 연결되어 있지 않음)
```

## 현재 상태 / Known limitations

- **화면 간 내비게이션 와이어링 없음:** `mobile/lib/main.dart`는 `flutter create`가 생성한 기본 카운터 앱 그대로입니다. 로그인/회원가입, discover(스와이프), matches, chat 화면과 각 리포지토리는 모두 구현·테스트되어 있지만(Task 11-13), 이들을 하나의 앱 흐름(라우팅, 로그인 후 화면 전환, 토큰 저장/전달)으로 엮는 작업은 원래 계획(Task 1-14)에 포함되지 않았습니다. `flutter run`을 실행해도 기본 카운터 화면만 보입니다 — 후속 작업으로 필요합니다.
- **모바일 환경 제약:** 이 개발 환경에는 Android SDK와 완전한 Xcode 설치가 없습니다. `flutter test`(헤드리스 위젯 테스트)와 `flutter analyze`, 그리고 Chrome(웹)/macOS 데스크톱 타겟은 동작하지만, 실제 iOS/Android 기기·시뮬레이터 빌드는 이 환경에서 검증되지 않았습니다.
- **이 개발 샌드박스에서는 백엔드를 실제로 기동해 end-to-end curl 검증을 할 수 없습니다.** 이 머신의 Node.js 바이너리(Codex.app에 번들된 버전)는 Hardened Runtime + library validation이 활성화되어 있어, `bcrypt`의 네이티브 `.node` 바이너리가 Node 바이너리와 다른 Team ID로 서명되어 있다는 이유로 로드를 거부합니다(`dlopen` 단계에서 `code signature ... not valid for use in process: ... different Team IDs` 오류). `AuthModule`이 앱 부트스트랩 시점에 즉시 로드되므로, `/health` 등 어떤 엔드포인트에도 도달하기 전에 서버 프로세스 자체가 크래시합니다. `npm rebuild bcrypt --build-from-source` 및 수동 `codesign --force -s -` 재서명으로도 해결되지 않았습니다(애드혹 서명에는 Team ID가 없어 Node 바이너리의 Team ID 일치 요구사항을 근본적으로 만족시킬 수 없음). 이는 **이 샌드박스에 한정된 제약**이며, 일반 로컬 머신이나 CI 환경에서는 발생하지 않습니다. 이 환경에서의 검증은 실시간 curl 대신 자동화된 테스트 스위트(`npm run test`, `npm run build`)로 대체했습니다. 상세: `.superpowers/sdd/2026-08-01-base-research-implementation/task-14-report.md`.

## 알려진 제약

- 리프레시 토큰 미구현 (액세스 토큰만, 1시간 만료) — 서브프로젝트 3에서 다룰 예정
- 맛집 데이터는 서울 지역 씨드 데이터로, 실시간 영업정보 아님
