# 모바일 앱 내비게이션 와이어링 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 백엔드에 스와이프 후보 목록 API를 추가하고, 모바일 앱의 5개 화면(로그인/회원가입/discover/matches/chat)을 세션 상태 관리(`AppSession`)와 내비게이션으로 연결해, `flutter run`으로 회원가입 → 로그인 → 스와이프 → 매칭 → 채팅까지 실제로 동작하는 앱을 만든다.

**Architecture:** 백엔드는 기존 `swipes`/`profiles` 모듈에 후보 조회 로직을 추가한다(`SwipesModule`이 `ProfilesModule`을 import). 모바일은 `provider` 패키지(이미 설치됨)로 `AppSession`(ChangeNotifier)을 앱 최상단에 두고, `Navigator.push(MaterialPageRoute(...))` 기반의 단순 내비게이션(`AuthGate` → `LoginScreen`/`HomeScreen`, `HomeScreen`은 `IndexedStack` 기반 하단 탭 2개)으로 화면을 연결한다. 로그인 토큰은 메모리에만 보관(앱 재시작 시 로그아웃)하고, 내 user id는 JWT payload를 클라이언트에서 로컬 디코딩해 얻는다(신규 "내 정보" 엔드포인트 없음).

**Tech Stack:** NestJS 10.x, TypeORM (백엔드는 신규 의존성 없음), Flutter (stable), `provider` 6.x(이미 설치됨) — 모바일도 신규 패키지 추가 없음

## Global Constraints

- 백엔드: 새 종속성 추가 금지. 기존 NestJS/TypeORM 패턴만 사용
- 모바일: 새 패키지 추가 금지. `provider`(이미 `pubspec.yaml`에 있음) 외 라우팅/상태관리 패키지를 추가하지 않는다
- 로그인 토큰은 메모리에만 보관한다 — 기기 영속 저장(secure storage 등) 금지, 앱 재시작 시 로그아웃되는 것이 의도된 동작
- 내 user id는 클라이언트에서 JWT payload를 로컬 디코딩(서명 검증 없이 `sub` claim만 읽음)해서 얻는다 — `GET /users/me` 등 신규 "내 정보" 엔드포인트를 추가하지 않는다
- 스와이프 후보 목록(`GET /swipes/candidates`)은 본인 + 이미 스와이프한 사람(좋아요/패스 무관) 전부를 제외하고, 프로필이 있는 사용자만, 최대 50건 반환한다
- 각 백엔드 로직 단위는 TDD로 작성한다: 실패하는 테스트 → 최소 구현 → 통과 확인 → 커밋 (기존 프로젝트 컨벤션 유지)
- 에러 처리는 기존 `LoginScreen`/`DiscoverScreen`에 쓰인 `_errorMessage` 상태 필드 + 빨간 `Text` 렌더링 패턴을 모든 화면에 일관되게 적용한다
- `ChatScreen`은 자신에게 주입된 `ChatSocketClient`를 계속 소유하고 `dispose()`에서 폐기한다 — 화면 하나당 소켓 하나, 화면과 함께 생성·폐기되는 규칙을 유지한다

---

## 파일 구조 개요

```
backend/
  src/
    swipes/
      swipes.service.ts        (수정: listSwipedTargetIds 추가)
      swipes.controller.ts     (수정: GET /swipes/candidates 추가)
      swipes.module.ts         (수정: ProfilesModule import)
    profiles/
      profiles.service.ts      (수정: listCandidates 추가)
mobile/
  lib/
    app_session.dart           (신규)
    auth_gate.dart              (신규)
    home_screen.dart            (신규)
    main.dart                   (수정: 전체 재작성)
    api/
      api_client.dart           (수정: get() 추가)
    auth/
      jwt_decoder.dart           (신규)
      login_screen.dart          (수정: AppSession 사용 + 회원가입 이동)
      signup_screen.dart         (수정: 성공 시 pop(true))
    discover/
      discover_repository.dart   (수정: fetchCandidates() 추가)
      discover_screen.dart       (수정: 후보 큐 순회로 재작성)
    matches/
      matches_repository.dart    (수정: ApiClient 경유로 변경)
      matches_screen.dart        (수정: 에러 처리 + onSelectMatch 콜백)
    chat/
      chat_socket_client.dart    (수정: onHistory/onError/onConnectError 추가)
      chat_screen.dart            (수정: history/error 처리)
  test/
    app_session_test.dart         (신규)
    auth_gate_test.dart           (신규)
    widget_test.dart              (삭제: 구식 카운터 테스트, auth_gate_test.dart로 대체됨)
    api/api_client_test.dart      (수정: get() 테스트 추가)
    auth/
      jwt_decoder_test.dart        (신규)
      login_screen_test.dart       (수정)
    discover/discover_screen_test.dart  (수정: 전면 재작성)
    matches/
      matches_repository_test.dart  (신규)
      matches_screen_test.dart      (수정)
```

각 신규/수정 파일은 하나의 책임만 갖는다. `AppSession`은 인증 상태와 토큰 바인딩된 리포지토리 인스턴스만 관리하고, 내비게이션 판단은 `AuthGate`가, 탭 구성은 `HomeScreen`이 담당한다.

---

### Task 1: 백엔드 — `SwipesService.listSwipedTargetIds`

**Files:**
- Modify: `backend/src/swipes/swipes.service.ts`
- Modify: `backend/src/swipes/swipes.service.spec.ts`

**Interfaces:**
- Consumes: 없음 (기존 `swipesRepo` 재사용)
- Produces: `SwipesService.listSwipedTargetIds(fromUserId: string): Promise<string[]>` — Task 3(후보 API 엔드포인트)이 이 메서드를 사용함

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/swipes/swipes.service.spec.ts`의 `beforeEach` 안 `repo` 객체에 `find: jest.fn()`을 추가하고, `describe('SwipesService', ...)` 블록 맨 끝에 다음 테스트를 추가한다:

```typescript
  it('lists the target ids a user has already swiped on', async () => {
    repo.find.mockResolvedValue([
      { targetUserId: 'user-2' },
      { targetUserId: 'user-3' },
    ]);

    const result = await service.listSwipedTargetIds('user-1');

    expect(repo.find).toHaveBeenCalledWith({
      where: { fromUserId: 'user-1' },
      select: ['targetUserId'],
    });
    expect(result).toEqual(['user-2', 'user-3']);
  });
