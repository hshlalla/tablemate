# 리프레시 토큰 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stateful 회전 방식의 리프레시 토큰을 도입해, 액세스 토큰이 만료돼도 모바일 앱이 세션 실행 중 401을 감지해 자동으로 토큰을 갱신하도록 한다.

**Architecture:** 백엔드는 리프레시 토큰의 발급/회전/재사용감지/폐기를 bcrypt를 import하지 않는 신규 `RefreshTokensService`(crypto sha256 + TypeORM)에 격리하고, `AuthService`가 로그인/refresh/logout에서 이를 오케스트레이션한다. 모바일은 신규 패키지 없이 `AuthenticatedApiClient` 래퍼가 401 시 리프레시 1회 후 재시도하고, `AppSession`이 single-flight 가드로 토큰 상태를 관리한다.

**Tech Stack:** NestJS 10.x, TypeORM(신규 엔티티 1개), Node 내장 `crypto`, Flutter(stable), `provider` 6.x(이미 설치) — 신규 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-08-13-refresh-token-design.md`

## Global Constraints

- 백엔드: 새 npm 의존성 추가 금지. 리프레시 토큰 해싱/생성은 Node 내장 `crypto`(`randomBytes`, `createHash('sha256')`)만 사용. bcrypt는 신규 코드에서 import하지 않는다.
- 모바일: 새 패키지 추가 금지. 리프레시 토큰은 메모리에만 보관(secure storage 금지). 앱 재시작 시 로그아웃은 의도된 동작.
- 각 로직 단위는 TDD: 실패 테스트 → 최소 구현 → 통과 → 커밋.
- 액세스 토큰 payload는 기존과 동일하게 `{ sub, email }`을 유지한다(모바일 `decodeUserId` 호환).
- `POST /auth/signup`은 변경하지 않는다(`{id, email}` 반환, 자동 로그인 없음).
- 이 개발 샌드박스 제약: `bcrypt`를 transitively import하는 테스트 스위트(`auth.service.spec.ts`, 그리고 `AuthController`/`AuthService`를 import하는 어떤 스펙도)는 이 샌드박스에서 **로드 자체가 실패**한다(문서화된 코드서명 이슈). 따라서 refresh 오케스트레이션의 컨트롤러/서비스 레벨 스펙은 추가하지 않고, 핵심 로직은 bcrypt-free인 `RefreshTokensService` 스펙으로 완전 검증하며, 배선(wiring)은 `npm run build`로 확인한다. 일반 로컬/CI 환경에서는 모든 스펙이 정상 동작한다.
- 모바일 flutter 명령은 `export PATH="/Users/studio/development/flutter/bin:$PATH"` 후 `cd mobile`에서 실행한다.

---

## 파일 구조 개요

```
backend/
  .env.example                                (수정: JWT_EXPIRES_IN, REFRESH_TOKEN_TTL_DAYS)
  src/
    auth/
      refresh-token.entity.ts                 (신규)
      refresh-tokens.service.ts               (신규)
      refresh-tokens.service.spec.ts          (신규)
      dto/refresh-token.dto.ts                (신규)
      auth.service.ts                         (수정: login 확장, refresh/logout 추가)
      auth.controller.ts                      (수정: refresh/logout 라우트)
      auth.module.ts                          (수정: RefreshToken feature + RefreshTokensService)
    users/
      users.service.ts                        (수정: findById 추가)
      users.service.spec.ts                   (신규)
mobile/
  lib/
    api/
      api_client.dart                         (수정: ApiException.statusCode)
      authenticated_api_client.dart           (신규)
    auth/auth_repository.dart                 (수정: login 반환 확장, refresh/logout)
    discover/discover_repository.dart         (수정: AuthenticatedApiClient 사용)
    matches/matches_repository.dart           (수정: AuthenticatedApiClient 사용)
    app_session.dart                          (수정: refreshToken, _refresh, 배선)
  test/
    api/api_client_test.dart                  (수정: statusCode 테스트)
    api/authenticated_api_client_test.dart    (신규)
    auth/auth_repository_test.dart            (신규)
    discover/discover_repository_test.dart    (수정: mock 대상 변경)
    matches/matches_repository_test.dart      (수정: mock 대상 변경)
    app_session_test.dart                     (수정: refresh/single-flight/두 토큰)
    auth/login_screen_test.dart               (수정: 로그인 mock에 refreshToken 추가)
    auth_gate_test.dart                       (수정: 로그인 mock에 refreshToken 추가)
```

---

### Task 1: 백엔드 — `RefreshToken` 엔티티 + `RefreshTokensService.issue`

**Files:**
- Create: `backend/src/auth/refresh-token.entity.ts`
- Create: `backend/src/auth/refresh-tokens.service.ts`
- Create: `backend/src/auth/refresh-tokens.service.spec.ts`

**Interfaces:**
- Consumes: 없음
- Produces: `RefreshTokensService.issue(userId: string): Promise<string>` — 원문(opaque) 리프레시 토큰 반환(64자 hex). Task 2/3이 같은 서비스에 메서드 추가, Task 5(`AuthService`)가 `issue` 사용.

- [ ] **Step 1: 엔티티 작성**

`backend/src/auth/refresh-token.entity.ts`:

```typescript
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

@Entity('refresh_tokens')
export class RefreshToken {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column()
  userId: string;

  @Column({ unique: true })
  tokenHash: string;

