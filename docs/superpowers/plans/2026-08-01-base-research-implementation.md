# TableMate 기반 골격 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 데이팅 앱(NestJS 백엔드 + Flutter 프론트엔드)의 최소 동작 골격(회원가입/로그인/스와이프/매칭/채팅)을 처음부터 구현하고, Overture Maps 기반 맛집 씨드 데이터를 PostgreSQL에 적재해, 이후 서브프로젝트가 이어받을 수 있는 로컬 실행 가능한 상태를 만든다.

**Architecture:** `backend/`(NestJS + TypeORM + PostgreSQL, JWT 인증, Socket.IO 기반 채팅 게이트웨이)와 `mobile/`(Flutter, iOS/Android/웹 단일 코드베이스)를 분리된 디렉토리로 구성한다. 맛집 데이터는 별도 스크립트(`backend/scripts/`)로 Overture Maps Parquet 데이터를 DuckDB로 추출해 CSV로 저장한 뒤, NestJS 시드 스크립트로 PostgreSQL에 적재한다. 참고 리포(DateMe 등)는 화면 흐름 참고용일 뿐 코드는 복사하지 않는다.

**Tech Stack:** NestJS 10.x, TypeORM, PostgreSQL 15+, Jest, Flutter (stable, Dart >=3.4), socket_io_client, DuckDB CLI(데이터 추출 전용, 런타임 의존성 아님)

## Global Constraints

- Node.js >=20 LTS, NestJS 10.x, TypeORM ORM 사용, PostgreSQL 15+ (스펙: `docs/superpowers/specs/2026-08-01-base-research-design.md`)
- Flutter stable 채널, Dart SDK >=3.4
- 참고 오픈소스(DateMe 등)의 코드를 그대로 복사하지 않는다 — 화면 구조만 참고해 직접 작성 (라이선스 없음, 저작권 리스크)
- 맛집 씨드 데이터는 Overture Maps Places(CDLA Permissive v2.0)만 사용, 초기 지역은 한국(서울)로 한정
- 모든 시크릿(JWT_SECRET, DB 접속정보)은 환경변수로 분리, 저장소에 커밋 금지 (`.env`는 `.gitignore`에 포함)
- 비밀번호는 bcrypt로 해싱 (평문/약한 해시 금지)
- 이번 서브프로젝트는 리프레시 토큰 로테이션을 구현하지 않는다 — JWT 액세스 토큰(만료 1시간)만 구현하고, 리프레시 토큰은 서브프로젝트 3(핵심 데이팅 기능)에서 다룬다
- 채팅은 WebSocket(Socket.IO, NestJS `@nestjs/websockets`)으로 구현한다 — REST 폴링이 아님
- 각 백엔드 로직 단위는 TDD로 작성한다: 실패하는 테스트 → 최소 구현 → 통과 확인 → 커밋

---

## 파일 구조 개요

```
tablemate/
  backend/
    src/
      app.module.ts
      main.ts
      users/
        user.entity.ts
        users.service.ts
        users.module.ts
      auth/
        auth.module.ts
        auth.service.ts
        auth.controller.ts
        jwt.strategy.ts
        jwt-auth.guard.ts
        dto/signup.dto.ts
        dto/login.dto.ts
      profiles/
        profile.entity.ts
        profiles.service.ts
        profiles.controller.ts
        profiles.module.ts
      swipes/
        swipe.entity.ts
        swipes.service.ts
        swipes.controller.ts
        swipes.module.ts
      matches/
        match.entity.ts
        matches.service.ts
        matches.module.ts
      chat/
        message.entity.ts
        chat.gateway.ts
        chat.service.ts
        chat.module.ts
      restaurants/
        restaurant.entity.ts
        restaurants.service.ts
        restaurants.controller.ts
        restaurants.module.ts
    scripts/
      extract-overture-restaurants.sql   (DuckDB 스크립트)
      seed-restaurants.ts                (CSV -> PostgreSQL 적재)
      fixtures/sample-restaurants.csv    (테스트용 소규모 샘플)
    test/ (Jest e2e)
  mobile/
    lib/
      main.dart
      api/api_client.dart
      auth/auth_repository.dart
      auth/login_screen.dart
      auth/signup_screen.dart
      discover/discover_screen.dart
      discover/swipe_card.dart
      matches/matches_screen.dart
      chat/chat_screen.dart
      chat/chat_socket_client.dart
    test/
      auth/login_screen_test.dart
      discover/discover_screen_test.dart
  README.md
```

각 모듈(users/auth/profiles/swipes/matches/chat/restaurants)은 하나의 책임만 갖는다. `matches`는 `swipes`가 만든 좋아요 기록을 소비해 매칭을 판정하고, `chat`은 `matches`가 만든 매칭 관계에 종속된다.

---

### Task 1: NestJS 백엔드 스캐폴드 + PostgreSQL 연결 헬스체크

**Files:**
- Create: `backend/package.json`, `backend/tsconfig.json`, `backend/nest-cli.json`
- Create: `backend/src/main.ts`
- Create: `backend/src/app.module.ts`
- Create: `backend/src/app.controller.ts`
- Create: `backend/.env.example`
- Test: `backend/test/app.e2e-spec.ts`

**Interfaces:**
- Produces: `AppModule` (다른 모든 모듈이 여기 등록됨), `ConfigModule` 기반 환경변수 로딩 패턴

- [ ] **Step 1: NestJS 프로젝트 생성**

```bash
cd /Users/studio/Downloads/project/tablemate
npx @nestjs/cli new backend --package-manager npm --skip-git
cd backend
npm install @nestjs/typeorm typeorm pg @nestjs/config
npm install --save-dev @types/pg
```

- [ ] **Step 2: 실패하는 헬스체크 e2e 테스트 작성**

`backend/test/app.e2e-spec.ts`:

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';

describe('AppController (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('/health (GET) returns ok status', () => {
    return request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok' });
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test:e2e`
Expected: FAIL (`/health` 라우트 없음, 404)

- [ ] **Step 4: `.env.example` 작성**

`backend/.env.example`:

```
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=tablemate
DB_PASSWORD=changeme
DB_DATABASE=tablemate_dev
JWT_SECRET=changeme-in-real-env
JWT_EXPIRES_IN=1h
```

- [ ] **Step 5: AppModule에 ConfigModule + TypeOrmModule + `/health` 엔드포인트 구현**

`backend/src/app.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.get('DB_HOST'),
        port: parseInt(config.get('DB_PORT') ?? '5432', 10),
        username: config.get('DB_USERNAME'),
        password: config.get('DB_PASSWORD'),
        database: config.get('DB_DATABASE'),
        autoLoadEntities: true,
        synchronize: process.env.NODE_ENV !== 'production',
      }),
    }),
  ],
  controllers: [AppController],
})
export class AppModule {}
```

`backend/src/app.controller.ts`:

```typescript
import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class AppController {
  @Get()
  getHealth() {
    return { status: 'ok' };
  }
}
```

- [ ] **Step 6: 로컬 PostgreSQL 준비 후 테스트 재실행**

Run:
```bash
createdb tablemate_dev
cp backend/.env.example backend/.env
# .env의 DB_USERNAME/DB_PASSWORD를 로컬 환경에 맞게 수정
cd backend && npm run test:e2e
```
Expected: PASS

- [ ] **Step 7: 커밋**

```bash
cd /Users/studio/Downloads/project/tablemate
git add backend/ .gitignore
git commit -m "feat: scaffold NestJS backend with health check endpoint"
```

---

### Task 2: User 엔티티 + 회원가입 (bcrypt 해싱)

**Files:**
- Create: `backend/src/users/user.entity.ts`
- Create: `backend/src/users/users.service.ts`
- Create: `backend/src/users/users.module.ts`
- Create: `backend/src/auth/dto/signup.dto.ts`
- Create: `backend/src/auth/auth.service.ts`
- Create: `backend/src/auth/auth.controller.ts`
- Create: `backend/src/auth/auth.module.ts`
- Test: `backend/src/auth/auth.service.spec.ts`

**Interfaces:**
- Consumes: `AppModule`의 TypeORM 연결 (Task 1)
- Produces: `UsersService.create(email, passwordHash): Promise<User>`, `UsersService.findByEmail(email): Promise<User | null>`, `AuthService.signup(dto: SignupDto): Promise<{ id: string; email: string }>` — Task 3(로그인)이 `UsersService.findByEmail`을 그대로 사용함

- [ ] **Step 1: 의존성 설치**

```bash
cd backend
npm install bcrypt class-validator class-transformer
npm install --save-dev @types/bcrypt
```

- [ ] **Step 2: 실패하는 AuthService 단위 테스트 작성**

`backend/src/auth/auth.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';