```

`beforeEach`의 `repo` 선언부는 다음과 같이 바뀐다(`find` 추가):

```typescript
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Promise.resolve({ id: 'swipe-1', ...data }),
        ),
      findOne: jest.fn(),
      find: jest.fn(),
    };
```

그리고 파일 상단의 `let repo: {...}` 타입 선언에도 `find: jest.Mock;`을 추가한다:

```typescript
  let repo: { create: jest.Mock; save: jest.Mock; findOne: jest.Mock; find: jest.Mock };
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- swipes.service.spec.ts`
Expected: FAIL (`service.listSwipedTargetIds is not a function`)

- [ ] **Step 3: 구현**

`backend/src/swipes/swipes.service.ts`에 메서드 추가 (기존 `hasLiked` 메서드 아래):

```typescript
  async listSwipedTargetIds(fromUserId: string): Promise<string[]> {
    const swipes = await this.swipesRepo.find({
      where: { fromUserId },
      select: ['targetUserId'],
    });
    return swipes.map((s) => s.targetUserId);
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- swipes.service.spec.ts`
Expected: PASS (기존 3개 + 신규 1개, 총 4개)

- [ ] **Step 5: 커밋**

```bash
cd /Users/studio/Downloads/project/tablemate/.claude/worktrees/mobile-app-wiring
git add backend/src/swipes/swipes.service.ts backend/src/swipes/swipes.service.spec.ts
git commit -m "feat: add SwipesService.listSwipedTargetIds"
```

---

### Task 2: 백엔드 — `ProfilesService.listCandidates`

**Files:**
- Modify: `backend/src/profiles/profiles.service.ts`
- Modify: `backend/src/profiles/profiles.service.spec.ts`

**Interfaces:**
- Consumes: 없음 (기존 `profilesRepo` 재사용)
- Produces: `ProfilesService.listCandidates(excludeUserId: string, excludeTargetIds: string[]): Promise<Profile[]>` — Task 3이 이 메서드를 사용함. 반환되는 `Profile`은 `userId`, `displayName`, `bio` 필드를 가짐(`backend/src/profiles/profile.entity.ts` 참고)

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/profiles/profiles.service.spec.ts` 맨 끝(기존 `describe('ProfilesService.upsert', ...)` 블록 밖)에 새 `describe` 블록을 추가한다:

```typescript
describe('ProfilesService.listCandidates', () => {
  let service: ProfilesService;
  let queryBuilder: { where: jest.Mock; take: jest.Mock; getMany: jest.Mock };
  let repo: { createQueryBuilder: jest.Mock };

  beforeEach(async () => {
    queryBuilder = {
      where: jest.fn().mockReturnThis(),
      take: jest.fn().mockReturnThis(),
      getMany: jest
        .fn()
        .mockResolvedValue([
          { userId: 'user-3', displayName: 'Amy', bio: 'Hey' },
        ]),
    };
    repo = {
      createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ProfilesService,
        { provide: getRepositoryToken(Profile), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(ProfilesService);
  });

  it('excludes the given user id and target ids from the candidate list', async () => {
    const result = await service.listCandidates('user-1', ['user-2']);

    expect(repo.createQueryBuilder).toHaveBeenCalledWith('profile');
    expect(queryBuilder.where).toHaveBeenCalledWith(
      'profile.userId NOT IN (:...excludeIds)',
      { excludeIds: ['user-1', 'user-2'] },
    );
    expect(queryBuilder.take).toHaveBeenCalledWith(50);
    expect(result).toEqual([
      { userId: 'user-3', displayName: 'Amy', bio: 'Hey' },
    ]);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: FAIL (`service.listCandidates is not a function`)

- [ ] **Step 3: 구현**

`backend/src/profiles/profiles.service.ts`에 메서드 추가 (기존 `upsert` 메서드 아래):

```typescript
  async listCandidates(
    excludeUserId: string,
    excludeTargetIds: string[],
  ): Promise<Profile[]> {
    const excludeIds = [excludeUserId, ...excludeTargetIds];
    return this.profilesRepo
      .createQueryBuilder('profile')
      .where('profile.userId NOT IN (:...excludeIds)', { excludeIds })
      .take(50)
      .getMany();
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: PASS (기존 1개 + 신규 1개, 총 2개)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/profiles/profiles.service.ts backend/src/profiles/profiles.service.spec.ts
git commit -m "feat: add ProfilesService.listCandidates"
```

---

### Task 3: 백엔드 — `GET /swipes/candidates` 엔드포인트

**Files:**
- Modify: `backend/src/swipes/swipes.controller.ts`
- Modify: `backend/src/swipes/swipes.controller.spec.ts`
- Modify: `backend/src/swipes/swipes.module.ts`

**Interfaces:**
- Consumes: `SwipesService.listSwipedTargetIds`(Task 1), `ProfilesService.listCandidates`(Task 2)
- Produces: `GET /swipes/candidates` → `{ candidates: [{ userId, displayName, bio }] }` — 모바일 Task 7(`DiscoverRepository.fetchCandidates`)이 이 응답 형태를 그대로 소비함

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/swipes/swipes.controller.spec.ts` 상단 import에 `ProfilesService` 추가:

```typescript
import { ProfilesService } from '../profiles/profiles.service';
```

파일 맨 끝(기존 `describe('SwipesController.create', ...)` 블록 밖)에 새 `describe` 블록을 추가한다:

```typescript
describe('SwipesController.listCandidates', () => {
  let controller: SwipesController;
  let swipesService: { listSwipedTargetIds: jest.Mock };
  let profilesService: { listCandidates: jest.Mock };

  beforeEach(async () => {
    swipesService = {
      listSwipedTargetIds: jest.fn().mockResolvedValue(['user-2']),
    };
    profilesService = {
      listCandidates: jest
        .fn()
        .mockResolvedValue([
          { userId: 'user-3', displayName: 'Amy', bio: 'Hey' },
        ]),
    };

    const moduleRef = await Test.createTestingModule({
      controllers: [SwipesController],
      providers: [
        { provide: SwipesService, useValue: swipesService },
        { provide: MatchesService, useValue: {} },
        { provide: ProfilesService, useValue: profilesService },
      ],
    }).compile();

    controller = moduleRef.get(SwipesController);
  });

  it('excludes already-swiped users and returns candidate profiles', async () => {
    const req = { user: { userId: 'user-1' } };

    const result = await controller.listCandidates(req);

    expect(swipesService.listSwipedTargetIds).toHaveBeenCalledWith('user-1');
    expect(profilesService.listCandidates).toHaveBeenCalledWith('user-1', [
      'user-2',
    ]);
    expect(result).toEqual({
      candidates: [{ userId: 'user-3', displayName: 'Amy', bio: 'Hey' }],
    });
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- swipes.controller.spec.ts`
Expected: FAIL (`ProfilesService`를 주입할 수 없다는 DI 에러, 또는 `controller.listCandidates is not a function`)

- [ ] **Step 3: SwipesController 수정**

`backend/src/swipes/swipes.controller.ts` 전체를 다음으로 교체:

```typescript
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';
import { ProfilesService } from '../profiles/profiles.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(
    private readonly swipesService: SwipesService,
    private readonly matchesService: MatchesService,
    private readonly profilesService: ProfilesService,
  ) {}

  @Get('candidates')
  async listCandidates(@Req() req: any) {
    const excludeTargetIds = await this.swipesService.listSwipedTargetIds(
      req.user.userId,
    );
    const candidates = await this.profilesService.listCandidates(
      req.user.userId,
      excludeTargetIds,
    );
    return {
      candidates: candidates.map((c) => ({
        userId: c.userId,
        displayName: c.displayName,
        bio: c.bio,
      })),
    };
  }

  @Post()
  async create(@Req() req: any, @Body() dto: CreateSwipeDto) {
    if (dto.targetUserId === req.user.userId) {
      throw new BadRequestException('Cannot swipe on yourself');
    }

    const swipe = await this.swipesService.record(
      req.user.userId,
      dto.targetUserId,
      dto.liked,
    );
    const match = dto.liked
      ? await this.matchesService.createIfMutual(
          req.user.userId,
          dto.targetUserId,
        )
      : null;
    return { swipe, match };
  }
}
```

- [ ] **Step 4: SwipesModule에 ProfilesModule import 추가**

`backend/src/swipes/swipes.module.ts` 전체를 다음으로 교체:

```typescript
import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Swipe } from './swipe.entity';
import { SwipesService } from './swipes.service';
import { SwipesController } from './swipes.controller';
import { MatchesModule } from '../matches/matches.module';
import { ProfilesModule } from '../profiles/profiles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Swipe]),
    forwardRef(() => MatchesModule),
    ProfilesModule,
  ],
  controllers: [SwipesController],
  providers: [SwipesService],
  exports: [SwipesService],
})
export class SwipesModule {}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- swipes.controller.spec.ts`
Expected: PASS (기존 2개 + 신규 1개, 총 3개)

- [ ] **Step 6: 전체 스위트 + 빌드 확인**

Run: `cd backend && npm run test && npm run build`
Expected: 이전과 동일한 패턴(전체 통과, `auth.service.spec.ts`만 이 샌드박스의 bcrypt 이슈로 실패) + 빌드 성공

- [ ] **Step 7: 커밋**

```bash
git add backend/src/swipes/swipes.controller.ts backend/src/swipes/swipes.controller.spec.ts backend/src/swipes/swipes.module.ts
git commit -m "feat: expose GET /swipes/candidates endpoint"
```

---

### Task 4: 모바일 — JWT 로컬 디코더

**Files:**
- Create: `mobile/lib/auth/jwt_decoder.dart`
- Test: `mobile/test/auth/jwt_decoder_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `decodeUserId(String jwt): String` — Task 8(`AppSession.login`)이 로그인 직후 이 함수로 user id를 얻음. 유효하지 않은 토큰이면 `FormatException`을 던짐

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/auth/jwt_decoder_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/auth/jwt_decoder.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
  final body = encodeSegment(payload);
  return '$header.$body.fake-signature';
}

void main() {
  group('decodeUserId', () {
    test('extracts the sub claim from a valid JWT', () {
      final token = _fakeJwt({'sub': 'user-123', 'email': 'jane@example.com'});

      expect(decodeUserId(token), 'user-123');
    });

    test('throws FormatException when the token does not have 3 segments', () {
      expect(() => decodeUserId('not-a-jwt'), throwsFormatException);
    });

    test('throws FormatException when the payload has no sub claim', () {
      final token = _fakeJwt({'email': 'jane@example.com'});

      expect(() => decodeUserId(token), throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/jwt_decoder_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:mobile/auth/jwt_decoder.dart'`)

- [ ] **Step 3: 구현**

`mobile/lib/auth/jwt_decoder.dart`:

```dart
import 'dart:convert';

/// Decodes the `sub` claim (user id) from a JWT's payload, without
/// verifying the signature. This is safe here because the token is the
/// one this client itself just received from `POST /auth/login` /
/// `POST /auth/signup` — there is no untrusted third party handing us a
/// token to verify.
String decodeUserId(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) {
    throw FormatException(
      'Not a valid JWT: expected 3 segments, got ${parts.length}',
    );
  }

  final payload = _decodeBase64Segment(parts[1]);
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, dynamic> || decoded['sub'] is! String) {
    throw const FormatException('JWT payload missing "sub" claim');
  }
  return decoded['sub'] as String;
}

String _decodeBase64Segment(String segment) {
  final normalized = base64Url.normalize(segment);
  return utf8.decode(base64Url.decode(normalized));
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/jwt_decoder_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/auth/jwt_decoder.dart mobile/test/auth/jwt_decoder_test.dart
git commit -m "feat: add client-side JWT user id decoder"
```

---

### Task 5: 모바일 — `ApiClient.get()`

**Files:**
- Modify: `mobile/lib/api/api_client.dart`
- Modify: `mobile/test/api/api_client_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `ApiClient.get(String path, {String? accessToken}): Future<dynamic>` — 반환 타입이 `post()`(항상 `Map<String, dynamic>`)와 달리 `dynamic`인 이유는 `GET /matches`가 JSON 배열을, `GET /swipes/candidates`가 JSON 객체를 반환하는 등 엔드포인트마다 응답 형태가 다르기 때문. 호출자가 받은 뒤 타입을 확인해야 함. Task 6(`MatchesRepository`), Task 7(`DiscoverRepository.fetchCandidates`)이 이 메서드를 사용함

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/api/api_client_test.dart`의 `void main() {` 바로 다음, 기존 `group('ApiClient.post', ...)` 앞이나 뒤에 새 그룹을 추가한다 (파일 끝, 마지막 `}` 직전에 추가):

```dart
  group('ApiClient.get', () {
    test('returns decoded body when it is a JSON array', () async {
      final mockClient = MockClient((request) async {
        return http.Response('[{"id": "match-1"}]', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.get('/matches', accessToken: 'token-123');

      expect(result, [
        {'id': 'match-1'},
      ]);
    });

    test('returns decoded body when it is a JSON object', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"candidates": []}', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      final result = await apiClient.get(
        '/swipes/candidates',
        accessToken: 'token-123',
      );

      expect(result, {'candidates': []});
    });

    test('sends the bearer token in the Authorization header', () async {
      String? capturedAuthHeader;
      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response('[]', 200);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await apiClient.get('/matches', accessToken: 'token-123');

      expect(capturedAuthHeader, 'Bearer token-123');
    });

    test('throws ApiException with server message on error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Unauthorized"}', 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.get('/matches', accessToken: 'bad-token'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Unauthorized'),
        ),
      );
    });

    test('throws ApiException instead of crashing on a non-JSON response body', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html>502</html>', 502);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      expect(
        () => apiClient.get('/matches', accessToken: 'token-123'),
        throwsA(isA<ApiException>()),
      );
    });
  });
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: FAIL (`The method 'get' isn't defined for the type 'ApiClient'`)

- [ ] **Step 3: 구현**

`mobile/lib/api/api_client.dart`의 `post()` 메서드 아래에 추가:

```dart
  Future<dynamic> get(String path, {String? accessToken}) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException('Invalid response from server');
    }

    if (response.statusCode >= 400) {
      final message =
          decoded is Map<String, dynamic> ? decoded['message']?.toString() : null;
      throw ApiException(message ?? 'Request failed');
    }
    return decoded;
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: PASS (기존 6개 + 신규 5개, 총 11개)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/api/api_client.dart mobile/test/api/api_client_test.dart
git commit -m "feat: add ApiClient.get()"
```

---

### Task 6: 모바일 — `MatchesRepository`를 `ApiClient` 경유로 변경

**Files:**
- Modify: `mobile/lib/matches/matches_repository.dart`
- Create: `mobile/test/matches/matches_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient.get()`(Task 5)
- Produces: `MatchesRepository(ApiClient apiClient, String accessToken)` — 생성자 시그니처 변경(기존 `MatchesRepository(String baseUrl, String accessToken)`에서 변경). `listMatches(): Future<List<Map<String, dynamic>>>`는 동일. Task 8(`AppSession.matchesRepository`)이 새 생성자를 사용함

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/matches/matches_repository_test.dart` (신규 파일):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/matches/matches_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  group('MatchesRepository.listMatches', () {
    test('returns the parsed match list from ApiClient.get', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/matches', accessToken: 'token-123'))
          .thenAnswer(
        (_) async => [
          {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
        ],
      );
      final repo = MatchesRepository(mockApiClient, 'token-123');

      final result = await repo.listMatches();

      expect(result, [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ]);
    });

    test('throws ApiException when the response is not a list', () async {
      final mockApiClient = MockApiClient();
      when(() => mockApiClient.get('/matches', accessToken: 'token-123'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = MatchesRepository(mockApiClient, 'token-123');

      expect(() => repo.listMatches(), throwsA(isA<ApiException>()));
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/matches/matches_repository_test.dart`
Expected: FAIL (생성자 인자 타입 불일치 — `MatchesRepository`가 첫 인자로 `String`을 기대함)

- [ ] **Step 3: 구현**

`mobile/lib/matches/matches_repository.dart` 전체를 다음으로 교체:

```dart
import '../api/api_client.dart';

class MatchesRepository {
  MatchesRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final decoded = await _apiClient.get('/matches', accessToken: _accessToken);
    if (decoded is! List) {
      throw ApiException('Invalid response from server');
    }
    return decoded.cast<Map<String, dynamic>>();
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/matches/matches_repository_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: 전체 스위트 확인 (matches_screen_test.dart는 Mock을 쓰므로 생성자 변경의 영향을 받지 않아야 함)**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test`
Expected: PASS (기존 테스트 전부 + 신규 2개, 회귀 없음)

- [ ] **Step 6: 커밋**

```bash
git add mobile/lib/matches/matches_repository.dart mobile/test/matches/matches_repository_test.dart
git commit -m "fix: route MatchesRepository through ApiClient"
```

---

### Task 7: 모바일 — 후보 큐 기반 `DiscoverScreen`

**Files:**
- Modify: `mobile/lib/discover/discover_repository.dart`
- Modify: `mobile/lib/discover/discover_screen.dart`
- Modify: `mobile/test/discover/discover_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.get()`(Task 5), 백엔드 `GET /swipes/candidates`(Task 3)
- Produces: `DiscoverRepository.fetchCandidates(): Future<List<Map<String, dynamic>>>` (각 항목은 `userId`, `displayName`, `bio` 키를 가짐). `DiscoverScreen`의 생성자가 `{repository}`만 받도록 변경됨(기존 `candidateUserId`/`candidateName` 제거) — Task 12(`HomeScreen`)이 이 새 생성자를 사용함

- [ ] **Step 1: 실패하는 테스트 작성 (기존 파일 전체 교체)**

`mobile/test/discover/discover_screen_test.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/discover/discover_repository.dart';
import 'package:mobile/discover/discover_screen.dart';

class MockDiscoverRepository extends Mock implements DiscoverRepository {}

void main() {
  testWidgets('fetches candidates on load and shows the first one', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsOneWidget);
  });

  testWidgets(
    'tapping like calls DiscoverRepository.swipe with liked=true and advances to next candidate',
    (tester) async {
      final mockRepo = MockDiscoverRepository();
      when(() => mockRepo.fetchCandidates()).thenAnswer(
        (_) async => [
          {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
          {'userId': 'user-3', 'displayName': 'Amy', 'bio': 'Hey'},
        ],
      );
      when(() => mockRepo.swipe('user-2', true)).thenAnswer((_) async => false);

      await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('likeButton')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.swipe('user-2', true)).called(1);
      expect(find.text('Amy'), findsOneWidget);
    },
  );

  testWidgets('shows an empty state once all candidates are swiped', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );
    when(() => mockRepo.swipe('user-2', false)).thenAnswer((_) async => false);

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passButton')));
    await tester.pumpAndSettle();

    expect(find.text('더 이상 후보가 없습니다'), findsOneWidget);
  });

  testWidgets('shows an error message when DiscoverRepository.swipe throws', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenAnswer(
      (_) async => [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ],
    );
    when(() => mockRepo.swipe('user-2', true)).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('likeButton')));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });

  testWidgets('shows an error message when fetchCandidates throws', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.fetchCandidates()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(home: DiscoverScreen(repository: mockRepo)));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/discover/discover_screen_test.dart`
Expected: FAIL (`DiscoverScreen`에 `candidateUserId`/`candidateName` 없는 생성자가 없음, `fetchCandidates`가 `DiscoverRepository`에 없음)

- [ ] **Step 3: `DiscoverRepository.fetchCandidates()` 구현**

`mobile/lib/discover/discover_repository.dart` 전체를 다음으로 교체:

```dart
import '../api/api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> fetchCandidates() async {
    final decoded = await _apiClient.get(
      '/swipes/candidates',
      accessToken: _accessToken,
    );
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw ApiException('Invalid response from server');
    }
    return (decoded['candidates'] as List).cast<Map<String, dynamic>>();
  }

  Future<bool> swipe(String targetUserId, bool liked) async {
    final result = await _apiClient.post(
      '/swipes',
      {'targetUserId': targetUserId, 'liked': liked},
      accessToken: _accessToken,
    );
    return result['match'] != null;
  }
}
```

- [ ] **Step 4: `DiscoverScreen` 재작성**

`mobile/lib/discover/discover_screen.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'discover_repository.dart';
import 'swipe_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.repository});

  final DiscoverRepository repository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Map<String, dynamic>> _candidates = [];
  int _index = 0;
  bool _loading = true;
  bool? _matched;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await widget.repository.fetchCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _index = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _current =>
      _index < _candidates.length ? _candidates[_index] : null;

  Future<void> _like() async {
    final candidate = _current;
    if (candidate == null) return;
    try {
      final matched =
          await widget.repository.swipe(candidate['userId'] as String, true);
      if (!mounted) return;
      setState(() {
        _matched = matched;
        _errorMessage = null;
        _index++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _pass() async {
    final candidate = _current;
    if (candidate == null) return;
    try {
      await widget.repository.swipe(candidate['userId'] as String, false);
      if (!mounted) return;
      setState(() {
        _matched = null;
        _errorMessage = null;
        _index++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final candidate = _current;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: candidate == null
                ? const Center(child: Text('더 이상 후보가 없습니다'))
                : SwipeCard(name: candidate['displayName'] as String? ?? '(이름 없음)'),
          ),
          if (_matched == true) const Text("It's a match!"),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          if (candidate != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: const Key('passButton'),
                  icon: const Icon(Icons.close),
                  onPressed: _pass,
                ),
                IconButton(
                  key: const Key('likeButton'),
                  icon: const Icon(Icons.favorite),
                  onPressed: _like,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/discover/discover_screen_test.dart`
Expected: PASS (5/5)

- [ ] **Step 6: 커밋**

```bash
git add mobile/lib/discover/discover_repository.dart mobile/lib/discover/discover_screen.dart mobile/test/discover/discover_screen_test.dart
git commit -m "feat: fetch and cycle through swipe candidates in DiscoverScreen"
```

---

### Task 8: 모바일 — `AppSession`

**Files:**
- Create: `mobile/lib/app_session.dart`
- Test: `mobile/test/app_session_test.dart`

**Interfaces:**
- Consumes: `ApiClient`(기존), `AuthRepository`(기존), `DiscoverRepository`(Task 7), `MatchesRepository`(Task 6), `ChatSocketClient`(기존), `decodeUserId`(Task 4)
- Produces: `AppSession` (ChangeNotifier) — `isAuthenticated`, `userId`, `authRepository`, `discoverRepository`, `matchesRepository`, `login(email, password)`, `logout()`, `buildChatSocketClient()`. Task 9(`LoginScreen`), Task 12(`AuthGate`/`HomeScreen`)이 이 클래스를 사용함

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/app_session_test.dart` (신규 파일):

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

void main() {
  group('AppSession', () {
    test('login stores the access token and decodes the user id', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'accessToken': token}), 200);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      var notified = false;
      session.addListener(() => notified = true);

      await session.login('jane@example.com', 'password123');

      expect(session.isAuthenticated, isTrue);
      expect(session.userId, 'user-1');
      expect(notified, isTrue);
    });

    test('logout clears the session and notifies listeners', () async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'accessToken': token}), 200);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@example.com', 'password123');
      var notified = false;
      session.addListener(() => notified = true);

      session.logout();

      expect(session.isAuthenticated, isFalse);
      expect(session.userId, isNull);
      expect(notified, isTrue);
    });

    test('discoverRepository throws before login', () {
      final session = AppSession(baseUrl: 'http://localhost:3000');

      expect(() => session.discoverRepository, throwsStateError);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:mobile/app_session.dart'`)