  @Column({ type: 'timestamp' })
  expiresAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  revokedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`backend/src/auth/refresh-tokens.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { RefreshTokensService } from './refresh-tokens.service';
import { RefreshToken } from './refresh-token.entity';

function sha256(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}

describe('RefreshTokensService.issue', () => {
  let service: RefreshTokensService;
  let repo: { create: jest.Mock; save: jest.Mock };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve(data)),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        RefreshTokensService,
        { provide: getRepositoryToken(RefreshToken), useValue: repo },
        { provide: ConfigService, useValue: { get: () => undefined } },
      ],
    }).compile();

    service = moduleRef.get(RefreshTokensService);
  });

  it('generates a 64-char hex token and stores only its sha256 hash', async () => {
    const before = Date.now();

    const rawToken = await service.issue('user-1');

    expect(rawToken).toMatch(/^[0-9a-f]{64}$/);
    expect(repo.create).toHaveBeenCalledTimes(1);
    const stored = repo.create.mock.calls[0][0];
    expect(stored.userId).toBe('user-1');
    expect(stored.tokenHash).toBe(sha256(rawToken));
    expect(stored.tokenHash).not.toBe(rawToken);
    expect(stored.expiresAt.getTime()).toBeGreaterThan(before);
    expect(repo.save).toHaveBeenCalledWith(stored);
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: FAIL (`Cannot find module './refresh-tokens.service'` 또는 `issue is not a function`)

- [ ] **Step 4: 구현**

`backend/src/auth/refresh-tokens.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import { Repository } from 'typeorm';
import { createHash, randomBytes } from 'crypto';
import { RefreshToken } from './refresh-token.entity';

@Injectable()
export class RefreshTokensService {
  constructor(
    @InjectRepository(RefreshToken)
    private readonly repo: Repository<RefreshToken>,
    private readonly config: ConfigService,
  ) {}