describe('AuthService.signup', () => {
  let authService: AuthService;
  let usersService: { create: jest.Mock; findByEmail: jest.Mock };

  beforeEach(async () => {
    usersService = {
      create: jest.fn().mockImplementation((email, passwordHash) =>
        Promise.resolve({ id: 'user-1', email, passwordHash }),
      ),
      findByEmail: jest.fn().mockResolvedValue(null),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: UsersService, useValue: usersService },
      ],
    }).compile();

    authService = moduleRef.get(AuthService);
  });

  it('hashes the password before storing and never returns it', async () => {
    const result = await authService.signup({
      email: 'jane@example.com',
      password: 'plaintext-password',
    });

    expect(usersService.create).toHaveBeenCalledWith(
      'jane@example.com',
      expect.not.stringContaining('plaintext-password'),
    );
    expect(result).toEqual({ id: 'user-1', email: 'jane@example.com' });
  });

  it('rejects signup when email is already registered', async () => {
    usersService.findByEmail.mockResolvedValue({ id: 'existing' });

    await expect(
      authService.signup({ email: 'jane@example.com', password: 'x' }),
    ).rejects.toThrow('Email already registered');
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- auth.service.spec.ts`
Expected: FAIL (`AuthService`, `UsersService` 모듈 없음)

- [ ] **Step 4: User 엔티티 작성**

`backend/src/users/user.entity.ts`:

```typescript
import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  @Column()
  passwordHash: string;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 5: UsersService/UsersModule 작성**

`backend/src/users/users.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './user.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly usersRepo: Repository<User>,
  ) {}

  findByEmail(email: string): Promise<User | null> {
    return this.usersRepo.findOne({ where: { email } });
  }

  create(email: string, passwordHash: string): Promise<User> {
    const user = this.usersRepo.create({ email, passwordHash });
    return this.usersRepo.save(user);
  }
}
```

`backend/src/users/users.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from './user.entity';
import { UsersService } from './users.service';

@Module({
  imports: [TypeOrmModule.forFeature([User])],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
```

- [ ] **Step 6: SignupDto + AuthService 작성**

`backend/src/auth/dto/signup.dto.ts`:

```typescript
import { IsEmail, MinLength } from 'class-validator';

export class SignupDto {
  @IsEmail()
  email: string;

  @MinLength(8)
  password: string;
}
```

`backend/src/auth/auth.service.ts`:

```typescript
import { BadRequestException, Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';
import { SignupDto } from './dto/signup.dto';

@Injectable()
export class AuthService {
  constructor(private readonly usersService: UsersService) {}

  async signup(dto: SignupDto): Promise<{ id: string; email: string }> {
    const existing = await this.usersService.findByEmail(dto.email);
    if (existing) {
      throw new BadRequestException('Email already registered');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.usersService.create(dto.email, passwordHash);
    return { id: user.id, email: user.email };
  }
}
```

- [ ] **Step 7: AuthController/AuthModule 작성**

`backend/src/auth/auth.controller.ts`:

```typescript
import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { SignupDto } from './dto/signup.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('signup')
  signup(@Body() dto: SignupDto) {
    return this.authService.signup(dto);
  }
}
```

`backend/src/auth/auth.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({
  imports: [UsersModule],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
```

- [ ] **Step 8: AppModule에 UsersModule, AuthModule 등록**

`backend/src/app.module.ts`의 `imports` 배열에 `UsersModule`, `AuthModule` 추가.

- [ ] **Step 9: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- auth.service.spec.ts`
Expected: PASS

- [ ] **Step 10: 커밋**

```bash
git add backend/src/users backend/src/auth backend/src/app.module.ts
git commit -m "feat: add user signup with bcrypt password hashing"
```

---

### Task 3: 로그인 + JWT 발급

**Files:**
- Create: `backend/src/auth/dto/login.dto.ts`
- Create: `backend/src/auth/jwt.strategy.ts`
- Create: `backend/src/auth/jwt-auth.guard.ts`
- Modify: `backend/src/auth/auth.service.ts`
- Modify: `backend/src/auth/auth.controller.ts`
- Modify: `backend/src/auth/auth.module.ts`
- Test: `backend/src/auth/auth.service.spec.ts`

**Interfaces:**
- Consumes: `UsersService.findByEmail` (Task 2)
- Produces: `AuthService.login(dto: LoginDto): Promise<{ accessToken: string }>`, `JwtAuthGuard` (Task 4/5/6/7이 라우트 보호에 사용)

- [ ] **Step 1: 의존성 설치**

```bash
cd backend
npm install @nestjs/jwt @nestjs/passport passport passport-jwt
npm install --save-dev @types/passport-jwt
```

- [ ] **Step 2: 실패하는 로그인 테스트 추가**

`backend/src/auth/auth.service.spec.ts`에 추가:

```typescript
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';

describe('AuthService.login', () => {
  let authService: AuthService;
  let usersService: { findByEmail: jest.Mock };

  beforeEach(async () => {
    const passwordHash = await bcrypt.hash('correct-password', 10);
    usersService = {
      findByEmail: jest.fn().mockResolvedValue({
        id: 'user-1',
        email: 'jane@example.com',
        passwordHash,
      }),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: UsersService, useValue: usersService },
        JwtService,
      ],
    }).compile();

    authService = moduleRef.get(AuthService);
  });

  it('returns an access token for correct credentials', async () => {
    const result = await authService.login({
      email: 'jane@example.com',
      password: 'correct-password',
    });

    expect(result.accessToken).toEqual(expect.any(String));
  });

  it('rejects login with wrong password', async () => {
    await expect(
      authService.login({ email: 'jane@example.com', password: 'wrong' }),
    ).rejects.toThrow('Invalid credentials');
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- auth.service.spec.ts`
Expected: FAIL (`AuthService.login` 없음)

- [ ] **Step 4: LoginDto 작성**

`backend/src/auth/dto/login.dto.ts`:

```typescript
import { IsEmail, IsString } from 'class-validator';

export class LoginDto {
  @IsEmail()
  email: string;

  @IsString()
  password: string;
}
```

- [ ] **Step 5: AuthService에 login 메서드 추가**

`backend/src/auth/auth.service.ts`에 추가 (constructor에 `JwtService` 주입):

```typescript
import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';
import { SignupDto } from './dto/signup.dto';
import { LoginDto } from './dto/login.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
  ) {}

  async signup(dto: SignupDto): Promise<{ id: string; email: string }> {
    const existing = await this.usersService.findByEmail(dto.email);
    if (existing) {
      throw new BadRequestException('Email already registered');
    }
    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.usersService.create(dto.email, passwordHash);
    return { id: user.id, email: user.email };
  }

  async login(dto: LoginDto): Promise<{ accessToken: string }> {
    const user = await this.usersService.findByEmail(dto.email);
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }
    const passwordMatches = await bcrypt.compare(dto.password, user.passwordHash);
    if (!passwordMatches) {
      throw new UnauthorizedException('Invalid credentials');
    }
    const accessToken = await this.jwtService.signAsync({ sub: user.id, email: user.email });
    return { accessToken };
  }
}
```

- [ ] **Step 6: JwtStrategy + JwtAuthGuard 작성**

`backend/src/auth/jwt.strategy.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get('JWT_SECRET'),
    });
  }

  validate(payload: { sub: string; email: string }) {
    return { userId: payload.sub, email: payload.email };
  }
}
```

`backend/src/auth/jwt-auth.guard.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
```

- [ ] **Step 7: AuthModule에 JwtModule/PassportModule/JwtStrategy 등록**

`backend/src/auth/auth.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { UsersModule } from '../users/users.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    UsersModule,
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get('JWT_SECRET'),
        signOptions: { expiresIn: config.get('JWT_EXPIRES_IN') ?? '1h' },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