- [ ] **Step 3: 구현**

`mobile/lib/app_session.dart` (신규 파일):

```dart
import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'auth/auth_repository.dart';
import 'auth/jwt_decoder.dart';
import 'chat/chat_socket_client.dart';
import 'discover/discover_repository.dart';
import 'matches/matches_repository.dart';

class AppSession extends ChangeNotifier {
  AppSession({required String baseUrl, ApiClient? apiClient})
      : _baseUrl = baseUrl,
        _apiClient = apiClient ?? ApiClient(baseUrl: baseUrl);

  final String _baseUrl;
  final ApiClient _apiClient;

  String? _accessToken;
  String? _userId;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;

  bool get isAuthenticated => _accessToken != null;
  String? get userId => _userId;

  late final AuthRepository authRepository = AuthRepository(_apiClient);

  DiscoverRepository get discoverRepository =>
      _discoverRepository ??= DiscoverRepository(_apiClient, _requireToken());

  MatchesRepository get matchesRepository =>
      _matchesRepository ??= MatchesRepository(_apiClient, _requireToken());

  String _requireToken() {
    final token = _accessToken;
    if (token == null) {
      throw StateError('AppSession: not authenticated');
    }
    return token;
  }

  Future<void> login(String email, String password) async {
    final token = await authRepository.login(email, password);
    _accessToken = token;
    _userId = decodeUserId(token);
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
  }

  void logout() {
    _accessToken = null;
    _userId = null;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
  }

  ChatSocketClient buildChatSocketClient() {
    return ChatSocketClient(_baseUrl, _requireToken());
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/app_session.dart mobile/test/app_session_test.dart
git commit -m "feat: add AppSession for shared auth state"
```