  async issue(userId: string): Promise<string> {
    const rawToken = randomBytes(32).toString('hex');
    const ttlDays = Number(this.config.get('REFRESH_TOKEN_TTL_DAYS') ?? 30);
    const expiresAt = new Date(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    const entity = this.repo.create({
      userId,
      tokenHash: this.hash(rawToken),
      expiresAt,
      revokedAt: null,
    });
    await this.repo.save(entity);
    return rawToken;
  }

  private hash(rawToken: string): string {
    return createHash('sha256').update(rawToken).digest('hex');
  }
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: PASS (1/1)

- [ ] **Step 6: 커밋**

```bash
git add backend/src/auth/refresh-token.entity.ts backend/src/auth/refresh-tokens.service.ts backend/src/auth/refresh-tokens.service.spec.ts
git commit -m "feat: add RefreshToken entity and RefreshTokensService.issue"
```

---

### Task 2: 백엔드 — `RefreshTokensService.rotate` + `revokeAllForUser`

**Files:**
- Modify: `backend/src/auth/refresh-tokens.service.ts`
- Modify: `backend/src/auth/refresh-tokens.service.spec.ts`

**Interfaces:**
- Consumes: `RefreshTokensService.issue`(Task 1)
- Produces: `RefreshTokensService.rotate(rawToken: string): Promise<{ userId: string; refreshToken: string }>`, `RefreshTokensService.revokeAllForUser(userId: string): Promise<void>` — Task 5(`AuthService.refresh`)가 `rotate` 사용.

- [ ] **Step 1: 실패하는 테스트 작성 (spec 파일 하단에 새 describe 추가)**

`backend/src/auth/refresh-tokens.service.spec.ts` 상단 import에 `UnauthorizedException`과 `IsNull` 추가:

```typescript
import { UnauthorizedException } from '@nestjs/common';
import { IsNull } from 'typeorm';
```

파일 맨 끝에 추가:

```typescript
describe('RefreshTokensService.rotate', () => {
  let service: RefreshTokensService;
  let repo: {
    create: jest.Mock;
    save: jest.Mock;
    findOne: jest.Mock;
    update: jest.Mock;
  };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve(data)),
      findOne: jest.fn(),
      update: jest.fn().mockResolvedValue(undefined),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        RefreshTokensService,
        { provide: getRepositoryToken(RefreshToken), useValue: repo },
        { provide: ConfigService, useValue: { get: () => undefined } },
      ],
    }).compile();

    service = moduleRef.get(RefreshTokensService);
  });

  it('revokes the presented token and issues a new one when valid', async () => {
    const row = {
      id: 'rt-1',
      userId: 'user-1',
      tokenHash: sha256('old-raw'),
      expiresAt: new Date(Date.now() + 60_000),
      revokedAt: null,
    };
    repo.findOne.mockResolvedValue(row);

    const result = await service.rotate('old-raw');

    expect(repo.findOne).toHaveBeenCalledWith({
      where: { tokenHash: sha256('old-raw') },
    });
    expect(row.revokedAt).toBeInstanceOf(Date); // old token rotated out
    expect(repo.save).toHaveBeenCalledWith(row);
    expect(result.userId).toBe('user-1');
    expect(result.refreshToken).toMatch(/^[0-9a-f]{64}$/);
    expect(result.refreshToken).not.toBe('old-raw');
  });

  it('throws Unauthorized when the token is unknown', async () => {
    repo.findOne.mockResolvedValue(null);

    await expect(service.rotate('nope')).rejects.toThrow(UnauthorizedException);
  });

  it('throws Unauthorized when the token is expired', async () => {
    repo.findOne.mockResolvedValue({
      id: 'rt-1',
      userId: 'user-1',
      tokenHash: sha256('old-raw'),
      expiresAt: new Date(Date.now() - 60_000),
      revokedAt: null,
    });

    await expect(service.rotate('old-raw')).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('revokes all of the user tokens and throws when a revoked token is reused', async () => {
    repo.findOne.mockResolvedValue({
      id: 'rt-1',
      userId: 'user-1',
      tokenHash: sha256('old-raw'),
      expiresAt: new Date(Date.now() + 60_000),
      revokedAt: new Date(Date.now() - 1000),
    });

    await expect(service.rotate('old-raw')).rejects.toThrow(
      UnauthorizedException,
    );
    expect(repo.update).toHaveBeenCalledWith(
      { userId: 'user-1', revokedAt: IsNull() },
      { revokedAt: expect.any(Date) },
    );
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: FAIL (`rotate is not a function`)

- [ ] **Step 3: 구현 (기존 `hash` 메서드 위에 추가)**

`backend/src/auth/refresh-tokens.service.ts`의 상단 import를 다음으로 교체:

```typescript
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import { IsNull, Repository } from 'typeorm';
import { createHash, randomBytes } from 'crypto';
import { RefreshToken } from './refresh-token.entity';
```

`issue` 메서드 아래에 추가:

```typescript
  async rotate(
    rawToken: string,
  ): Promise<{ userId: string; refreshToken: string }> {
    const tokenHash = this.hash(rawToken);
    const existing = await this.repo.findOne({ where: { tokenHash } });

    if (!existing) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (existing.revokedAt) {
      await this.revokeAllForUser(existing.userId);
      throw new UnauthorizedException('Refresh token reuse detected');
    }
    if (existing.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('Refresh token expired');
    }

    existing.revokedAt = new Date();
    await this.repo.save(existing);
    const refreshToken = await this.issue(existing.userId);
    return { userId: existing.userId, refreshToken };
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.repo.update(
      { userId, revokedAt: IsNull() },
      { revokedAt: new Date() },
    );
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: PASS (기존 1개 + 신규 4개, 총 5개)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/auth/refresh-tokens.service.ts backend/src/auth/refresh-tokens.service.spec.ts
git commit -m "feat: add RefreshTokensService.rotate with reuse detection"
```

---

### Task 3: 백엔드 — `RefreshTokensService.revoke`

**Files:**
- Modify: `backend/src/auth/refresh-tokens.service.ts`
- Modify: `backend/src/auth/refresh-tokens.service.spec.ts`

**Interfaces:**
- Consumes: 없음
- Produces: `RefreshTokensService.revoke(rawToken: string): Promise<void>` — Task 5(`AuthService.logout`)가 사용. 멱등(없는 토큰이어도 예외 없음).

- [ ] **Step 1: 실패하는 테스트 작성 (파일 맨 끝에 추가)**

```typescript
describe('RefreshTokensService.revoke', () => {
  let service: RefreshTokensService;
  let repo: { update: jest.Mock };

  beforeEach(async () => {
    repo = { update: jest.fn().mockResolvedValue(undefined) };

    const moduleRef = await Test.createTestingModule({
      providers: [
        RefreshTokensService,
        { provide: getRepositoryToken(RefreshToken), useValue: repo },
        { provide: ConfigService, useValue: { get: () => undefined } },
      ],
    }).compile();

    service = moduleRef.get(RefreshTokensService);
  });

  it('marks the matching active token as revoked by its hash', async () => {
    await service.revoke('some-raw');

    expect(repo.update).toHaveBeenCalledWith(
      { tokenHash: sha256('some-raw'), revokedAt: IsNull() },
      { revokedAt: expect.any(Date) },
    );
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: FAIL (`revoke is not a function`)

- [ ] **Step 3: 구현 (`revokeAllForUser` 아래에 추가)**

```typescript
  async revoke(rawToken: string): Promise<void> {
    await this.repo.update(
      { tokenHash: this.hash(rawToken), revokedAt: IsNull() },
      { revokedAt: new Date() },
    );
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- refresh-tokens.service.spec.ts`
Expected: PASS (총 6개)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/auth/refresh-tokens.service.ts backend/src/auth/refresh-tokens.service.spec.ts
git commit -m "feat: add RefreshTokensService.revoke"
```

---

### Task 4: 백엔드 — `UsersService.findById`

**Files:**
- Modify: `backend/src/users/users.service.ts`
- Create: `backend/src/users/users.service.spec.ts`

**Interfaces:**
- Consumes: 없음
- Produces: `UsersService.findById(id: string): Promise<User | null>` — Task 5(`AuthService.refresh`)가 새 액세스 토큰 서명 시 이메일 조회에 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/users/users.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { UsersService } from './users.service';
import { User } from './user.entity';

describe('UsersService.findById', () => {
  let service: UsersService;
  let repo: { findOne: jest.Mock };

  beforeEach(async () => {
    repo = { findOne: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: getRepositoryToken(User), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(UsersService);
  });

  it('looks up a user by id', async () => {
    const user = { id: 'user-1', email: 'jane@example.com' };
    repo.findOne.mockResolvedValue(user);

    const result = await service.findById('user-1');

    expect(repo.findOne).toHaveBeenCalledWith({ where: { id: 'user-1' } });
    expect(result).toBe(user);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- users.service.spec.ts`
Expected: FAIL (`findById is not a function`)

- [ ] **Step 3: 구현 (`findByEmail` 아래에 추가)**

`backend/src/users/users.service.ts`:

```typescript
  findById(id: string): Promise<User | null> {
    return this.usersRepo.findOne({ where: { id } });
  }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- users.service.spec.ts`
Expected: PASS (1/1)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/users/users.service.ts backend/src/users/users.service.spec.ts
git commit -m "feat: add UsersService.findById"
```

---

### Task 5: 백엔드 — Auth 배선 (login 확장, refresh/logout, 모듈, env)

**Files:**
- Create: `backend/src/auth/dto/refresh-token.dto.ts`
- Modify: `backend/src/auth/auth.service.ts`
- Modify: `backend/src/auth/auth.controller.ts`
- Modify: `backend/src/auth/auth.module.ts`
- Modify: `backend/.env.example`

**Interfaces:**
- Consumes: `RefreshTokensService.issue/rotate/revoke`(Task 1-3), `UsersService.findById`(Task 4)
- Produces: `POST /auth/login` → `{ accessToken, refreshToken }`; `POST /auth/refresh` → `{ accessToken, refreshToken }`; `POST /auth/logout` → `{}`. Task 8(모바일 `AuthRepository`)가 이 응답을 소비.

> 이 태스크는 `AuthService`/`AuthController`를 수정하므로 관련 스펙은 이 샌드박스에서 bcrypt 로드 실패로 실행되지 않는다(Global Constraints 참조). 검증은 `npm run build` + 전체 스위트(기존과 동일하게 `auth.service.spec.ts`만 실패)로 한다. 핵심 로직은 Task 1-4 스펙이 이미 커버.

- [ ] **Step 1: DTO 작성**

`backend/src/auth/dto/refresh-token.dto.ts`:

```typescript
import { IsString } from 'class-validator';

export class RefreshTokenDto {
  @IsString()
  refreshToken: string;
}
```

- [ ] **Step 2: `AuthService` 수정**

`backend/src/auth/auth.service.ts`의 import와 생성자, `login`을 수정하고 `refresh`/`logout`을 추가한다.

import 블록에 추가:

```typescript
import { RefreshTokensService } from './refresh-tokens.service';
```

생성자를 다음으로 교체:

```typescript
  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
    private readonly refreshTokensService: RefreshTokensService,
  ) {}
```

`login`의 반환부를 교체(비밀번호 검증 로직은 그대로 두고, 토큰 발급 부분만):

```typescript
    const accessToken = await this.jwtService.signAsync({
      sub: user.id,
      email: user.email,
    });
    const refreshToken = await this.refreshTokensService.issue(user.id);
    return { accessToken, refreshToken };
```

그리고 `login` 메서드의 반환 타입을 `Promise<{ accessToken: string; refreshToken: string }>`로 바꾼다.

클래스 끝(닫는 `}` 앞)에 추가:

```typescript
  async refresh(
    rawToken: string,
  ): Promise<{ accessToken: string; refreshToken: string }> {
    const { userId, refreshToken } =
      await this.refreshTokensService.rotate(rawToken);
    const user = await this.usersService.findById(userId);
    if (!user) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    const accessToken = await this.jwtService.signAsync({
      sub: user.id,
      email: user.email,
    });
    return { accessToken, refreshToken };
  }

  async logout(rawToken: string): Promise<void> {
    await this.refreshTokensService.revoke(rawToken);
  }
```

(`UnauthorizedException`은 파일 상단에서 이미 import되어 있다.)

- [ ] **Step 3: `AuthController` 수정**

`backend/src/auth/auth.controller.ts` 전체를 교체:

```typescript
import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { SignupDto } from './dto/signup.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('signup')
  signup(@Body() dto: SignupDto) {
    return this.authService.signup(dto);
  }

  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(200)
  async logout(@Body() dto: RefreshTokenDto) {
    await this.authService.logout(dto.refreshToken);
    return {};
  }
}
```

- [ ] **Step 4: `AuthModule` 수정**

`backend/src/auth/auth.module.ts`의 import 블록과 `@Module` imports/providers를 수정한다.

파일 상단 import에 추가:

```typescript
import { TypeOrmModule } from '@nestjs/typeorm';
import { RefreshToken } from './refresh-token.entity';
import { RefreshTokensService } from './refresh-tokens.service';
```

`@Module`의 `imports` 배열 맨 앞에 `TypeOrmModule.forFeature([RefreshToken]),`를 추가하고, `providers` 배열에 `RefreshTokensService`를 추가한다. 결과:

```typescript
  imports: [
    TypeOrmModule.forFeature([RefreshToken]),
    UsersModule,
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get('JWT_SECRET'),
        signOptions: { expiresIn: config.get('JWT_EXPIRES_IN') ?? '15m' },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, RefreshTokensService],
  exports: [AuthService],
```

(위 `useFactory`의 기본값을 `'1h'` → `'15m'`으로 함께 변경한다.)

- [ ] **Step 5: `.env.example` 수정**

`backend/.env.example`의 `JWT_EXPIRES_IN=1h`를 `JWT_EXPIRES_IN=15m`으로 바꾸고, 그 아래에 `REFRESH_TOKEN_TTL_DAYS=30`을 추가한다.

- [ ] **Step 6: 빌드 + 전체 스위트 확인**

Run: `cd backend && npm run build && npm run test`
Expected: 빌드 성공. 테스트는 이전과 동일한 패턴 — 신규 `refresh-tokens.service.spec.ts`/`users.service.spec.ts` 통과, `auth.service.spec.ts`만 이 샌드박스의 bcrypt 이슈로 실패(코드 결함 아님).

- [ ] **Step 7: 커밋**

```bash
git add backend/src/auth/ backend/.env.example
git commit -m "feat: issue refresh tokens on login and add refresh/logout endpoints"
```

---

### Task 6: 모바일 — `ApiException.statusCode`

**Files:**
- Modify: `mobile/lib/api/api_client.dart`
- Modify: `mobile/test/api/api_client_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `ApiException(message, {int? statusCode})` — Task 7(`AuthenticatedApiClient`)이 `statusCode == 401` 판별에 사용.

- [ ] **Step 1: 실패하는 테스트 작성 (`api_client_test.dart`의 `ApiClient.get` 그룹 안, 마지막 test 뒤에 추가)**

```dart
    test('carries the HTTP status code on the thrown ApiException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Unauthorized"}', 401);
      });
      final apiClient = ApiClient(httpClient: mockClient);

      await expectLater(
        () => apiClient.get('/matches', accessToken: 'bad-token'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: FAIL (`The getter 'statusCode' isn't defined for the type 'ApiException'`)

- [ ] **Step 3: 구현**

`mobile/lib/api/api_client.dart`의 `ApiException` 클래스를 교체:

```dart
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
```

그리고 `post`의 두 throw를 상태코드 포함으로 교체:

```dart
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'Invalid response from server',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['message']?.toString() ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
```

`post`의 `FormatException` catch도 교체:

```dart
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'Invalid response from server',
        statusCode: response.statusCode,
      );
    }
```

`get`도 동일하게: `FormatException` catch와 `>= 400` throw를 `statusCode: response.statusCode`를 포함하도록 교체:

```dart
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'Invalid response from server',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      final message =
          decoded is Map<String, dynamic> ? decoded['message']?.toString() : null;
      throw ApiException(
        message ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/api_client_test.dart`
Expected: PASS (기존 + 신규 1개)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/api/api_client.dart mobile/test/api/api_client_test.dart
git commit -m "feat: expose HTTP status code on ApiException"
```

---

### Task 7: 모바일 — `AuthenticatedApiClient`

**Files:**
- Create: `mobile/lib/api/authenticated_api_client.dart`
- Create: `mobile/test/api/authenticated_api_client_test.dart`

**Interfaces:**
- Consumes: `ApiClient`(기존), `ApiException.statusCode`(Task 6)
- Produces: `AuthenticatedApiClient(ApiClient api, String Function() currentAccessToken, Future<String> Function() refreshAccessToken)` with `get(String path): Future<dynamic>`, `post(String path, Map<String, dynamic> body): Future<Map<String, dynamic>>`. Task 9(리포지토리)가 소비.

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/api/authenticated_api_client_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';

void main() {
  group('AuthenticatedApiClient', () {
    test('attaches the current access token to the request', () async {
      String? sentAuth;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentAuth = request.headers['Authorization'];
          return http.Response('[]', 200);
        }),
      );
      final client = AuthenticatedApiClient(
        api,
        () => 'access-1',
        () async => 'unused',
      );

      await client.get('/matches');

      expect(sentAuth, 'Bearer access-1');
    });

    test('refreshes once and retries with the new token on a 401', () async {
      var calls = 0;
      final authHeaders = <String?>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          calls++;
          authHeaders.add(request.headers['Authorization']);
          if (calls == 1) {
            return http.Response('{"message": "expired"}', 401);
          }
          return http.Response('{"ok": true}', 200);
        }),
      );
      var refreshCalls = 0;
      final client = AuthenticatedApiClient(
        api,
        () => 'stale',
        () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      final result = await client.post('/swipes', {'x': 1});

      expect(refreshCalls, 1);
      expect(calls, 2);
      expect(authHeaders, ['Bearer stale', 'Bearer fresh']);
      expect(result, {'ok': true});
    });

    test('does not refresh on a non-401 error', () async {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          return http.Response('{"message": "boom"}', 500);
        }),
      );
      var refreshCalls = 0;
      final client = AuthenticatedApiClient(
        api,
        () => 'access-1',
        () async {
          refreshCalls++;
          return 'fresh';
        },
      );

      await expectLater(
        () => client.get('/matches'),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/authenticated_api_client_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:mobile/api/authenticated_api_client.dart'`)

- [ ] **Step 3: 구현**

`mobile/lib/api/authenticated_api_client.dart`:

```dart
import 'api_client.dart';

/// Wraps [ApiClient] with the current access token and transparent
/// single-retry refresh on a 401. Auth token accessors are injected as
/// functions so this stays decoupled from AppSession and easy to test.
class AuthenticatedApiClient {
  AuthenticatedApiClient(
    this._api,
    this._currentAccessToken,
    this._refreshAccessToken,
  );

  final ApiClient _api;
  final String Function() _currentAccessToken;
  final Future<String> Function() _refreshAccessToken;

  Future<dynamic> get(String path) async {
    try {
      return await _api.get(path, accessToken: _currentAccessToken());
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.get(path, accessToken: newToken);
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _api.post(path, body, accessToken: _currentAccessToken());
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final newToken = await _refreshAccessToken();
      return await _api.post(path, body, accessToken: newToken);
    }
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/api/authenticated_api_client_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/api/authenticated_api_client.dart mobile/test/api/authenticated_api_client_test.dart
git commit -m "feat: add AuthenticatedApiClient with 401 refresh-and-retry"
```

---

### Task 8: 모바일 — `AuthRepository` login 확장 + refresh/logout

**Files:**
- Modify: `mobile/lib/auth/auth_repository.dart`
- Create: `mobile/test/auth/auth_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`(기존)
- Produces: `AuthRepository.login(email, password): Future<({String accessToken, String refreshToken})>`, `AuthRepository.refresh(String refreshToken): Future<({String accessToken, String refreshToken})>`, `AuthRepository.logout(String refreshToken): Future<void>`. Task 10(`AppSession`)이 소비.

- [ ] **Step 1: 실패하는 테스트 작성**

`mobile/test/auth/auth_repository_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/auth/auth_repository.dart';

void main() {
  group('AuthRepository', () {
    test('login returns both access and refresh tokens', () async {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'accessToken': 'a-1', 'refreshToken': 'r-1'}),
            200,
          );
        }),
      );
      final repo = AuthRepository(api);

      final tokens = await repo.login('jane@example.com', 'pw');

      expect(tokens.accessToken, 'a-1');
      expect(tokens.refreshToken, 'r-1');
    });

    test('refresh posts the refresh token and returns the rotated pair',
        () async {
      String? sentPath;
      Map<String, dynamic>? sentBody;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentPath = request.url.path;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'accessToken': 'a-2', 'refreshToken': 'r-2'}),
            200,
          );
        }),
      );
      final repo = AuthRepository(api);

      final tokens = await repo.refresh('r-1');

      expect(sentPath, '/auth/refresh');
      expect(sentBody, {'refreshToken': 'r-1'});
      expect(tokens.accessToken, 'a-2');
      expect(tokens.refreshToken, 'r-2');
    });

    test('logout posts the refresh token to /auth/logout', () async {
      String? sentPath;
      final api = ApiClient(
        httpClient: MockClient((request) async {
          sentPath = request.url.path;
          return http.Response('{}', 200);
        }),
      );
      final repo = AuthRepository(api);

      await repo.logout('r-1');

      expect(sentPath, '/auth/logout');
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/auth_repository_test.dart`
Expected: FAIL (`login`의 반환 타입이 `Future<String>`이라 `tokens.accessToken` 접근 불가; `refresh`/`logout` 미정의)

- [ ] **Step 3: 구현 (`auth_repository.dart` 전체 교체)**

```dart
import '../api/api_client.dart';

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<({String accessToken, String refreshToken})> login(
    String email,
    String password,
  ) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return (
      accessToken: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String,
    );
  }

  Future<void> signup(String email, String password) async {
    await _apiClient.post('/auth/signup', {
      'email': email,
      'password': password,
    });
  }

  Future<({String accessToken, String refreshToken})> refresh(
    String refreshToken,
  ) async {
    final result = await _apiClient.post('/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return (
      accessToken: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String,
    );
  }

  Future<void> logout(String refreshToken) async {
    await _apiClient.post('/auth/logout', {'refreshToken': refreshToken});
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/auth/auth_repository_test.dart`
Expected: PASS (3/3)

(참고: `AppSession`/`login_screen`은 아직 옛 `login` 반환을 참조하므로 이 시점의 **전체** 스위트/analyze는 실패할 수 있다. Task 10에서 정리한다. 이 태스크는 해당 파일 테스트만 통과시키면 된다.)

- [ ] **Step 5: 커밋**

```bash
git add mobile/lib/auth/auth_repository.dart mobile/test/auth/auth_repository_test.dart
git commit -m "feat: return token pair from AuthRepository.login, add refresh/logout"
```

---

### Task 9: 모바일 — 리포지토리를 `AuthenticatedApiClient`로 이관

**Files:**
- Modify: `mobile/lib/discover/discover_repository.dart`
- Modify: `mobile/lib/matches/matches_repository.dart`
- Modify: `mobile/test/discover/discover_repository_test.dart`
- Modify: `mobile/test/matches/matches_repository_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedApiClient`(Task 7)
- Produces: `DiscoverRepository(AuthenticatedApiClient)` / `MatchesRepository(AuthenticatedApiClient)` — 생성자에서 토큰 인자 제거. `fetchCandidates`/`swipe`/`listMatches` 시그니처는 동일. Task 10(`AppSession`)이 새 생성자를 사용.

- [ ] **Step 1: 실패하는 테스트 작성 (`discover_repository_test.dart` 전체 교체)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/discover/discover_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('DiscoverRepository', () {
    test('fetchCandidates returns the candidate list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/swipes/candidates')).thenAnswer(
        (_) async => {
          'candidates': [
            {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
          ],
        },
      );
      final repo = DiscoverRepository(client);

      final result = await repo.fetchCandidates();

      expect(result, [
        {'userId': 'user-2', 'displayName': 'Jane', 'bio': 'Hi'},
      ]);
    });

    test('fetchCandidates throws when the shape is invalid', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/swipes/candidates'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = DiscoverRepository(client);

      expect(() => repo.fetchCandidates(), throwsA(isA<ApiException>()));
    });

    test('swipe posts and reports whether a match resulted', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.post('/swipes', {'targetUserId': 'user-2', 'liked': true}))
          .thenAnswer((_) async => {'swipe': {}, 'match': {'id': 'm-1'}});
      final repo = DiscoverRepository(client);

      final matched = await repo.swipe('user-2', true);

      expect(matched, isTrue);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/discover/discover_repository_test.dart`
Expected: FAIL (`DiscoverRepository`가 첫 인자로 `AuthenticatedApiClient`를 받지 않음 — 타입 불일치)

- [ ] **Step 3: `DiscoverRepository` 교체**

`mobile/lib/discover/discover_repository.dart`:

```dart
import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<List<Map<String, dynamic>>> fetchCandidates() async {
    final decoded = await _client.get('/swipes/candidates');
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw ApiException('Invalid response from server');
    }
    return (decoded['candidates'] as List).cast<Map<String, dynamic>>();
  }