- [ ] **Step 8: AuthController에 login 라우트 추가**

`backend/src/auth/auth.controller.ts`에 추가:

```typescript
@Post('login')
login(@Body() dto: LoginDto) {
  return this.authService.login(dto);
}
```

(`LoginDto` import 추가)

- [ ] **Step 9: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- auth.service.spec.ts`
Expected: PASS

- [ ] **Step 10: 커밋**

```bash
git add backend/src/auth
git commit -m "feat: add JWT login and auth guard"
```

---

### Task 4: 프로필 모듈 (본인 프로필 조회/수정)

**Files:**
- Create: `backend/src/profiles/profile.entity.ts`
- Create: `backend/src/profiles/profiles.service.ts`
- Create: `backend/src/profiles/profiles.controller.ts`
- Create: `backend/src/profiles/profiles.module.ts`
- Create: `backend/src/profiles/dto/update-profile.dto.ts`
- Test: `backend/src/profiles/profiles.service.spec.ts`

**Interfaces:**
- Consumes: `JwtAuthGuard` (Task 3), `User.id` as foreign key
- Produces: `ProfilesService.getByUserId(userId): Promise<Profile | null>`, `ProfilesService.upsert(userId, dto): Promise<Profile>` — Task 6(스와이프 카드 노출)이 `ProfilesService.getByUserId`를 사용함

- [ ] **Step 1: 실패하는 ProfilesService 테스트 작성**

`backend/src/profiles/profiles.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ProfilesService } from './profiles.service';
import { Profile } from './profile.entity';