---

### Task 9: 모바일 — `LoginScreen`/`SignupScreen`을 `AppSession`에 연결

**Files:**
- Modify: `mobile/lib/auth/login_screen.dart`
- Modify: `mobile/lib/auth/signup_screen.dart`
- Modify: `mobile/test/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `AppSession`(Task 8)
- Produces: `LoginScreen({required AppSession session})` — 생성자 시그니처 변경(기존 `{required AuthRepository authRepository}`에서 변경). Task 12(`AuthGate`)가 이 새 생성자를 사용함. `SignupScreen`의 생성자는 그대로(`{required AuthRepository authRepository}`)지만 성공 시 `Navigator.pop(context, true)`를 호출하도록 동작이 바뀜

- [ ] **Step 1: 실패하는 테스트 작성 (기존 파일 전체 교체)**

`mobile/test/auth/login_screen_test.dart` 전체를 다음으로 교체:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';
import 'package:mobile/auth/login_screen.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

void main() {
  testWidgets('submits email and password and authenticates the session', (tester) async {
    final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'accessToken': token}), 200);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient:
          ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isTrue);
  });

  testWidgets('shows an error message when login fails', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'message': 'Invalid credentials'}), 401);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient:
          ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('navigating to signup and completing it shows a success message', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/auth/signup') {
        return http.Response(
          jsonEncode({'id': 'user-2', 'email': 'amy@example.com'}),
          201,
        );
      }
      return http.Response(jsonEncode({'message': 'not found'}), 404);
    });
    final session = AppSession(
      baseUrl: 'http://localhost:3000',
      apiClient:
          ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));

    await tester.tap(find.byKey(const Key('goToSignupButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('emailField')), 'amy@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('signupButton')));
    await tester.pumpAndSettle();

    expect(find.text('가입 완료 — 로그인해주세요'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/login_screen_test.dart`