  Future<bool> swipe(String targetUserId, bool liked) async {
    final result = await _client.post(
      '/swipes',
      {'targetUserId': targetUserId, 'liked': liked},
    );
    return result['match'] != null;
  }
}
```

- [ ] **Step 4: `matches_repository_test.dart` 전체 교체**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/api/authenticated_api_client.dart';
import 'package:mobile/matches/matches_repository.dart';

class MockAuthenticatedApiClient extends Mock
    implements AuthenticatedApiClient {}

void main() {
  group('MatchesRepository.listMatches', () {
    test('returns the parsed match list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/matches')).thenAnswer(
        (_) async => [
          {'id': 'match-1', 'counterpartUserId': 'user-2', 'counterpartName': 'Jane'},
        ],
      );
      final repo = MatchesRepository(client);

      final result = await repo.listMatches();

      expect(result, [
        {'id': 'match-1', 'counterpartUserId': 'user-2', 'counterpartName': 'Jane'},
      ]);
    });

    test('throws ApiException when the response is not a list', () async {
      final client = MockAuthenticatedApiClient();
      when(() => client.get('/matches'))
          .thenAnswer((_) async => {'unexpected': 'shape'});
      final repo = MatchesRepository(client);

      expect(() => repo.listMatches(), throwsA(isA<ApiException>()));
    });
  });
}
```

- [ ] **Step 5: `MatchesRepository` 교체**

`mobile/lib/matches/matches_repository.dart`:

```dart
import '../api/api_client.dart';
import '../api/authenticated_api_client.dart';

class MatchesRepository {
  MatchesRepository(this._client);

  final AuthenticatedApiClient _client;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final decoded = await _client.get('/matches');
    if (decoded is! List) {
      throw ApiException('Invalid response from server');
    }
    return decoded.cast<Map<String, dynamic>>();
  }
}
```

- [ ] **Step 6: 두 리포지토리 테스트 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/discover/discover_repository_test.dart test/matches/matches_repository_test.dart`
Expected: PASS (Discover 3개, Matches 2개)

(참고: `app_session.dart`가 아직 옛 생성자를 참조하므로 전체 스위트는 Task 10 완료 전까지 실패한다.)

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/discover/discover_repository.dart mobile/lib/matches/matches_repository.dart mobile/test/discover/discover_repository_test.dart mobile/test/matches/matches_repository_test.dart
git commit -m "refactor: route Discover/Matches repositories through AuthenticatedApiClient"
```

---

### Task 10: 모바일 — `AppSession` 리프레시 배선

**Files:**
- Modify: `mobile/lib/app_session.dart`
- Modify: `mobile/test/app_session_test.dart`
- Modify: `mobile/test/auth/login_screen_test.dart`
- Modify: `mobile/test/auth_gate_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`(Task 8), `AuthenticatedApiClient`(Task 7), `DiscoverRepository`/`MatchesRepository`(Task 9)
- Produces: 없음(조립 지점). `AppSession.login/logout` 시그니처는 유지, 내부적으로 리프레시 토큰 보관 + 401 자동 갱신.

- [ ] **Step 1: 실패하는 테스트 작성 (`app_session_test.dart` 하단에 새 그룹 추가)**

기존 `app_session_test.dart`의 로그인 mock들이 `{'accessToken': token}`만 반환하므로, 먼저 파일 내 모든 `http.Response(jsonEncode({'accessToken': token}), 200)`를 `http.Response(jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}), 200)`로 바꾼다. 그런 다음 파일 맨 끝(마지막 `}` 앞, `group('AppSession', ...)` 밖)에 새 그룹을 추가한다:

```dart
  group('AppSession refresh', () {
    test('refreshes the access token and retries when a repository sees a 401',
        () async {
      final freshAccess = _fakeJwt({'sub': 'user-1', 'email': 'jane@x.com'});
      var candidatesCalls = 0;
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': 'access-old', 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'accessToken': freshAccess, 'refreshToken': 'r-2'}),
            200,
          );
        }
        if (path == '/swipes/candidates') {
          candidatesCalls++;
          if (candidatesCalls == 1) {
            return http.Response(jsonEncode({'message': 'expired'}), 401);
          }
          return http.Response(jsonEncode({'candidates': []}), 200);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@x.com', 'pw');

      // First candidates call 401s -> AppSession refreshes -> retry succeeds.
      final result = await session.discoverRepository.fetchCandidates();

      expect(result, isEmpty);
      expect(candidatesCalls, 2);
    });

    test('logs out when the refresh itself fails', () async {
      var candidatesCalls = 0;
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': 'access-old', 'refreshToken': 'r-1'}),
            200,
          );
        }
        if (path == '/auth/refresh') {
          return http.Response(jsonEncode({'message': 'revoked'}), 401);
        }
        if (path == '/swipes/candidates') {
          candidatesCalls++;
          return http.Response(jsonEncode({'message': 'expired'}), 401);
        }
        return http.Response(jsonEncode({'message': 'not found'}), 404);
      });
      final session = AppSession(
        baseUrl: 'http://localhost:3000',
        apiClient:
            ApiClient(baseUrl: 'http://localhost:3000', httpClient: mockClient),
      );
      await session.login('jane@x.com', 'pw');

      await expectLater(
        () => session.discoverRepository.fetchCandidates(),
        throwsA(isA<ApiException>()),
      );
      expect(session.isAuthenticated, isFalse);
    });
  });
```

(파일 상단에 이미 `_fakeJwt` 헬퍼가 정의되어 있다 — 재사용한다.)

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart`
Expected: FAIL (컴파일 에러 — `AppSession`이 아직 리프레시 토큰/`AuthenticatedApiClient` 배선을 안 함, 리포지토리 생성자 불일치)

- [ ] **Step 3: `AppSession` 교체**

`mobile/lib/app_session.dart` 전체:

```dart
import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'api/authenticated_api_client.dart';
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
  String? _refreshToken;
  String? _userId;
  Future<String>? _inFlightRefresh;
  DiscoverRepository? _discoverRepository;
  MatchesRepository? _matchesRepository;

