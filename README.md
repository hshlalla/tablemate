# TableMate

데이팅과 맛집을 결합한 서비스.

**현재 상태:** 백엔드 기반 골격(회원가입/로그인, 프로필, 스와이프/매칭, 실시간 채팅, 맛집 씨드 데이터) 구현 및 테스트 완료. 모바일(Flutter) 앱은 아직 구현되지 않음 — Flutter SDK 미설치로 후속 세션으로 연기됨.

## 구조

- `backend/` — NestJS + PostgreSQL API 서버. **구현 완료:**
  - `auth/` — 회원가입/로그인 (JWT, bcrypt 비밀번호 해싱)
  - `users/`, `profiles/` — 사용자 및 프로필 관리
  - `swipes/`, `matches/` — 스와이프 및 상호 매칭 로직
  - `chat/` — WebSocket 채팅 게이트웨이 (JWT 인증 기반 소켓 identity)
  - `restaurants/` — 맛집 데이터 API 및 씨드 파이프라인
- `mobile/` — Flutter 앱 (iOS/Android/웹). **미구현.** Flutter SDK 설치가 선행되어야 착수 가능 (계획 문서 기준 Task 11-13).
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

아직 존재하지 않음. Flutter SDK 설치 후 아래와 같이 초기화될 예정:

```bash
cd mobile
flutter pub get
flutter run
```

## 현재 상태 / Known limitations

- **모바일 앱 미구현:** Flutter SDK가 이 개발 환경에 설치되어 있지 않아 `mobile/` 디렉터리 자체가 아직 생성되지 않았습니다. Task 11-13(Flutter 앱: discover/스와이프 화면, matches 화면, 채팅 화면)은 후속 세션에서 Flutter SDK 설치 후 진행합니다.
- **이 개발 샌드박스에서는 백엔드를 실제로 기동해 end-to-end curl 검증을 할 수 없습니다.** 이 머신의 Node.js 바이너리(Codex.app에 번들된 버전)는 Hardened Runtime + library validation이 활성화되어 있어, `bcrypt`의 네이티브 `.node` 바이너리가 Node 바이너리와 다른 Team ID로 서명되어 있다는 이유로 로드를 거부합니다(`dlopen` 단계에서 `code signature ... not valid for use in process: ... different Team IDs` 오류). `AuthModule`이 앱 부트스트랩 시점에 즉시 로드되므로, `/health` 등 어떤 엔드포인트에도 도달하기 전에 서버 프로세스 자체가 크래시합니다. `npm rebuild bcrypt --build-from-source` 및 수동 `codesign --force -s -` 재서명으로도 해결되지 않았습니다(애드혹 서명에는 Team ID가 없어 Node 바이너리의 Team ID 일치 요구사항을 근본적으로 만족시킬 수 없음). 이는 **이 샌드박스에 한정된 제약**이며, 일반 로컬 머신이나 CI 환경에서는 발생하지 않습니다. 이 환경에서의 검증은 실시간 curl 대신 자동화된 테스트 스위트(`npm run test`, `npm run build`)로 대체했습니다. 상세: `.superpowers/sdd/2026-08-01-base-research-implementation/task-14-report.md`.

## 알려진 제약

- 리프레시 토큰 미구현 (액세스 토큰만, 1시간 만료) — 서브프로젝트 3에서 다룰 예정
- 맛집 데이터는 서울 지역 씨드 데이터로, 실시간 영업정보 아님