Expected: FAIL (`LoginScreen`에 `session` 이름의 파라미터가 없음, `goToSignupButton` 키를 찾을 수 없음)

- [ ] **Step 3: `SignupScreen` 수정 — 성공 시 pop(true)**

`mobile/lib/auth/signup_screen.dart`의 `_submit` 메서드를 다음으로 교체:

```dart
  Future<void> _submit() async {
    try {
      await widget.authRepository.signup(_emailController.text, _passwordController.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }
```

- [ ] **Step 4: `LoginScreen` 재작성**

`mobile/lib/auth/login_screen.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import '../app_session.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  String? _infoMessage;

  Future<void> _submit() async {
    try {
      await widget.session.login(_emailController.text, _passwordController.text);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _infoMessage = null;
      });
    }
  }

  Future<void> _goToSignup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SignupScreen(authRepository: widget.session.authRepository),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _infoMessage = '가입 완료 — 로그인해주세요';
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('emailField'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              key: const Key('passwordField'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_infoMessage != null)
              Text(_infoMessage!, style: const TextStyle(color: Colors.green)),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('loginButton'),
              onPressed: _submit,
              child: const Text('Log in'),
            ),
            TextButton(
              key: const Key('goToSignupButton'),
              onPressed: _goToSignup,
              child: const Text('회원가입'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/login_screen_test.dart`