  bool get isAuthenticated => _accessToken != null;
  String? get userId => _userId;

  late final AuthRepository authRepository = AuthRepository(_apiClient);

  late final AuthenticatedApiClient _authClient = AuthenticatedApiClient(
    _apiClient,
    _requireToken,
    _refresh,
  );

  DiscoverRepository get discoverRepository =>
      _discoverRepository ??= DiscoverRepository(_authClient);

  MatchesRepository get matchesRepository =>
      _matchesRepository ??= MatchesRepository(_authClient);

  String _requireToken() {
    final token = _accessToken;
    if (token == null) {
      throw StateError('AppSession: not authenticated');
    }
    return token;
  }

  Future<void> login(String email, String password) async {
    final tokens = await authRepository.login(email, password);
    final userId = decodeUserId(tokens.accessToken);
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    _userId = userId;
    notifyListeners();
  }

  /// Single-flight refresh: concurrent 401s share one in-flight refresh.
  Future<String> _refresh() {
    return _inFlightRefresh ??=
        _doRefresh().whenComplete(() => _inFlightRefresh = null);
  }

  Future<String> _doRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw StateError('AppSession: not authenticated');
    }
    try {
      final tokens = await authRepository.refresh(refreshToken);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      return tokens.accessToken;
    } catch (_) {
      logout();
      rethrow;
    }
  }

  void logout() {
    final refreshToken = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _discoverRepository = null;
    _matchesRepository = null;
    notifyListeners();
    if (refreshToken != null) {
      // Best-effort server-side revocation; ignore failures.
      authRepository.logout(refreshToken).catchError((_) {});
    }
  }

  ChatSocketClient buildChatSocketClient() {
    return ChatSocketClient(_baseUrl, _requireToken());
  }
}
```

- [ ] **Step 4: `login_screen_test.dart`와 `auth_gate_test.dart`의 로그인 mock 갱신**

두 파일에서 로그인 응답 mock을 리프레시 토큰 포함으로 바꾼다. 각 파일의
`http.Response(jsonEncode({'accessToken': token}), 200)`(또는 `/auth/login` 분기의 동등 표현)을
`http.Response(jsonEncode({'accessToken': token, 'refreshToken': 'r-1'}), 200)`으로 교체한다.

`auth_gate_test.dart`의 경우 `if (request.url.path == '/auth/login')` 분기의 응답만 위와 같이 바꾸면 된다(나머지 `/swipes/candidates`, `/matches` 분기는 그대로 둔다).

- [ ] **Step 5: 대상 테스트들 통과 확인**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test test/app_session_test.dart test/auth/login_screen_test.dart test/auth_gate_test.dart`
Expected: PASS (전부)