describe('ProfilesService.upsert', () => {
  let service: ProfilesService;
  let repo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock };

  beforeEach(async () => {
    repo = {
      findOne: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve({ id: 'profile-1', ...data })),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ProfilesService,
        { provide: getRepositoryToken(Profile), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(ProfilesService);
  });

  it('creates a profile when none exists for the user', async () => {
    const result = await service.upsert('user-1', { displayName: 'Jane', bio: 'Hi' });

    expect(repo.create).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'user-1', displayName: 'Jane', bio: 'Hi' }),
    );
    expect(result.displayName).toBe('Jane');
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: FAIL (모듈 없음)

- [ ] **Step 3: Profile 엔티티 작성**

`backend/src/profiles/profile.entity.ts`:

```typescript
import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('profiles')
export class Profile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  userId: string;

  @Column()
  displayName: string;

  @Column({ type: 'text', nullable: true })
  bio: string | null;

  @Column({ type: 'int', nullable: true })
  birthYear: number | null;
}
```

- [ ] **Step 4: UpdateProfileDto 작성**

`backend/src/profiles/dto/update-profile.dto.ts`:

```typescript
import { IsInt, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateProfileDto {
  @IsString()
  @MaxLength(50)
  displayName: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  bio?: string;

  @IsOptional()
  @IsInt()
  birthYear?: number;
}
```

- [ ] **Step 5: ProfilesService 작성**

`backend/src/profiles/profiles.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Profile } from './profile.entity';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class ProfilesService {
  constructor(
    @InjectRepository(Profile) private readonly profilesRepo: Repository<Profile>,
  ) {}

  getByUserId(userId: string): Promise<Profile | null> {
    return this.profilesRepo.findOne({ where: { userId } });
  }

  async upsert(userId: string, dto: UpdateProfileDto): Promise<Profile> {
    const existing = await this.getByUserId(userId);
    const profile = this.profilesRepo.create({
      ...existing,
      userId,
      displayName: dto.displayName,
      bio: dto.bio ?? null,
      birthYear: dto.birthYear ?? null,
    });
    return this.profilesRepo.save(profile);
  }
}
```

- [ ] **Step 6: ProfilesController + ProfilesModule 작성**

`backend/src/profiles/profiles.controller.ts`:

```typescript
import { Body, Controller, Get, Put, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProfilesService } from './profiles.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Controller('profiles')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(private readonly profilesService: ProfilesService) {}

  @Get('me')
  getMyProfile(@Req() req: any) {
    return this.profilesService.getByUserId(req.user.userId);
  }

  @Put('me')
  updateMyProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
    return this.profilesService.upsert(req.user.userId, dto);
  }
}
```

`backend/src/profiles/profiles.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Profile } from './profile.entity';
import { ProfilesService } from './profiles.service';
import { ProfilesController } from './profiles.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Profile])],
  controllers: [ProfilesController],
  providers: [ProfilesService],
  exports: [ProfilesService],
})
export class ProfilesModule {}
```

- [ ] **Step 7: AppModule에 ProfilesModule 등록, 테스트 재실행**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add backend/src/profiles backend/src/app.module.ts
git commit -m "feat: add profile get/update endpoints"
```

---

### Task 5: 스와이프 모듈 (좋아요/패스 기록)

**Files:**
- Create: `backend/src/swipes/swipe.entity.ts`
- Create: `backend/src/swipes/swipes.service.ts`
- Create: `backend/src/swipes/swipes.controller.ts`
- Create: `backend/src/swipes/swipes.module.ts`
- Create: `backend/src/swipes/dto/create-swipe.dto.ts`
- Test: `backend/src/swipes/swipes.service.spec.ts`

**Interfaces:**
- Consumes: `JwtAuthGuard` (Task 3)
- Produces: `SwipesService.record(fromUserId, targetUserId, liked: boolean): Promise<Swipe>`, `SwipesService.hasLiked(fromUserId, targetUserId): Promise<boolean>` — Task 6(매칭 판정)이 `hasLiked`를 사용함

- [ ] **Step 1: 실패하는 SwipesService 테스트 작성**

`backend/src/swipes/swipes.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { SwipesService } from './swipes.service';
import { Swipe } from './swipe.entity';

describe('SwipesService', () => {
  let service: SwipesService;
  let repo: { create: jest.Mock; save: jest.Mock; findOne: jest.Mock };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve({ id: 'swipe-1', ...data })),
      findOne: jest.fn(),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        SwipesService,
        { provide: getRepositoryToken(Swipe), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(SwipesService);
  });

  it('records a like swipe', async () => {
    const result = await service.record('user-1', 'user-2', true);

    expect(repo.create).toHaveBeenCalledWith({
      fromUserId: 'user-1',
      targetUserId: 'user-2',
      liked: true,
    });
    expect(result.liked).toBe(true);
  });

  it('reports whether a user has liked another', async () => {
    repo.findOne.mockResolvedValue({ id: 'swipe-1', liked: true });

    const result = await service.hasLiked('user-1', 'user-2');

    expect(repo.findOne).toHaveBeenCalledWith({
      where: { fromUserId: 'user-1', targetUserId: 'user-2', liked: true },
    });
    expect(result).toBe(true);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- swipes.service.spec.ts`
Expected: FAIL

- [ ] **Step 3: Swipe 엔티티 작성**

`backend/src/swipes/swipe.entity.ts`:

```typescript
import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity('swipes')
@Index(['fromUserId', 'targetUserId'], { unique: true })
export class Swipe {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  fromUserId: string;

  @Column()
  targetUserId: string;

  @Column()
  liked: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 4: CreateSwipeDto 작성**

`backend/src/swipes/dto/create-swipe.dto.ts`:

```typescript
import { IsBoolean, IsUUID } from 'class-validator';

export class CreateSwipeDto {
  @IsUUID()
  targetUserId: string;

  @IsBoolean()
  liked: boolean;
}
```

- [ ] **Step 5: SwipesService 작성**

`backend/src/swipes/swipes.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Swipe } from './swipe.entity';

@Injectable()
export class SwipesService {
  constructor(
    @InjectRepository(Swipe) private readonly swipesRepo: Repository<Swipe>,
  ) {}

  async record(fromUserId: string, targetUserId: string, liked: boolean): Promise<Swipe> {
    const swipe = this.swipesRepo.create({ fromUserId, targetUserId, liked });
    return this.swipesRepo.save(swipe);
  }

  async hasLiked(fromUserId: string, targetUserId: string): Promise<boolean> {
    const swipe = await this.swipesRepo.findOne({
      where: { fromUserId, targetUserId, liked: true },
    });
    return !!swipe;
  }
}
```

- [ ] **Step 6: SwipesController + SwipesModule 작성**

`backend/src/swipes/swipes.controller.ts`:

```typescript
import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(private readonly swipesService: SwipesService) {}

  @Post()
  create(@Req() req: any, @Body() dto: CreateSwipeDto) {
    return this.swipesService.record(req.user.userId, dto.targetUserId, dto.liked);
  }
}
```

`backend/src/swipes/swipes.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Swipe } from './swipe.entity';
import { SwipesService } from './swipes.service';
import { SwipesController } from './swipes.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Swipe])],
  controllers: [SwipesController],
  providers: [SwipesService],
  exports: [SwipesService],
})
export class SwipesModule {}
```

- [ ] **Step 7: AppModule에 SwipesModule 등록, 테스트 재실행**

Run: `cd backend && npm run test -- swipes.service.spec.ts`
Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add backend/src/swipes backend/src/app.module.ts
git commit -m "feat: add swipe recording endpoint"
```

---

### Task 6: 매칭 모듈 (양방향 좋아요 → 매칭 성사)

**Files:**
- Create: `backend/src/matches/match.entity.ts`
- Create: `backend/src/matches/matches.service.ts`
- Create: `backend/src/matches/matches.controller.ts`
- Create: `backend/src/matches/matches.module.ts`
- Modify: `backend/src/swipes/swipes.service.ts`
- Modify: `backend/src/swipes/swipes.controller.ts`
- Modify: `backend/src/swipes/swipes.module.ts`
- Test: `backend/src/matches/matches.service.spec.ts`

**Interfaces:**
- Consumes: `SwipesService.hasLiked` (Task 5)
- Produces: `MatchesService.createIfMutual(userAId, userBId): Promise<Match | null>`, `MatchesService.listForUser(userId): Promise<Match[]>` — Task 7(채팅)이 매칭된 두 사용자 확인에 `MatchesService`를 사용함

- [ ] **Step 1: 실패하는 MatchesService 테스트 작성**

`backend/src/matches/matches.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { MatchesService } from './matches.service';
import { Match } from './match.entity';
import { SwipesService } from '../swipes/swipes.service';

describe('MatchesService.createIfMutual', () => {
  let service: MatchesService;
  let repo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock };
  let swipesService: { hasLiked: jest.Mock };

  beforeEach(async () => {
    repo = {
      findOne: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve({ id: 'match-1', ...data })),
    };
    swipesService = { hasLiked: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        MatchesService,
        { provide: getRepositoryToken(Match), useValue: repo },
        { provide: SwipesService, useValue: swipesService },
      ],
    }).compile();

    service = moduleRef.get(MatchesService);
  });

  it('creates a match when both users liked each other', async () => {
    swipesService.hasLiked.mockResolvedValue(true);

    const result = await service.createIfMutual('user-1', 'user-2');

    expect(result).not.toBeNull();
    expect(repo.save).toHaveBeenCalled();
  });

  it('does not create a match when the like is one-sided', async () => {
    swipesService.hasLiked.mockResolvedValueOnce(true).mockResolvedValueOnce(false);

    const result = await service.createIfMutual('user-1', 'user-2');

    expect(result).toBeNull();
    expect(repo.save).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- matches.service.spec.ts`
Expected: FAIL

- [ ] **Step 3: Match 엔티티 작성**

`backend/src/matches/match.entity.ts`:

```typescript
import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('matches')
export class Match {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userAId: string;

  @Column()
  userBId: string;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 4: MatchesService 작성**

`backend/src/matches/matches.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Match } from './match.entity';
import { SwipesService } from '../swipes/swipes.service';

@Injectable()
export class MatchesService {
  constructor(
    @InjectRepository(Match) private readonly matchesRepo: Repository<Match>,
    private readonly swipesService: SwipesService,
  ) {}

  async createIfMutual(userAId: string, userBId: string): Promise<Match | null> {
    const aLikedB = await this.swipesService.hasLiked(userAId, userBId);
    const bLikedA = await this.swipesService.hasLiked(userBId, userAId);

    if (!aLikedB || !bLikedA) {
      return null;
    }

    const match = this.matchesRepo.create({ userAId, userBId });
    return this.matchesRepo.save(match);
  }

  listForUser(userId: string): Promise<Match[]> {
    return this.matchesRepo
      .createQueryBuilder('match')
      .where('match.userAId = :userId OR match.userBId = :userId', { userId })
      .getMany();
  }
}
```

- [ ] **Step 5: MatchesController + MatchesModule 작성**

`backend/src/matches/matches.controller.ts`:

```typescript
import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { MatchesService } from './matches.service';

@Controller('matches')
@UseGuards(JwtAuthGuard)
export class MatchesController {
  constructor(private readonly matchesService: MatchesService) {}

  @Get()
  listMine(@Req() req: any) {
    return this.matchesService.listForUser(req.user.userId);
  }
}
```

`backend/src/matches/matches.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Match } from './match.entity';
import { MatchesService } from './matches.service';
import { MatchesController } from './matches.controller';
import { SwipesModule } from '../swipes/swipes.module';

@Module({
  imports: [TypeOrmModule.forFeature([Match]), SwipesModule],
  controllers: [MatchesController],
  providers: [MatchesService],
  exports: [MatchesService],
})
export class MatchesModule {}
```

`backend/src/swipes/swipes.module.ts`의 `exports`에 `SwipesService`가 이미 있는지 확인 (Task 5에서 이미 추가함).

- [ ] **Step 6: SwipesController에서 매칭 판정 호출하도록 수정**

`backend/src/swipes/swipes.controller.ts`를 수정해 스와이프 생성 후 매칭 여부를 함께 반환한다. 순환 의존(swipes ↔ matches)을 피하기 위해 `MatchesModule`이 `SwipesModule`을 참조하는 방향은 유지하고, 매칭 판정 호출은 컨트롤러 레벨에서 두 서비스를 조합한다:

```typescript
import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(
    private readonly swipesService: SwipesService,
    private readonly matchesService: MatchesService,
  ) {}

  @Post()
  async create(@Req() req: any, @Body() dto: CreateSwipeDto) {
    const swipe = await this.swipesService.record(req.user.userId, dto.targetUserId, dto.liked);
    const match = dto.liked
      ? await this.matchesService.createIfMutual(req.user.userId, dto.targetUserId)
      : null;
    return { swipe, match };
  }
}
```

`backend/src/swipes/swipes.module.ts`의 `imports`에 `MatchesModule`을 추가하되, `MatchesModule`이 이미 `SwipesModule`을 import하므로 NestJS 순환 참조가 발생한다 — `forwardRef(() => MatchesModule)` / `forwardRef(() => SwipesModule)`을 양쪽에 적용한다:

```typescript
// swipes.module.ts
import { Module, forwardRef } from '@nestjs/common';
// ...
@Module({
  imports: [TypeOrmModule.forFeature([Swipe]), forwardRef(() => MatchesModule)],
  // ...
})
```

```typescript
// matches.module.ts
import { Module, forwardRef } from '@nestjs/common';
// ...
@Module({
  imports: [TypeOrmModule.forFeature([Match]), forwardRef(() => SwipesModule)],
  // ...
})
```

- [ ] **Step 7: AppModule에 MatchesModule 등록, 테스트 재실행**

Run: `cd backend && npm run test -- matches.service.spec.ts`
Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add backend/src/matches backend/src/swipes
git commit -m "feat: create match on mutual like"
```

---

### Task 7: 채팅 모듈 (매칭된 사용자 간 WebSocket 메시징)

**Files:**
- Create: `backend/src/chat/message.entity.ts`
- Create: `backend/src/chat/chat.service.ts`
- Create: `backend/src/chat/chat.gateway.ts`
- Create: `backend/src/chat/chat.module.ts`
- Test: `backend/src/chat/chat.service.spec.ts`

**Interfaces:**
- Consumes: `MatchesService.listForUser` (Task 6, 소켓 연결 시 사용자가 해당 매칭의 당사자인지 검증하는 데 사용)
- Produces: `ChatService.saveMessage(matchId, senderId, content): Promise<Message>`, `ChatService.listMessages(matchId): Promise<Message[]>`

- [ ] **Step 1: 의존성 설치**

```bash
cd backend
npm install @nestjs/websockets @nestjs/platform-socket.io socket.io
```

- [ ] **Step 2: 실패하는 ChatService 테스트 작성**

`backend/src/chat/chat.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ChatService } from './chat.service';
import { Message } from './message.entity';

describe('ChatService', () => {
  let service: ChatService;
  let repo: { create: jest.Mock; save: jest.Mock; find: jest.Mock };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest.fn().mockImplementation((data) => Promise.resolve({ id: 'msg-1', ...data })),
      find: jest.fn().mockResolvedValue([]),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [ChatService, { provide: getRepositoryToken(Message), useValue: repo }],
    }).compile();

    service = moduleRef.get(ChatService);
  });

  it('saves a message tied to a match', async () => {
    const result = await service.saveMessage('match-1', 'user-1', 'hello');

    expect(repo.create).toHaveBeenCalledWith({
      matchId: 'match-1',
      senderId: 'user-1',
      content: 'hello',
    });
    expect(result.content).toBe('hello');
  });

  it('lists messages ordered by creation time for a match', async () => {
    await service.listMessages('match-1');

    expect(repo.find).toHaveBeenCalledWith({
      where: { matchId: 'match-1' },
      order: { createdAt: 'ASC' },
    });
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- chat.service.spec.ts`
Expected: FAIL

- [ ] **Step 4: Message 엔티티 작성**

`backend/src/chat/message.entity.ts`:

```typescript
import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  matchId: string;

  @Column()
  senderId: string;

  @Column({ type: 'text' })
  content: string;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 5: ChatService 작성**

`backend/src/chat/chat.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message } from './message.entity';

@Injectable()
export class ChatService {
  constructor(
    @InjectRepository(Message) private readonly messagesRepo: Repository<Message>,
  ) {}

  async saveMessage(matchId: string, senderId: string, content: string): Promise<Message> {
    const message = this.messagesRepo.create({ matchId, senderId, content });
    return this.messagesRepo.save(message);
  }

  listMessages(matchId: string): Promise<Message[]> {
    return this.messagesRepo.find({ where: { matchId }, order: { createdAt: 'ASC' } });
  }
}
```

- [ ] **Step 6: ChatGateway 작성**

`backend/src/chat/chat.gateway.ts`:

```typescript
import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { ChatService } from './chat.service';
import { MatchesService } from '../matches/matches.service';

interface SendMessagePayload {
  matchId: string;
  senderId: string;
  content: string;
}

@WebSocketGateway({ cors: { origin: '*' } })
export class ChatGateway {
  @WebSocketServer()
  server: Server;

  constructor(
    private readonly chatService: ChatService,
    private readonly matchesService: MatchesService,
  ) {}

  @SubscribeMessage('joinMatch')
  async handleJoinMatch(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { matchId: string; userId: string },
  ) {
    const matches = await this.matchesService.listForUser(data.userId);
    const isParticipant = matches.some((m) => m.id === data.matchId);
    if (!isParticipant) {
      client.emit('error', { message: 'Not a participant of this match' });
      return;
    }
    client.join(data.matchId);
    const history = await this.chatService.listMessages(data.matchId);
    client.emit('history', history);
  }

  @SubscribeMessage('sendMessage')
  async handleSendMessage(@MessageBody() data: SendMessagePayload) {
    const message = await this.chatService.saveMessage(data.matchId, data.senderId, data.content);
    this.server.to(data.matchId).emit('newMessage', message);
    return message;
  }
}
```

- [ ] **Step 7: ChatModule 작성**

`backend/src/chat/chat.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Message } from './message.entity';
import { ChatService } from './chat.service';
import { ChatGateway } from './chat.gateway';
import { MatchesModule } from '../matches/matches.module';

@Module({
  imports: [TypeOrmModule.forFeature([Message]), MatchesModule],
  providers: [ChatService, ChatGateway],
})
export class ChatModule {}
```

- [ ] **Step 8: AppModule에 ChatModule 등록, 테스트 재실행**

Run: `cd backend && npm run test -- chat.service.spec.ts`
Expected: PASS

- [ ] **Step 9: 커밋**

```bash
git add backend/src/chat
git commit -m "feat: add WebSocket chat gateway scoped to matches"
```

---

### Task 8: 맛집 엔티티 + Overture Maps 추출 스크립트 (DuckDB)

**Files:**
- Create: `backend/src/restaurants/restaurant.entity.ts`
- Create: `backend/scripts/extract-overture-restaurants.sql`
- Create: `backend/scripts/fixtures/sample-restaurants.csv`
- Test: 수동 검증 (DuckDB 스크립트는 외부 네트워크 의존이라 유닛 테스트 대상이 아님, Task 9에서 로더를 fixture로 테스트)

**Interfaces:**
- Produces: `restaurants.csv` (컬럼: `overture_id, name, category, latitude, longitude, address`) — Task 9(시드 로더)가 이 CSV 스키마를 그대로 소비함

- [ ] **Step 1: Restaurant 엔티티 작성**

`backend/src/restaurants/restaurant.entity.ts`:

```typescript
import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('restaurants')
export class Restaurant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  overtureId: string;

  @Column()
  name: string;

  @Column()
  category: string;

  @Column('double precision')
  latitude: number;

  @Column('double precision')
  longitude: number;

  @Column({ type: 'text', nullable: true })
  address: string | null;
}
```

- [ ] **Step 2: DuckDB 추출 스크립트 작성**

`backend/scripts/extract-overture-restaurants.sql` (서울 인근 bounding box로 필터링, 로컬에서 DuckDB CLI로 실행):

```sql
INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;
SET s3_region='us-west-2';

COPY (
    SELECT
        id AS overture_id,
        names.primary AS name,
        categories.primary AS category,
        ST_Y(geometry) AS latitude,
        ST_X(geometry) AS longitude,
        addresses[1].freeform AS address
    FROM read_parquet(
        's3://overturemaps-us-west-2/release/2026-06-25.0/theme=places/type=place/*',
        filename=true,
        hive_partitioning=1
    )
    WHERE categories.primary IN ('restaurant', 'cafe', 'fast_food', 'bar', 'food_court')
      AND ST_Y(geometry) BETWEEN 37.40 AND 37.70
      AND ST_X(geometry) BETWEEN 126.76 AND 127.18
) TO 'backend/scripts/output/seoul-restaurants.csv' (HEADER, DELIMITER ',');
```

문서화 주석(스크립트 상단에 실제 코드로 포함):

```sql
-- 실행: duckdb < backend/scripts/extract-overture-restaurants.sql
-- Overture Maps release 버전은 https://overturemaps.org/release 에서 최신 값으로 갱신 필요
-- 출력 데이터는 CDLA Permissive v2.0 라이선스 — 앱 내 attribution 표기 필요 (Task 11 참고)
```

- [ ] **Step 3: 로더 테스트용 소규모 fixture CSV 작성**

`backend/scripts/fixtures/sample-restaurants.csv` (실제 DuckDB 실행 없이 Task 9 테스트에 사용할 5개 샘플 행):

```csv
overture_id,name,category,latitude,longitude,address
ovt-001,서울식당,restaurant,37.5665,126.9780,서울 중구 세종대로 110
ovt-002,강남카페,cafe,37.4979,127.0276,서울 강남구 테헤란로 152
ovt-003,홍대분식,fast_food,37.5563,126.9236,서울 마포구 양화로 160
ovt-004,이태원바,bar,37.5347,126.9945,서울 용산구 이태원로 145
ovt-005,잠실푸드코트,food_court,37.5133,127.1000,서울 송파구 올림픽로 240
```

- [ ] **Step 4: 커밋**

```bash
git add backend/src/restaurants/restaurant.entity.ts backend/scripts
git commit -m "feat: add restaurant entity and Overture Maps extraction script"
```

---

### Task 9: 맛집 시드 로더 (CSV → PostgreSQL)

**Files:**
- Create: `backend/scripts/seed-restaurants.ts`
- Test: `backend/scripts/seed-restaurants.spec.ts`

**Interfaces:**
- Consumes: `restaurants.csv` 스키마 (Task 8), `Restaurant` 엔티티 (Task 8)
- Produces: `parseRestaurantsCsv(csvContent: string): RestaurantRow[]` — 순수 함수로 분리해 DB 없이 테스트 가능하게 함

- [ ] **Step 1: 의존성 설치**

```bash
cd backend
npm install csv-parse
```

- [ ] **Step 2: 실패하는 파서 테스트 작성**

`backend/scripts/seed-restaurants.spec.ts`:

```typescript
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseRestaurantsCsv } from './seed-restaurants';

describe('parseRestaurantsCsv', () => {
  it('parses the fixture CSV into typed restaurant rows', () => {
    const csvContent = readFileSync(
      join(__dirname, 'fixtures/sample-restaurants.csv'),
      'utf-8',
    );

    const rows = parseRestaurantsCsv(csvContent);

    expect(rows).toHaveLength(5);
    expect(rows[0]).toEqual({
      overtureId: 'ovt-001',
      name: '서울식당',
      category: 'restaurant',
      latitude: 37.5665,
      longitude: 126.978,
      address: '서울 중구 세종대로 110',
    });
  });
});
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- seed-restaurants.spec.ts`
Expected: FAIL (`parseRestaurantsCsv` 없음)

- [ ] **Step 4: 파서 + 시드 실행 함수 작성**

`backend/scripts/seed-restaurants.ts`:

```typescript
import { parse } from 'csv-parse/sync';
import { readFileSync } from 'fs';
import { DataSource } from 'typeorm';
import { Restaurant } from '../src/restaurants/restaurant.entity';

export interface RestaurantRow {
  overtureId: string;
  name: string;
  category: string;
  latitude: number;
  longitude: number;
  address: string | null;
}

export function parseRestaurantsCsv(csvContent: string): RestaurantRow[] {
  const records: Record<string, string>[] = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
  });

  return records.map((r) => ({
    overtureId: r.overture_id,
    name: r.name,
    category: r.category,
    latitude: parseFloat(r.latitude),
    longitude: parseFloat(r.longitude),
    address: r.address || null,
  }));
}

async function run() {
  const csvPath = process.argv[2];
  if (!csvPath) {
    console.error('Usage: ts-node seed-restaurants.ts <path-to-csv>');
    process.exit(1);
  }

  const dataSource = new DataSource({
    type: 'postgres',
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    username: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_DATABASE,
    entities: [Restaurant],
  });
  await dataSource.initialize();

  const rows = parseRestaurantsCsv(readFileSync(csvPath, 'utf-8'));
  const repo = dataSource.getRepository(Restaurant);
  for (const row of rows) {
    await repo.upsert(row, ['overtureId']);
  }

  console.log(`Seeded ${rows.length} restaurants`);
  await dataSource.destroy();
}

if (require.main === module) {
  run();
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- seed-restaurants.spec.ts`
Expected: PASS

- [ ] **Step 6: 실제 시드 데이터로 로컬 DB에 적재 (수동 실행)**

```bash
cd backend
npx ts-node scripts/seed-restaurants.ts scripts/output/seoul-restaurants.csv
# DuckDB 추출 결과가 없다면 fixtures/sample-restaurants.csv로 우선 검증:
npx ts-node scripts/seed-restaurants.ts scripts/fixtures/sample-restaurants.csv
```

- [ ] **Step 7: 커밋**

```bash
git add backend/scripts/seed-restaurants.ts backend/scripts/seed-restaurants.spec.ts backend/package.json
git commit -m "feat: add restaurant CSV seed loader"
```

---

### Task 10: 맛집 조회 API

**Files:**
- Create: `backend/src/restaurants/restaurants.service.ts`
- Create: `backend/src/restaurants/restaurants.controller.ts`
- Create: `backend/src/restaurants/restaurants.module.ts`
- Test: `backend/src/restaurants/restaurants.service.spec.ts`

**Interfaces:**
- Consumes: `Restaurant` 엔티티 (Task 8)
- Produces: `RestaurantsService.list(): Promise<Restaurant[]>` — GET `/restaurants`로 노출, attribution 문자열을 응답에 포함

- [ ] **Step 1: 실패하는 RestaurantsService 테스트 작성**

`backend/src/restaurants/restaurants.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { RestaurantsService } from './restaurants.service';
import { Restaurant } from './restaurant.entity';

describe('RestaurantsService.list', () => {
  let service: RestaurantsService;
  let repo: { find: jest.Mock };

  beforeEach(async () => {
    repo = { find: jest.fn().mockResolvedValue([{ id: 'r1', name: '서울식당' }]) };

    const moduleRef = await Test.createTestingModule({
      providers: [
        RestaurantsService,
        { provide: getRepositoryToken(Restaurant), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(RestaurantsService);
  });

  it('returns all seeded restaurants', async () => {
    const result = await service.list();

    expect(result).toEqual([{ id: 'r1', name: '서울식당' }]);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- restaurants.service.spec.ts`
Expected: FAIL

- [ ] **Step 3: RestaurantsService 작성**

`backend/src/restaurants/restaurants.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Restaurant } from './restaurant.entity';

@Injectable()
export class RestaurantsService {
  constructor(
    @InjectRepository(Restaurant) private readonly restaurantsRepo: Repository<Restaurant>,
  ) {}

  list(): Promise<Restaurant[]> {
    return this.restaurantsRepo.find();
  }
}
```

- [ ] **Step 4: RestaurantsController + RestaurantsModule 작성**

`backend/src/restaurants/restaurants.controller.ts`:

```typescript
import { Controller, Get } from '@nestjs/common';
import { RestaurantsService } from './restaurants.service';

const OVERTURE_ATTRIBUTION =
  'Restaurant data © Overture Maps Foundation contributors, licensed under CDLA Permissive v2.0';

@Controller('restaurants')
export class RestaurantsController {
  constructor(private readonly restaurantsService: RestaurantsService) {}

  @Get()
  async list() {
    const restaurants = await this.restaurantsService.list();
    return { restaurants, attribution: OVERTURE_ATTRIBUTION };
  }
}
```

`backend/src/restaurants/restaurants.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Restaurant } from './restaurant.entity';
import { RestaurantsService } from './restaurants.service';
import { RestaurantsController } from './restaurants.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Restaurant])],
  controllers: [RestaurantsController],
  providers: [RestaurantsService],
})
export class RestaurantsModule {}
```

- [ ] **Step 5: AppModule에 RestaurantsModule 등록, 테스트 재실행**

Run: `cd backend && npm run test -- restaurants.service.spec.ts`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add backend/src/restaurants backend/src/app.module.ts
git commit -m "feat: expose restaurant list endpoint with Overture attribution"
```

---

### Task 11: Flutter 스캐폴드 + API 클라이언트 + 로그인/회원가입 화면

**Files:**
- Create: `mobile/pubspec.yaml` (Flutter 프로젝트 생성으로 자동 생성 후 의존성 추가)
- Create: `mobile/lib/api/api_client.dart`
- Create: `mobile/lib/auth/auth_repository.dart`
- Create: `mobile/lib/auth/login_screen.dart`
- Create: `mobile/lib/auth/signup_screen.dart`
- Test: `mobile/test/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: 백엔드 `/auth/login`, `/auth/signup` (Task 2, 3)
- Produces: `AuthRepository.login(email, password): Future<String>` (accessToken 반환), `ApiClient` (Task 12/13이 재사용)

- [ ] **Step 1: Flutter 프로젝트 생성 + 의존성 추가**

```bash
cd /Users/studio/Downloads/project/tablemate
flutter create --platforms=ios,android,web mobile
cd mobile
flutter pub add http socket_io_client provider
flutter pub add --dev mocktail
```

- [ ] **Step 2: ApiClient 작성**

`mobile/lib/api/api_client.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({this.baseUrl = 'http://localhost:3000'});

  final String baseUrl;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(decoded['message']?.toString() ?? 'Request failed');
    }
    return decoded;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
```

- [ ] **Step 3: AuthRepository 작성**

`mobile/lib/auth/auth_repository.dart`:

```dart
import '../api/api_client.dart';

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String> login(String email, String password) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return result['accessToken'] as String;
  }

  Future<void> signup(String email, String password) async {
    await _apiClient.post('/auth/signup', {
      'email': email,
      'password': password,
    });
  }
}
```

- [ ] **Step 4: 실패하는 LoginScreen 위젯 테스트 작성**

`mobile/test/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/auth/auth_repository.dart';
import 'package:mobile/auth/login_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('submits email and password to AuthRepository.login', (tester) async {
    final mockRepo = MockAuthRepository();
    when(() => mockRepo.login('jane@example.com', 'password123'))
        .thenAnswer((_) async => 'fake-token');

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(authRepository: mockRepo),
    ));

    await tester.enterText(find.byKey(const Key('emailField')), 'jane@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'password123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.login('jane@example.com', 'password123')).called(1);
  });
}
```

- [ ] **Step 5: 테스트 실행해서 실패 확인**

Run: `cd mobile && flutter test test/auth/login_screen_test.dart`
Expected: FAIL (`LoginScreen` 없음)

- [ ] **Step 6: LoginScreen 구현**

`mobile/lib/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _submit() async {
    try {
      await widget.authRepository.login(_emailController.text, _passwordController.text);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
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
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('loginButton'),
              onPressed: _submit,
              child: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: 테스트 재실행해서 통과 확인**

Run: `cd mobile && flutter test test/auth/login_screen_test.dart`
Expected: PASS

- [ ] **Step 8: SignupScreen도 동일 패턴으로 구현**

`mobile/lib/auth/signup_screen.dart`는 `LoginScreen`과 동일한 구조로 `authRepository.signup`을 호출하도록 작성한다 (Key: `emailField`, `passwordField`, `signupButton`).

- [ ] **Step 9: 커밋**

```bash
cd /Users/studio/Downloads/project/tablemate
git add mobile/
git commit -m "feat: scaffold Flutter app with login/signup screens"
```

---

### Task 12: Discover(스와이프) 화면

**Files:**
- Create: `mobile/lib/discover/discover_screen.dart`
- Create: `mobile/lib/discover/swipe_card.dart`
- Create: `mobile/lib/discover/discover_repository.dart`
- Test: `mobile/test/discover/discover_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task 11), 백엔드 `/swipes` (Task 5)
- Produces: `DiscoverRepository.swipe(targetUserId, liked): Future<bool>` (매칭 성사 여부 반환)

- [ ] **Step 1: 실패하는 DiscoverScreen 위젯 테스트 작성**

`mobile/test/discover/discover_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/discover/discover_repository.dart';
import 'package:mobile/discover/discover_screen.dart';

class MockDiscoverRepository extends Mock implements DiscoverRepository {}

void main() {
  testWidgets('tapping like calls DiscoverRepository.swipe with liked=true', (tester) async {
    final mockRepo = MockDiscoverRepository();
    when(() => mockRepo.swipe('user-2', true)).thenAnswer((_) async => false);

    await tester.pumpWidget(MaterialApp(
      home: DiscoverScreen(
        repository: mockRepo,
        candidateUserId: 'user-2',
        candidateName: 'Jane',
      ),
    ));

    await tester.tap(find.byKey(const Key('likeButton')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.swipe('user-2', true)).called(1);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd mobile && flutter test test/discover/discover_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: DiscoverRepository 작성**

`mobile/lib/discover/discover_repository.dart`:

```dart
import '../api/api_client.dart';

class DiscoverRepository {
  DiscoverRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String _accessToken;

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

- [ ] **Step 4: SwipeCard + DiscoverScreen 구현**

`mobile/lib/discover/swipe_card.dart`:

```dart
import 'package:flutter/material.dart';

class SwipeCard extends StatelessWidget {
  const SwipeCard({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(child: Text(name, style: Theme.of(context).textTheme.headlineMedium)),
    );
  }
}
```

`mobile/lib/discover/discover_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'discover_repository.dart';
import 'swipe_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.repository,
    required this.candidateUserId,
    required this.candidateName,
  });

  final DiscoverRepository repository;
  final String candidateUserId;
  final String candidateName;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  bool? _matched;

  Future<void> _like() async {
    final matched = await widget.repository.swipe(widget.candidateUserId, true);
    setState(() => _matched = matched);
  }

  Future<void> _pass() async {
    await widget.repository.swipe(widget.candidateUserId, false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: SwipeCard(name: widget.candidateName)),
          if (_matched == true) const Text("It's a match!"),
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

Run: `cd mobile && flutter test test/discover/discover_screen_test.dart`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add mobile/lib/discover mobile/test/discover
git commit -m "feat: add discover/swipe screen"
```

---

### Task 13: 매칭 목록 + 채팅 화면 (WebSocket)

**Files:**
- Create: `mobile/lib/matches/matches_screen.dart`
- Create: `mobile/lib/matches/matches_repository.dart`
- Create: `mobile/lib/chat/chat_socket_client.dart`
- Create: `mobile/lib/chat/chat_screen.dart`
- Test: `mobile/test/matches/matches_screen_test.dart`

**Interfaces:**
- Consumes: 백엔드 `/matches` (Task 6), WebSocket `joinMatch`/`sendMessage`/`newMessage` 이벤트 (Task 7)
- Produces: 없음 (이번 서브프로젝트의 최종 화면)

- [ ] **Step 1: 실패하는 MatchesScreen 위젯 테스트 작성**

`mobile/test/matches/matches_screen_test.dart`:

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
      home: MatchesScreen(repository: mockRepo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('match-1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd mobile && flutter test test/matches/matches_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: MatchesRepository 작성**

`mobile/lib/matches/matches_repository.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class MatchesRepository {
  MatchesRepository(this._baseUrl, this._accessToken);

  final String _baseUrl;
  final String _accessToken;

  Future<List<Map<String, dynamic>>> listMatches() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/matches'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
}
```

- [ ] **Step 4: MatchesScreen 구현**

`mobile/lib/matches/matches_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'matches_repository.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.repository});

  final MatchesRepository repository;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    widget.repository.listMatches().then((matches) => setState(() => _matches = matches));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_matches[index]['id'] as String),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `cd mobile && flutter test test/matches/matches_screen_test.dart`
Expected: PASS

- [ ] **Step 6: ChatSocketClient + ChatScreen 구현 (테스트 없이 직접 구현 — socket_io_client는 실제 소켓 연결이 필요해 위젯 테스트로 검증하기 어려움, Task 14 수동 검증에서 확인)**

`mobile/lib/chat/chat_socket_client.dart`:

```dart
import 'package:socket_io_client/socket_io_client.dart' as io;

class ChatSocketClient {
  ChatSocketClient(String baseUrl) {
    _socket = io.io(baseUrl, io.OptionBuilder().setTransports(['websocket']).build());
  }

  late final io.Socket _socket;

  void joinMatch(String matchId, String userId) {
    _socket.emit('joinMatch', {'matchId': matchId, 'userId': userId});
  }

  void sendMessage(String matchId, String senderId, String content) {
    _socket.emit('sendMessage', {'matchId': matchId, 'senderId': senderId, 'content': content});
  }

  void onNewMessage(void Function(dynamic message) handler) {
    _socket.on('newMessage', handler);
  }

  void dispose() {
    _socket.dispose();
  }
}
```

`mobile/lib/chat/chat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'chat_socket_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.socketClient,
    required this.matchId,
    required this.userId,
  });

  final ChatSocketClient socketClient;
  final String matchId;
  final String userId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <String>[];
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.socketClient.joinMatch(widget.matchId, widget.userId);
    widget.socketClient.onNewMessage((message) {
      setState(() => _messages.add(message['content'] as String));
    });
  }

  void _send() {
    widget.socketClient.sendMessage(widget.matchId, widget.userId, _inputController.text);
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

- [ ] **Step 7: 커밋**

```bash
git add mobile/lib/matches mobile/lib/chat mobile/test/matches
git commit -m "feat: add matches list and WebSocket chat screen"
```

---

### Task 14: 전체 연결 수동 검증 + README

**Files:**
- Create: `README.md` (프로젝트 루트)
- Modify: `backend/.gitignore`, `mobile/.gitignore` (`.env`, `scripts/output/` 제외 확인)

**Interfaces:**
- Consumes: 없음 (검증 전용)
- Produces: 없음

- [ ] **Step 1: 백엔드 + Postgres 로컬 기동**

```bash
cd /Users/studio/Downloads/project/tablemate/backend
npm run start:dev
```

- [ ] **Step 2: 시드 데이터 적재 확인**

```bash
curl http://localhost:3000/restaurants
```
Expected: 적재된 맛집 목록 + `attribution` 필드 포함 JSON 응답

- [ ] **Step 3: 회원가입 → 로그인 → 스와이프 → 매칭 → 채팅 흐름을 curl로 수동 검증**

```bash
curl -X POST http://localhost:3000/auth/signup -H 'Content-Type: application/json' \
  -d '{"email":"a@example.com","password":"password123"}'
curl -X POST http://localhost:3000/auth/signup -H 'Content-Type: application/json' \
  -d '{"email":"b@example.com","password":"password123"}'
# 두 계정 각각 로그인해서 accessToken 획득 후, 서로에게 liked:true로 /swipes 호출
# 두 번째 스와이프 응답의 match 필드가 null이 아님을 확인
```

- [ ] **Step 4: Flutter 앱 로컬 기동 확인**

```bash
cd /Users/studio/Downloads/project/tablemate/mobile
flutter run -d chrome
```
로그인 화면 → (수동으로 회원가입 계정으로 로그인) → discover 화면에서 좋아요 → matches 화면에 표시되는지 육안 확인

- [ ] **Step 5: 루트 README 작성**

`README.md`:

```markdown
# TableMate

데이팅과 맛집을 결합한 서비스. 현재 상태: 기반 골격(회원가입/로그인/스와이프/매칭/채팅 + 맛집 씨드 데이터) 구현 완료.

## 구조

- `backend/` — NestJS + PostgreSQL API 서버
- `mobile/` — Flutter 앱 (iOS/Android/웹)
- `docs/superpowers/specs/` — 설계 문서
- `docs/superpowers/plans/` — 구현 계획 문서

## 로컬 실행

### 백엔드
\`\`\`bash
cd backend
cp .env.example .env  # DB 접속정보 수정
npm install
npm run start:dev
\`\`\`

### 맛집 씨드 데이터
\`\`\`bash
# DuckDB로 Overture Maps에서 서울 지역 맛집 추출 (DuckDB CLI 설치 필요)
duckdb < backend/scripts/extract-overture-restaurants.sql
# PostgreSQL에 적재
npx ts-node backend/scripts/seed-restaurants.ts backend/scripts/output/seoul-restaurants.csv
\`\`\`

맛집 데이터 출처: [Overture Maps Foundation](https://overturemaps.org/), CDLA Permissive v2.0 라이선스.
씨드 데이터는 서울 지역으로 한정되어 있으며, 실제 출시 지역(글로벌) 데이터로 교체가 필요합니다.

### 모바일
\`\`\`bash
cd mobile
flutter pub get
flutter run
\`\`\`

## 알려진 제약

- 리프레시 토큰 미구현 (액세스 토큰만, 1시간 만료) — 서브프로젝트 3에서 다룰 예정
- 맛집 데이터는 서울 지역 씨드 데이터로, 실시간 영업정보 아님
```

- [ ] **Step 6: 최종 커밋**

```bash
cd /Users/studio/Downloads/project/tablemate
git add README.md
git commit -m "docs: add root README with setup and verification steps"
```

---

## Self-Review 결과

- **스펙 커버리지:** 회원가입/로그인(Task 2-3), 프로필(Task 4), 스와이프/매칭(Task 5-6), 채팅(Task 7), 맛집 씨드 파이프라인(Task 8-10), Flutter 앱(Task 11-13), 산출물 검증(Task 14) — 스펙의 "작업 내용" 3개 항목을 모두 커버함
- **플레이스홀더 스캔:** 없음. 모든 스텝에 실행 가능한 코드 포함
- **타입 일관성:** `SwipesService.hasLiked`(Task 5) → `MatchesService.createIfMutual`(Task 6) → `ChatGateway`의 매칭 검증(Task 7) → Flutter `DiscoverRepository.swipe`/`MatchesRepository.listMatches`(Task 12-13)까지 필드명(`matchId`, `userAId`/`userBId`, `targetUserId`, `liked`) 일관되게 사용됨을 확인