Expected: PASS (3/3)

- [ ] **Step 6: 전체 스위트 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test`
Expected: PASS 전체, 회귀 없음

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/auth/login_screen.dart mobile/lib/auth/signup_screen.dart mobile/test/auth/login_screen_test.dart
git commit -m "feat: wire LoginScreen/SignupScreen to AppSession"
```

---

### Task 10: 모바일 — `MatchesScreen` 에러 처리 + 채팅 이동 콜백

**Files:**
- Modify: `mobile/lib/matches/matches_screen.dart`
- Modify: `mobile/test/matches/matches_screen_test.dart`

**Interfaces:**
- Consumes: `MatchesRepository`(Task 6)
- Produces: `MatchesScreen({required MatchesRepository repository, required void Function(String matchId) onSelectMatch})` — 생성자에 `onSelectMatch` 콜백 추가. Task 12(`HomeScreen`)가 이 콜백으로 채팅 화면 이동을 처리함

- [ ] **Step 1: 실패하는 테스트 작성 (기존 파일 전체 교체)**

`mobile/test/matches/matches_screen_test.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/matches/matches_repository.dart';
import 'package:mobile/matches/matches_screen.dart';

class MockMatchesRepository extends Mock implements MatchesRepository {}

void main() {
  testWidgets('renders each match returned by the repository', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('match-1'), findsOneWidget);
  });

  testWidgets('tapping a match calls onSelectMatch with its id', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenAnswer(
      (_) async => [
        {'id': 'match-1', 'userAId': 'me', 'userBId': 'user-2'},
      ],
    );
    String? selected;

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(
        repository: mockRepo,
        onSelectMatch: (matchId) => selected = matchId,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('match-1'));
    await tester.pumpAndSettle();

    expect(selected, 'match-1');
  });

  testWidgets('shows an error message when listMatches throws', (tester) async {
    final mockRepo = MockMatchesRepository();
    when(() => mockRepo.listMatches()).thenThrow(Exception('Network error'));

    await tester.pumpWidget(MaterialApp(
      home: MatchesScreen(repository: mockRepo, onSelectMatch: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Network error'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/matches/matches_screen_test.dart`
Expected: FAIL (`MatchesScreen`에 `onSelectMatch` 파라미터가 없음)

- [ ] **Step 3: 구현**