- [ ] **Step 6: 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, analyze 클린

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/app_session.dart mobile/test/app_session_test.dart mobile/test/auth/login_screen_test.dart mobile/test/auth_gate_test.dart
git commit -m "feat: wire refresh-token storage and auto-refresh into AppSession"
```

---

### Task 11: 검증 + README/문서 갱신

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 없음 (검증 전용)
- Produces: 없음

- [ ] **Step 1: 백엔드 전체 스위트 + 빌드**

Run: `cd backend && npm run test && npm run build`
Expected: 신규 스펙 통과, `auth.service.spec.ts`만 이 샌드박스의 bcrypt 이슈로 실패(코드 결함 아님), 빌드 성공.

- [ ] **Step 2: 모바일 전체 스위트 + analyze**

Run: `export PATH="/Users/studio/development/flutter/bin:$PATH" && cd mobile && flutter test && flutter analyze`
Expected: 전체 PASS, 클린.

- [ ] **Step 3: README 갱신**

`README.md`를 Read한 뒤 다음을 반영한다(기존 문구에 자연스럽게 병합):

- "알려진 제약" 섹션에서 `- 리프레시 토큰 미구현 (액세스 토큰만, 1시간 만료) — 서브프로젝트 3에서 다룰 예정` 항목을 제거한다.
- 백엔드 `auth/` 설명에 리프레시 토큰(회전/재사용감지, `POST /auth/refresh`·`POST /auth/logout`)을 추가한다.
- "현재 상태 / Known limitations"에 다음 두 줄을 추가한다:
  - 리프레시 토큰은 모바일 메모리에만 보관되어 앱 재시작 시 로그아웃된다(기기 영속 저장은 별개 후속 항목).
  - 채팅 WebSocket은 연결 시점의 액세스 토큰을 사용하며, 장시간 연결 중 액세스 토큰 만료를 자동 갱신하지 않는다.

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: document refresh-token flow and update limitations"
```