`mobile/lib/matches/matches_screen.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'matches_repository.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.repository,
    required this.onSelectMatch,
  });

  final MatchesRepository repository;
  final void Function(String matchId) onSelectMatch;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>> _matches = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final matches = await widget.repository.listMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return Scaffold(
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) {
          final matchId = _matches[index]['id'] as String;
          return ListTile(
            title: Text(matchId),
            onTap: () => widget.onSelectMatch(matchId),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/matches/matches_screen_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/matches/matches_screen.dart mobile/test/matches/matches_screen_test.dart
git commit -m "fix: handle listMatches errors and add match tap navigation"
```

---

### Task 11: 모바일 — `ChatSocketClient`/`ChatScreen` history/error 처리

**Files:**
- Modify: `mobile/lib/chat/chat_socket_client.dart`
- Modify: `mobile/lib/chat/chat_screen.dart`

**Interfaces:**
- Consumes: 없음 (기존 `socket_io_client` 사용)
- Produces: `ChatSocketClient.onHistory(void Function(dynamic) handler)`, `onError(void Function(dynamic) handler)`, `onConnectError(void Function(dynamic) handler)` 추가. `ChatScreen`의 생성자/외부 동작은 변경 없음(내부 구현만 보강)

이 태스크는 실제 Socket.IO 서버 연결이 있어야 검증 가능해 자동 테스트 대상이 아니다(Task 13에서 이미 확립된 방침). `flutter analyze` 타입체크로 갈음한다.

- [ ] **Step 1: `ChatSocketClient`에 리스너 추가**

`mobile/lib/chat/chat_socket_client.dart`의 `onNewMessage` 메서드 아래에 추가:

```dart
  void onHistory(void Function(dynamic history) handler) {
    _socket.on('history', handler);
  }

  void onError(void Function(dynamic error) handler) {
    _socket.on('error', handler);
  }

  void onConnectError(void Function(dynamic error) handler) {
    _socket.onConnectError(handler);
  }
```

- [ ] **Step 2: `ChatScreen`이 history/error를 반영하도록 수정**

`mobile/lib/chat/chat_screen.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'chat_socket_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.socketClient,
    required this.matchId,
  });

  final ChatSocketClient socketClient;
  final String matchId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <String>[];
  final _inputController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    widget.socketClient.joinMatch(widget.matchId);
    widget.socketClient.onHistory((history) {
      if (!mounted || history is! List) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history.map((m) => (m as Map)['content'] as String));
      });
    });
    widget.socketClient.onNewMessage((message) {
      if (!mounted) return;
      setState(() => _messages.add(message['content'] as String));
    });
    widget.socketClient.onError((error) {
      if (!mounted) return;
      final message = error is Map ? error['message']?.toString() : null;
      setState(() => _errorMessage = message ?? '채팅 오류가 발생했습니다');
    });
    widget.socketClient.onConnectError((error) {
      if (!mounted) return;
      setState(() => _errorMessage = '채팅 서버에 연결할 수 없습니다');
    });
  }

  void _send() {
    widget.socketClient.sendMessage(widget.matchId, _inputController.text);
    _inputController.clear();
  }

  @override
  void dispose() {
    widget.socketClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: ListView(children: _messages.map((m) => Text(m)).toList()),
          ),
          Row(
            children: [
              Expanded(child: TextField(controller: _inputController)),
              IconButton(
                key: const Key('sendButton'),
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: 정적 분석 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter analyze`
Expected: 클린 (에러/경고 없음). `onConnectError`가 설치된 `socket_io_client` 버전의 `Socket` 클래스 API와 이름이 다르면(패키지 버전에 따라 메서드명이 다를 수 있음) 여기서 컴파일 에러로 드러난다 — 그 경우 `flutter pub deps` 또는 패키지 소스(`~/.pub-cache` 또는 `mobile/.dart_tool/package_config.json`이 가리키는 경로)를 확인해 실제 메서드명으로 맞춘다.

- [ ] **Step 4: 전체 테스트 스위트 확인 (회귀 없는지)**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test`
Expected: PASS 전체, 회귀 없음

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/chat/chat_socket_client.dart mobile/lib/chat/chat_screen.dart
git commit -m "feat: surface chat history and connection errors in ChatScreen"
```

---

### Task 12: 모바일 — `AuthGate` + `HomeScreen` + `main.dart` 와이어링

**Files:**
- Create: `mobile/lib/auth_gate.dart`
- Create: `mobile/lib/home_screen.dart`
- Modify: `mobile/lib/main.dart`
- Create: `mobile/test/auth_gate_test.dart`
- Delete: `mobile/test/widget_test.dart`

**Interfaces:**
- Consumes: `AppSession`(Task 8), `LoginScreen`(Task 9), `DiscoverScreen`(Task 7), `MatchesScreen`(Task 10), `ChatScreen`(Task 11)
- Produces: 없음 (이번 계획의 최종 조립 지점)

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/auth_gate_test.dart` (신규 파일):

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/app_session.dart';
import 'package:mobile/auth_gate.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String encodeSegment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encodeSegment({'alg': 'HS256'})}.${encodeSegment(payload)}.fake-signature';
}

void main() {
  testWidgets(
    'logs in, shows the home screen, and logs back out to the login screen',
    (tester) async {
      final token = _fakeJwt({'sub': 'user-1', 'email': 'jane@example.com'});
      final mockClient = MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return http.Response(jsonEncode({'accessToken': token}), 200);
        }
        if (request.url.path == '/swipes/candidates') {
          return http.Response(jsonEncode({'candidates': []}), 200);
        }
        if (request.url.path == '/matches') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient: ApiClient(
          baseUrl: 'http://localhost:3000',
          httpClient: mockClient,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppSession>.value(
          value: session,
          child: const MaterialApp(home: AuthGate()),
        ),
      );

      expect(find.byKey(const Key('emailField')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
      await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logoutButton')), findsOneWidget);
      expect(find.text('더 이상 후보가 없습니다'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logoutButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('emailField')), findsOneWidget);
    },
  );
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:mobile/auth_gate.dart'`)

- [ ] **Step 3: `HomeScreen` 구현**

`mobile/lib/home_screen.dart` (신규 파일):

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'chat/chat_screen.dart';
import 'discover/discover_screen.dart';
import 'matches/matches_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  void _openChat(String matchId) {
    final session = context.read<AppSession>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          socketClient: session.buildChatSocketClient(),
          matchId: matchId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabIndex == 0 ? 'Discover' : 'Matches'),
        actions: [
          IconButton(
            key: const Key('logoutButton'),
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppSession>().logout(),
          ),
        ],
      ),
      // IndexedStack keeps both tabs mounted so switching tabs doesn't reset
      // DiscoverScreen's fetched candidate queue or MatchesScreen's list.
      body: IndexedStack(
        index: _tabIndex,
        children: [
          DiscoverScreen(repository: session.discoverRepository),
          MatchesScreen(
            repository: session.matchesRepository,
            onSelectMatch: _openChat,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Matches'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `AuthGate` 구현**

`mobile/lib/auth_gate.dart` (신규 파일):

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'auth/login_screen.dart';
import 'home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AppSession>().isAuthenticated;
    return isAuthenticated
        ? const HomeScreen()
        : LoginScreen(session: context.read<AppSession>());
  }
}
```

- [ ] **Step 5: `main.dart` 재작성**

`mobile/lib/main.dart` 전체를 다음으로 교체:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'auth_gate.dart';

const String kApiBaseUrl = 'http://localhost:3000';

void main() {
  runApp(const TableMateApp());
}

class TableMateApp extends StatelessWidget {
  const TableMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppSession(baseUrl: kApiBaseUrl),
      child: MaterialApp(
        title: 'TableMate',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
```

- [ ] **Step 6: 구식 카운터 테스트 삭제**

```bash
git rm mobile/test/widget_test.dart
```

(이 파일은 삭제되는 기본 카운터 앱을 테스트하던 파일이며, 그 커버리지는 이번 태스크의 `auth_gate_test.dart`가 대체한다.)

- [ ] **Step 7: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth_gate_test.dart`
Expected: PASS (1/1)

- [ ] **Step 8: 전체 스위트 + 정적 분석 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, `flutter analyze` 클린

- [ ] **Step 9: 커밋**

```bash
git add mobile/lib/auth_gate.dart mobile/lib/home_screen.dart mobile/lib/main.dart mobile/test/auth_gate_test.dart
git commit -m "feat: wire login/discover/matches/chat screens into a navigable app"
```

---

### Task 13: 수동 검증 + README 갱신

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 없음 (검증 전용)
- Produces: 없음

- [ ] **Step 1: 백엔드 전체 스위트 + 빌드 확인**

Run: `cd backend && npm run test && npm run build`
Expected: 이전과 동일한 패턴 — 전체 통과, `auth.service.spec.ts`만 이 개발 샌드박스의 bcrypt 코드서명 이슈로 실패(README에 이미 기록된 사유, 코드 결함 아님)

- [ ] **Step 2: 모바일 전체 스위트 + 정적 분석 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, 클린

(이 개발 환경에는 Android SDK/완전한 Xcode가 없어 실기기·에뮬레이터로 `flutter run`을 실제 검증할 수는 없다 — Task 11~13(서브프로젝트 1)과 동일한 제약. 이번 태스크의 검증은 위 두 자동화 테스트 스위트로 갈음한다.)

- [ ] **Step 3: README 갱신**

`README.md`의 "현재 상태" 문단과 `mobile/` 구조 설명, "알려진 제약" 섹션을 아래 내용을 반영해 갱신한다 (기존 파일을 Read한 뒤, 아래 변경사항을 기존 구조에 자연스럽게 병합할 것 — 아래는 갱신할 핵심 내용이지 파일 전체 치환이 아니다):

- 상단 "현재 상태" 문단에서 "`main.dart` 와이어링이 계획 범위에 없었다"는 기존 문장을 제거하고, "로그인 게이트 + 하단 탭(Discover/Matches) 내비게이션까지 연결되어 `flutter run`으로 회원가입 → 로그인 → 스와이프 → 매칭 → 채팅 흐름을 탈 수 있다"는 내용으로 교체
- `mobile/` 구조 설명에 `lib/app_session.dart`, `lib/auth_gate.dart`, `lib/home_screen.dart`를 추가하고, "아직 기본 카운터 앱 그대로임" 문장을 제거
- "알려진 제약"에 다음을 추가:
  - 로그인 토큰은 메모리에만 보관되며 앱을 재시작하면 로그아웃된다 (지속 저장 미구현, 의도된 동작)
  - `MatchesScreen`은 매칭 상대의 표시 이름을 보여주지 못하고 매칭 id를 그대로 노출한다 (상대방 프로필 조회 API가 아직 없음 — 향후 서브프로젝트에서 다룰 수 있음)
  - Android/iOS 실기기·에뮬레이터에서의 `flutter run` 검증은 이 개발 환경에 해당 툴체인이 없어 수행되지 않았다

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: update README for the wired mobile app"
```

## Self-Review 결과

- **스펙 커버리지:** 백엔드 후보 API(Task 1-3), JWT 로컬 디코딩(Task 4), `ApiClient.get()`+`MatchesRepository` 이관(Task 5-6), `DiscoverScreen` 큐 순회(Task 7), `AppSession`(Task 8), `LoginScreen`/`SignupScreen` 와이어링(Task 9), `MatchesScreen` 에러 처리(Task 10), 채팅 history/error(Task 11), `AuthGate`/`HomeScreen`/`main.dart` 조립(Task 12), 검증+문서화(Task 13) — 스펙의 5개 섹션을 모두 커버함
- **플레이스홀더 스캔:** 없음. 모든 스텝에 실행 가능한 코드 포함
- **타입 일관성:** `SwipesService.listSwipedTargetIds`(Task 1) → `ProfilesService.listCandidates`(Task 2) → `SwipesController.listCandidates`(Task 3) → `DiscoverRepository.fetchCandidates`(Task 7)까지 `{candidates: [{userId, displayName, bio}]}` 응답 형태가 일관됨. `ApiClient.get()`(Task 5) → `MatchesRepository`(Task 6)/`DiscoverRepository`(Task 7) 소비 패턴 일관됨. `AppSession`(Task 8)이 노출하는 `discoverRepository`/`matchesRepository`/`buildChatSocketClient()`가 각각 Task 7/6/11에서 정의한 생성자 시그니처와 일치함. `LoginScreen`의 새 `session` 파라미터(Task 9)와 `AuthGate`(Task 12)의 사용처가 일치함. `MatchesScreen`의 `onSelectMatch`(Task 10)와 `HomeScreen._openChat`(Task 12)의 시그니처가 일치함