## Self-Review 결과

- **스펙 커버리지:** 토큰 수명/형태(Task 5 env + Task 1 issue), 데이터 모델(Task 1 엔티티), `/auth/login` 확장·`/auth/refresh`·`/auth/logout`(Task 5), 회전·재사용감지(Task 2), 폐기(Task 3), `findById`(Task 4), `ApiException.statusCode`(Task 6), `AuthenticatedApiClient`(Task 7), `AuthRepository`(Task 8), 리포지토리 이관(Task 9), `AppSession` single-flight/자동갱신/logout(Task 10), 검증·문서(Task 11) — 스펙 전 항목 커버.
- **플레이스홀더 스캔:** 없음. 모든 코드 스텝에 실제 코드 포함.
- **타입 일관성:** `RefreshTokensService.issue/rotate/revoke/revokeAllForUser` 시그니처가 Task 1-3 정의와 Task 5 소비처에서 일치. `AuthRepository`의 record 반환 `({String accessToken, String refreshToken})`이 Task 8 정의와 Task 10 소비에서 일치. `AuthenticatedApiClient(api, String Function(), Future<String> Function())` 생성자가 Task 7 정의와 Task 10 배선(`_requireToken`, `_refresh`)에서 일치. 리포지토리 단일 인자 생성자(Task 9)가 Task 10의 `DiscoverRepository(_authClient)`/`MatchesRepository(_authClient)`와 일치. `/auth/logout`이 `{}`(2xx JSON)를 반환하므로 모바일 `ApiClient.post`의 JSON-객체 요구와 일치.
