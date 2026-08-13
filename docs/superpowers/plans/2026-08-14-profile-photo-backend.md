# 프로필 사진 (백엔드) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 프로필 사진을 오브젝트 스토리지(S3 호환)에 올리고 서빙하는 백엔드를 구현하고, 프로필·후보·매칭 응답에 `photoUrl`을 노출한다.

**Architecture:** 저장은 `PhotoStorage` 추상화(+ `S3PhotoStorage`) 뒤에 두고 `ProfilePhotosService`가 검증·키생성·저장·교체를 오케스트레이션한다. 업로드는 `POST /profiles/me/photo`(인증, multipart), 서빙은 `GET /profiles/photos/:key`(공개 프록시, `StreamableFile`). 테스트는 `PhotoStorage`/`S3Client`를 목킹해 실제 S3 없이 검증한다.

**Tech Stack:** NestJS 10.x, TypeORM, `@aws-sdk/client-s3`(신규), `@nestjs/platform-express`+`multer`(기존, `FileInterceptor`), Node 내장 `crypto`.

**Spec:** `docs/superpowers/specs/2026-08-14-profile-photo-backend-design.md`

## Global Constraints

- 저장소 접근은 반드시 `PhotoStorage` 추상 클래스(DI 토큰) 뒤로 숨긴다. 서비스/컨트롤러는 `S3Client`를 직접 참조하지 않는다.
- 키 생성은 Node 내장 `crypto.randomUUID()` 사용. 키 형식은 `<uuid>.<ext>`(ext ∈ {jpg, png}).
- 파일 제한: `image/jpeg`·`image/png`만, 최대 5MB. 위반 시 `BadRequestException`.
- 응답에 내부 `id`·`photoKey`를 노출하지 않는다. 사진은 `photoUrl`(`/profiles/photos/<key>`)로만 노출한다.
- `photoUrlFor(null)`은 `null`을 반환한다.
- 각 로직 단위는 TDD. 이 서브프로젝트의 모든 신규 스펙은 이 개발 샌드박스에서 실행된다(profiles/swipes/matches 계열은 bcrypt를 import하지 않음). 배선은 `npm run build`로 확인.
- 백엔드 명령은 `cd backend`에서 실행한다.

---

## 파일 구조 개요

```
backend/
  package.json                              (수정: @aws-sdk/client-s3, @types/multer)
  .env.example                              (수정: S3_* 변수)
  src/
    profiles/
      profile.entity.ts                     (수정: photoKey 컬럼)
      profiles.service.ts                   (수정: setPhotoKey, photoUrlFor)
      profiles.service.spec.ts              (수정)
      photo-storage.ts                      (신규: 추상 PhotoStorage)
      s3-photo-storage.ts                   (신규)
      s3-photo-storage.spec.ts              (신규)
      profile-photos.service.ts             (신규)
      profile-photos.service.spec.ts        (신규)
      profiles.controller.ts                (수정: upload + 응답 셰이핑)
      profiles.controller.spec.ts           (신규)
      photos.controller.ts                  (신규: 공개 서빙)
      photos.controller.spec.ts             (신규)
      profiles.module.ts                    (수정: 프로바이더/컨트롤러 배선)
    swipes/
      swipes.controller.ts                  (수정: 후보 photoUrl)
      swipes.controller.spec.ts             (수정)
    matches/
      matches.service.ts                    (수정: counterpartPhotoUrl)
      matches.service.spec.ts               (수정)
  README.md                                 (수정)
```

---

### Task 1: `Profile.photoKey` + `ProfilesService.setPhotoKey`/`photoUrlFor`

**Files:**
- Modify: `backend/src/profiles/profile.entity.ts`
- Modify: `backend/src/profiles/profiles.service.ts`
- Modify: `backend/src/profiles/profiles.service.spec.ts`

**Interfaces:**
- Produces: `ProfilesService.setPhotoKey(userId: string, photoKey: string): Promise<Profile>`, `ProfilesService.photoUrlFor(photoKey: string | null): string | null`. Task 3/6/7이 소비. `Profile.photoKey: string | null`.

- [ ] **Step 1: 엔티티에 컬럼 추가**

`backend/src/profiles/profile.entity.ts`의 `birthYear` 컬럼 아래에 추가:

```typescript
  @Column({ type: 'text', nullable: true })
  photoKey: string | null;
```

- [ ] **Step 2: 실패하는 테스트 작성 (`profiles.service.spec.ts` 맨 끝에 새 describe 추가)**

```typescript
describe('ProfilesService.photos', () => {
  let service: ProfilesService;
  let repo: { update: jest.Mock; findOne: jest.Mock };

  beforeEach(async () => {
    repo = {
      update: jest.fn().mockResolvedValue(undefined),
      findOne: jest.fn(),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ProfilesService,
        { provide: getRepositoryToken(Profile), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(ProfilesService);
  });

  it('photoUrlFor builds a relative url or null', () => {
    expect(service.photoUrlFor('abc.jpg')).toBe('/profiles/photos/abc.jpg');
    expect(service.photoUrlFor(null)).toBeNull();
  });

  it('setPhotoKey updates the column and returns the fresh profile', async () => {
    repo.findOne.mockResolvedValue({ userId: 'user-1', photoKey: 'k.jpg' });

    const result = await service.setPhotoKey('user-1', 'k.jpg');

    expect(repo.update).toHaveBeenCalledWith(
      { userId: 'user-1' },
      { photoKey: 'k.jpg' },
    );
    expect(result.photoKey).toBe('k.jpg');
  });

  it('setPhotoKey throws when the profile does not exist', async () => {
    repo.findOne.mockResolvedValue(null);

    await expect(service.setPhotoKey('ghost', 'k.jpg')).rejects.toThrow(
      NotFoundException,
    );
  });
});
```

`profiles.service.spec.ts` 상단 import에 `NotFoundException` 추가:

```typescript
import { NotFoundException } from '@nestjs/common';
```

- [ ] **Step 3: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: FAIL (`photoUrlFor`/`setPhotoKey` 미정의)

- [ ] **Step 4: 구현**

`backend/src/profiles/profiles.service.ts` 상단 import에 `NotFoundException` 추가:

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
```

`listCandidates` 아래에 추가:

```typescript
  async setPhotoKey(userId: string, photoKey: string): Promise<Profile> {
    await this.profilesRepo.update({ userId }, { photoKey });
    const profile = await this.getByUserId(userId);
    if (!profile) {
      throw new NotFoundException('Profile not found');
    }
    return profile;
  }

  photoUrlFor(photoKey: string | null): string | null {
    return photoKey ? `/profiles/photos/${photoKey}` : null;
  }
```

- [ ] **Step 5: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- profiles.service.spec.ts`
Expected: PASS (기존 + 신규 3개)

- [ ] **Step 6: 커밋**

```bash
git add backend/src/profiles/profile.entity.ts backend/src/profiles/profiles.service.ts backend/src/profiles/profiles.service.spec.ts
git commit -m "feat: add Profile.photoKey with setPhotoKey and photoUrlFor"
```

---

### Task 2: 의존성 + `PhotoStorage` 추상 + `S3PhotoStorage`

**Files:**
- Modify: `backend/package.json` (via npm install)
- Create: `backend/src/profiles/photo-storage.ts`
- Create: `backend/src/profiles/s3-photo-storage.ts`
- Create: `backend/src/profiles/s3-photo-storage.spec.ts`

**Interfaces:**
- Produces: `abstract class PhotoStorage { put(key,body,contentType); get(key): Promise<{body: Readable; contentType: string}>; delete(key); }` (DI 토큰), `S3PhotoStorage implements PhotoStorage`. Task 3/4가 소비.

- [ ] **Step 1: 패키지 설치**

Run: `cd backend && npm install @aws-sdk/client-s3 && npm install -D @types/multer`
Expected: `package.json`/`package-lock.json` 갱신.

- [ ] **Step 2: 추상 클래스 작성**

`backend/src/profiles/photo-storage.ts`:

```typescript
import { Readable } from 'stream';

export abstract class PhotoStorage {
  abstract put(key: string, body: Buffer, contentType: string): Promise<void>;
  abstract get(key: string): Promise<{ body: Readable; contentType: string }>;
  abstract delete(key: string): Promise<void>;
}
```

- [ ] **Step 3: 실패하는 테스트 작성**

`backend/src/profiles/s3-photo-storage.spec.ts`:

```typescript
import {
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { S3PhotoStorage } from './s3-photo-storage';

function makeStorage(send: jest.Mock): S3PhotoStorage {
  const config = {
    get: (key: string) => (key === 'S3_BUCKET' ? 'my-bucket' : undefined),
  };
  return new S3PhotoStorage(config as any, { send } as any);
}

describe('S3PhotoStorage', () => {
  it('put sends a PutObjectCommand with bucket/key/body/content-type', async () => {
    const send = jest.fn().mockResolvedValue({});
    const storage = makeStorage(send);
    const body = Buffer.from('bytes');

    await storage.put('k.jpg', body, 'image/jpeg');

    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(PutObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'my-bucket',
      Key: 'k.jpg',
      Body: body,
      ContentType: 'image/jpeg',
    });
  });

  it('get returns the object body and content type', async () => {
    const fakeBody = { pipe: jest.fn() };
    const send = jest
      .fn()
      .mockResolvedValue({ Body: fakeBody, ContentType: 'image/png' });
    const storage = makeStorage(send);

    const result = await storage.get('k.png');

    expect(send.mock.calls[0][0]).toBeInstanceOf(GetObjectCommand);
    expect(result.body).toBe(fakeBody);
    expect(result.contentType).toBe('image/png');
  });

  it('delete sends a DeleteObjectCommand', async () => {
    const send = jest.fn().mockResolvedValue({});
    const storage = makeStorage(send);

    await storage.delete('k.jpg');

    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(DeleteObjectCommand);
    expect(command.input).toEqual({ Bucket: 'my-bucket', Key: 'k.jpg' });
  });
});
```

- [ ] **Step 4: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- s3-photo-storage.spec.ts`
Expected: FAIL (`Cannot find module './s3-photo-storage'`)

- [ ] **Step 5: 구현**

`backend/src/profiles/s3-photo-storage.ts`:

```typescript
import { Injectable, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { Readable } from 'stream';
import { PhotoStorage } from './photo-storage';

@Injectable()
export class S3PhotoStorage implements PhotoStorage {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(config: ConfigService, @Optional() client?: S3Client) {
    this.bucket = config.get<string>('S3_BUCKET') ?? '';
    this.client =
      client ??
      new S3Client({
        region: config.get<string>('S3_REGION') ?? 'us-east-1',
        endpoint: config.get<string>('S3_ENDPOINT'),
        forcePathStyle: config.get<string>('S3_FORCE_PATH_STYLE') === 'true',
        credentials: {
          accessKeyId: config.get<string>('S3_ACCESS_KEY_ID') ?? '',
          secretAccessKey: config.get<string>('S3_SECRET_ACCESS_KEY') ?? '',
        },
      });
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
      }),
    );
  }

  async get(key: string): Promise<{ body: Readable; contentType: string }> {
    const res = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
    );
    return {
      body: res.Body as Readable,
      contentType: res.ContentType ?? 'application/octet-stream',
    };
  }

  async delete(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }
}
```

- [ ] **Step 6: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- s3-photo-storage.spec.ts`
Expected: PASS (3/3)

- [ ] **Step 7: 커밋**

```bash
git add backend/package.json backend/package-lock.json backend/src/profiles/photo-storage.ts backend/src/profiles/s3-photo-storage.ts backend/src/profiles/s3-photo-storage.spec.ts
git commit -m "feat: add PhotoStorage abstraction with S3 implementation"
```

---

### Task 3: `ProfilePhotosService`

**Files:**
- Create: `backend/src/profiles/profile-photos.service.ts`
- Create: `backend/src/profiles/profile-photos.service.spec.ts`

**Interfaces:**
- Consumes: `PhotoStorage`(Task 2), `ProfilesService.getByUserId`/`setPhotoKey`(Task 1)
- Produces: `ProfilePhotosService.replace(userId, file: { buffer: Buffer; mimetype: string; size: number }): Promise<Profile>`, `ProfilePhotosService.get(key: string): Promise<{ body: Readable; contentType: string }>`. Task 4/5가 소비.

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/profiles/profile-photos.service.spec.ts`:

```typescript
import { BadRequestException } from '@nestjs/common';
import { ProfilePhotosService } from './profile-photos.service';

describe('ProfilePhotosService', () => {
  let storage: { put: jest.Mock; get: jest.Mock; delete: jest.Mock };
  let profilesService: { getByUserId: jest.Mock; setPhotoKey: jest.Mock };
  let service: ProfilePhotosService;

  beforeEach(() => {
    storage = {
      put: jest.fn().mockResolvedValue(undefined),
      get: jest.fn(),
      delete: jest.fn().mockResolvedValue(undefined),
    };
    profilesService = {
      getByUserId: jest.fn(),
      setPhotoKey: jest
        .fn()
        .mockImplementation((userId, photoKey) =>
          Promise.resolve({ userId, photoKey }),
        ),
    };
    service = new ProfilePhotosService(storage as any, profilesService as any);
  });

  it('stores a jpeg under a uuid key and records it on the profile', async () => {
    profilesService.getByUserId.mockResolvedValue({
      userId: 'u1',
      photoKey: null,
    });

    const result = await service.replace('u1', {
      buffer: Buffer.from('x'),
      mimetype: 'image/jpeg',
      size: 100,
    });

    const key = storage.put.mock.calls[0][0];
    expect(key).toMatch(/^[0-9a-f-]{36}\.jpg$/);
    expect(storage.put).toHaveBeenCalledWith(key, expect.any(Buffer), 'image/jpeg');
    expect(storage.delete).not.toHaveBeenCalled();
    expect(profilesService.setPhotoKey).toHaveBeenCalledWith('u1', key);
    expect(result.photoKey).toBe(key);
  });

  it('deletes the previous object when replacing an existing photo', async () => {
    profilesService.getByUserId.mockResolvedValue({
      userId: 'u1',
      photoKey: 'old.jpg',
    });

    await service.replace('u1', {
      buffer: Buffer.from('x'),
      mimetype: 'image/png',
      size: 100,
    });

    expect(storage.delete).toHaveBeenCalledWith('old.jpg');
    const key = storage.put.mock.calls[0][0];
    expect(key).toMatch(/^[0-9a-f-]{36}\.png$/);
  });

  it('rejects a non image/jpeg-png mimetype', async () => {
    await expect(
      service.replace('u1', {
        buffer: Buffer.from('x'),
        mimetype: 'image/gif',
        size: 100,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(storage.put).not.toHaveBeenCalled();
  });

  it('rejects a file larger than 5MB', async () => {
    await expect(
      service.replace('u1', {
        buffer: Buffer.from('x'),
        mimetype: 'image/jpeg',
        size: 6 * 1024 * 1024,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(storage.put).not.toHaveBeenCalled();
  });

  it('get delegates to storage', async () => {
    storage.get.mockResolvedValue({ body: 'stream', contentType: 'image/jpeg' });

    const result = await service.get('k.jpg');

    expect(storage.get).toHaveBeenCalledWith('k.jpg');
    expect(result).toEqual({ body: 'stream', contentType: 'image/jpeg' });
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- profile-photos.service.spec.ts`
Expected: FAIL (`Cannot find module './profile-photos.service'`)

- [ ] **Step 3: 구현**

`backend/src/profiles/profile-photos.service.ts`:

```typescript
import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Readable } from 'stream';
import { PhotoStorage } from './photo-storage';
import { ProfilesService } from './profiles.service';
import { Profile } from './profile.entity';

const MAX_SIZE = 5 * 1024 * 1024;
const EXT_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
};

@Injectable()
export class ProfilePhotosService {
  constructor(
    private readonly storage: PhotoStorage,
    private readonly profilesService: ProfilesService,
  ) {}

  async replace(
    userId: string,
    file: { buffer: Buffer; mimetype: string; size: number },
  ): Promise<Profile> {
    const ext = EXT_BY_MIME[file.mimetype];
    if (!ext) {
      throw new BadRequestException('Only JPEG and PNG images are allowed');
    }
    if (file.size > MAX_SIZE) {
      throw new BadRequestException('Image must be 5MB or smaller');
    }

    const key = `${randomUUID()}.${ext}`;
    await this.storage.put(key, file.buffer, file.mimetype);

    const current = await this.profilesService.getByUserId(userId);
    if (current?.photoKey) {
      try {
        await this.storage.delete(current.photoKey);
      } catch {
        // best-effort cleanup of the previous object
      }
    }

    return this.profilesService.setPhotoKey(userId, key);
  }

  get(key: string): Promise<{ body: Readable; contentType: string }> {
    return this.storage.get(key);
  }
}
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- profile-photos.service.spec.ts`
Expected: PASS (5/5)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/profiles/profile-photos.service.ts backend/src/profiles/profile-photos.service.spec.ts
git commit -m "feat: add ProfilePhotosService for upload validation and storage"
```

---

### Task 4: `ProfilesController` 업로드 + 응답 셰이핑 + 모듈 배선

**Files:**
- Modify: `backend/src/profiles/profiles.controller.ts`
- Create: `backend/src/profiles/profiles.controller.spec.ts`
- Modify: `backend/src/profiles/profiles.module.ts`

**Interfaces:**
- Consumes: `ProfilePhotosService`(Task 3), `ProfilesService.photoUrlFor`(Task 1)
- Produces: `POST /profiles/me/photo` → 셰이핑된 프로필 `{ userId, displayName, bio, birthYear, photoUrl }`. `GET /profiles/me`·`PUT /profiles/me`도 동일 셰이프.

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/profiles/profiles.controller.spec.ts`:

```typescript
import { BadRequestException } from '@nestjs/common';
import { ProfilesController } from './profiles.controller';

describe('ProfilesController', () => {
  let profilesService: {
    getByUserId: jest.Mock;
    upsert: jest.Mock;
    photoUrlFor: jest.Mock;
  };
  let profilePhotosService: { replace: jest.Mock };
  let controller: ProfilesController;

  beforeEach(() => {
    profilesService = {
      getByUserId: jest.fn(),
      upsert: jest.fn(),
      photoUrlFor: jest.fn((key: string | null) =>
        key ? `/profiles/photos/${key}` : null,
      ),
    };
    profilePhotosService = { replace: jest.fn() };
    controller = new ProfilesController(
      profilesService as any,
      profilePhotosService as any,
    );
  });

  it('getMyProfile returns a shaped profile with photoUrl', async () => {
    profilesService.getByUserId.mockResolvedValue({
      id: 'internal',
      userId: 'u1',
      displayName: 'Jane',
      bio: 'Hi',
      birthYear: 1990,
      photoKey: 'k.jpg',
    });

    const result = await controller.getMyProfile({ user: { userId: 'u1' } });

    expect(result).toEqual({
      userId: 'u1',
      displayName: 'Jane',
      bio: 'Hi',
      birthYear: 1990,
      photoUrl: '/profiles/photos/k.jpg',
    });
  });

  it('uploadPhoto delegates to the photos service and shapes the result', async () => {
    profilePhotosService.replace.mockResolvedValue({
      userId: 'u1',
      displayName: 'Jane',
      bio: null,
      birthYear: null,
      photoKey: 'new.jpg',
    });
    const file = { buffer: Buffer.from('x'), mimetype: 'image/jpeg', size: 10 };

    const result = await controller.uploadPhoto(
      { user: { userId: 'u1' } },
      file as any,
    );

    expect(profilePhotosService.replace).toHaveBeenCalledWith('u1', file);
    expect(result.photoUrl).toBe('/profiles/photos/new.jpg');
  });

  it('uploadPhoto throws when no file is provided', async () => {
    await expect(
      controller.uploadPhoto({ user: { userId: 'u1' } }, undefined as any),
    ).rejects.toThrow(BadRequestException);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- profiles.controller.spec.ts`
Expected: FAIL (`ProfilesController` 생성자 인자 수 불일치 / `uploadPhoto` 미정의)

- [ ] **Step 3: `ProfilesController` 교체**

`backend/src/profiles/profiles.controller.ts` 전체:

```typescript
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Put,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProfilesService } from './profiles.service';
import { ProfilePhotosService } from './profile-photos.service';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { Profile } from './profile.entity';

@Controller('profiles')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(
    private readonly profilesService: ProfilesService,
    private readonly profilePhotosService: ProfilePhotosService,
  ) {}

  @Get('me')
  async getMyProfile(@Req() req: any) {
    const profile = await this.profilesService.getByUserId(req.user.userId);
    return profile ? this.toResponse(profile) : null;
  }

  @Put('me')
  async updateMyProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
    const profile = await this.profilesService.upsert(req.user.userId, dto);
    return this.toResponse(profile);
  }

  @Post('me/photo')
  @UseInterceptors(
    FileInterceptor('photo', { limits: { fileSize: 5 * 1024 * 1024 } }),
  )
  async uploadPhoto(
    @Req() req: any,
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) {
      throw new BadRequestException('photo file is required');
    }
    const profile = await this.profilePhotosService.replace(
      req.user.userId,
      file,
    );
    return this.toResponse(profile);
  }

  private toResponse(profile: Profile) {
    return {
      userId: profile.userId,
      displayName: profile.displayName,
      bio: profile.bio,
      birthYear: profile.birthYear,
      photoUrl: this.profilesService.photoUrlFor(profile.photoKey),
    };
  }
}
```

- [ ] **Step 4: `ProfilesModule` 배선 (프로바이더 추가; 컨트롤러는 Task 5에서 PhotosController까지 함께)**

`backend/src/profiles/profiles.module.ts` 전체:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Profile } from './profile.entity';
import { ProfilesService } from './profiles.service';
import { ProfilesController } from './profiles.controller';
import { ProfilePhotosService } from './profile-photos.service';
import { PhotoStorage } from './photo-storage';
import { S3PhotoStorage } from './s3-photo-storage';

@Module({
  imports: [TypeOrmModule.forFeature([Profile])],
  controllers: [ProfilesController],
  providers: [
    ProfilesService,
    ProfilePhotosService,
    { provide: PhotoStorage, useClass: S3PhotoStorage },
  ],
  exports: [ProfilesService],
})
export class ProfilesModule {}
```

- [ ] **Step 5: 테스트 + 빌드 확인**

Run: `cd backend && npm run test -- profiles.controller.spec.ts && npm run build`
Expected: 컨트롤러 스펙 PASS (3/3), 빌드 성공.

- [ ] **Step 6: 커밋**

```bash
git add backend/src/profiles/profiles.controller.ts backend/src/profiles/profiles.controller.spec.ts backend/src/profiles/profiles.module.ts
git commit -m "feat: add profile photo upload endpoint and shape profile responses"
```

---

### Task 5: `PhotosController` 공개 서빙

**Files:**
- Create: `backend/src/profiles/photos.controller.ts`
- Create: `backend/src/profiles/photos.controller.spec.ts`
- Modify: `backend/src/profiles/profiles.module.ts`

**Interfaces:**
- Consumes: `ProfilePhotosService.get`(Task 3)
- Produces: `GET /profiles/photos/:key` → `StreamableFile`(content-type 설정). 공개(가드 없음).

- [ ] **Step 1: 실패하는 테스트 작성**

`backend/src/profiles/photos.controller.spec.ts`:

```typescript
import { StreamableFile } from '@nestjs/common';
import { Readable } from 'stream';
import { PhotosController } from './photos.controller';

describe('PhotosController', () => {
  it('serves the stored object as a StreamableFile', async () => {
    const body = Readable.from([Buffer.from('img')]);
    const profilePhotosService = {
      get: jest.fn().mockResolvedValue({ body, contentType: 'image/jpeg' }),
    };
    const controller = new PhotosController(profilePhotosService as any);

    const result = await controller.serve('k.jpg');

    expect(profilePhotosService.get).toHaveBeenCalledWith('k.jpg');
    expect(result).toBeInstanceOf(StreamableFile);
    expect(result.getStream()).toBe(body);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- photos.controller.spec.ts`
Expected: FAIL (`Cannot find module './photos.controller'`)

- [ ] **Step 3: 구현**

`backend/src/profiles/photos.controller.ts`:

```typescript
import { Controller, Get, Param, StreamableFile } from '@nestjs/common';
import { ProfilePhotosService } from './profile-photos.service';

@Controller('profiles/photos')
export class PhotosController {
  constructor(private readonly profilePhotosService: ProfilePhotosService) {}

  @Get(':key')
  async serve(@Param('key') key: string): Promise<StreamableFile> {
    const { body, contentType } = await this.profilePhotosService.get(key);
    return new StreamableFile(body, { type: contentType });
  }
}
```

- [ ] **Step 4: `ProfilesModule`에 컨트롤러 등록**

`backend/src/profiles/profiles.module.ts`의 import에 `PhotosController`를 추가하고 `controllers` 배열을 `[ProfilesController, PhotosController]`로 바꾼다:

```typescript
import { PhotosController } from './photos.controller';
```

```typescript
  controllers: [ProfilesController, PhotosController],
```

- [ ] **Step 5: 테스트 + 빌드 확인**

Run: `cd backend && npm run test -- photos.controller.spec.ts && npm run build`
Expected: PASS (1/1), 빌드 성공.

- [ ] **Step 6: 커밋**

```bash
git add backend/src/profiles/photos.controller.ts backend/src/profiles/photos.controller.spec.ts backend/src/profiles/profiles.module.ts
git commit -m "feat: serve profile photos over a public GET endpoint"
```

---

### Task 6: `GET /swipes/candidates`에 photoUrl 추가

**Files:**
- Modify: `backend/src/swipes/swipes.controller.ts`
- Modify: `backend/src/swipes/swipes.controller.spec.ts`

**Interfaces:**
- Consumes: `ProfilesService.photoUrlFor`(Task 1)
- Produces: 후보 항목에 `photoUrl: string | null` 추가.

- [ ] **Step 1: 실패하는 테스트 갱신 (`swipes.controller.spec.ts`의 `listCandidates` describe)**

`SwipesController.listCandidates` describe의 `profilesService` 목과 검증을 다음으로 교체한다. `beforeEach`의 `profilesService`를 다음으로 바꾼다:

```typescript
    profilesService = {
      listCandidates: jest
        .fn()
        .mockResolvedValue([
          { userId: 'user-3', displayName: 'Amy', bio: 'Hey', photoKey: 'a.jpg' },
        ]),
      photoUrlFor: jest.fn((key: string | null) =>
        key ? `/profiles/photos/${key}` : null,
      ),
    };
```

그리고 결과 검증 `expect(result).toEqual({...})`를 다음으로 교체:

```typescript
    expect(result).toEqual({
      candidates: [
        {
          userId: 'user-3',
          displayName: 'Amy',
          bio: 'Hey',
          photoUrl: '/profiles/photos/a.jpg',
        },
      ],
    });
```

(파일 상단의 `profilesService` 타입 선언에 `photoUrlFor: jest.Mock;`을 추가한다.)

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- swipes.controller.spec.ts`
Expected: FAIL (결과에 `photoUrl` 없음)

- [ ] **Step 3: 구현**

`backend/src/swipes/swipes.controller.ts`의 `listCandidates` 매핑을 교체:

```typescript
    return {
      candidates: candidates.map((c) => ({
        userId: c.userId,
        displayName: c.displayName,
        bio: c.bio,
        photoUrl: this.profilesService.photoUrlFor(c.photoKey),
      })),
    };
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- swipes.controller.spec.ts`
Expected: PASS (기존 개수 유지)

- [ ] **Step 5: 커밋**

```bash
git add backend/src/swipes/swipes.controller.ts backend/src/swipes/swipes.controller.spec.ts
git commit -m "feat: include candidate photoUrl in GET /swipes/candidates"
```

---

### Task 7: `GET /matches`에 counterpartPhotoUrl 추가

**Files:**
- Modify: `backend/src/matches/matches.service.ts`
- Modify: `backend/src/matches/matches.service.spec.ts`

**Interfaces:**
- Consumes: `ProfilesService.photoUrlFor`(Task 1)
- Produces: `MatchWithProfile`에 `counterpartPhotoUrl: string | null` 추가.

- [ ] **Step 1: 실패하는 테스트 갱신 (`matches.service.spec.ts`의 `listForUserWithProfiles` describe)**

`beforeEach`의 `profilesService` 목에 `photoUrlFor`를 추가하고 `listByUserIds` 반환에 `photoKey`를 포함한다:

```typescript
    profilesService = {
      listByUserIds: jest.fn(),
      photoUrlFor: jest.fn((key: string | null) =>
        key ? `/profiles/photos/${key}` : null,
      ),
    };
```

(파일 상단 `profilesService` 타입 선언에 `photoUrlFor: jest.Mock;` 추가.)

첫 번째 테스트('resolves the counterpart ...')의 `listByUserIds` 반환과 기대값을 교체:

```typescript
    profilesService.listByUserIds.mockResolvedValue([
      { userId: 'user-2', displayName: 'Jane', photoKey: 'j.jpg' },
      { userId: 'user-3', displayName: 'Amy', photoKey: null },
    ]);
```

```typescript
    expect(result).toEqual([
      {
        id: 'match-1',
        counterpartUserId: 'user-2',
        counterpartName: 'Jane',
        counterpartPhotoUrl: '/profiles/photos/j.jpg',
      },
      {
        id: 'match-2',
        counterpartUserId: 'user-3',
        counterpartName: 'Amy',
        counterpartPhotoUrl: null,
      },
    ]);
```

두 번째 테스트('sets counterpartName to null ...')의 기대값에 `counterpartPhotoUrl: null`을 추가:

```typescript
    expect(result).toEqual([
      {
        id: 'match-1',
        counterpartUserId: 'user-2',
        counterpartName: null,
        counterpartPhotoUrl: null,
      },
    ]);
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && npm run test -- matches.service.spec.ts`
Expected: FAIL (`counterpartPhotoUrl` 없음)

- [ ] **Step 3: 구현**

`backend/src/matches/matches.service.ts`의 `MatchWithProfile` 인터페이스에 필드 추가:

```typescript
export interface MatchWithProfile {
  id: string;
  counterpartUserId: string;
  counterpartName: string | null;
  counterpartPhotoUrl: string | null;
}
```

`listForUserWithProfiles`에서 이름 맵을 프로필 맵으로 바꾸고 매핑을 교체:

```typescript
    const profiles = await this.profilesService.listByUserIds(counterpartIds);
    const profileByUserId = new Map(
      profiles.map((profile) => [profile.userId, profile]),
    );

    return matches.map((match) => {
      const counterpartUserId =
        match.userAId === userId ? match.userBId : match.userAId;
      const profile = profileByUserId.get(counterpartUserId);
      return {
        id: match.id,
        counterpartUserId,
        counterpartName: profile?.displayName ?? null,
        counterpartPhotoUrl: this.profilesService.photoUrlFor(
          profile?.photoKey ?? null,
        ),
      };
    });
```

- [ ] **Step 4: 테스트 재실행해서 통과 확인**

Run: `cd backend && npm run test -- matches.service.spec.ts`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add backend/src/matches/matches.service.ts backend/src/matches/matches.service.spec.ts
git commit -m "feat: include counterpart photoUrl in GET /matches"
```

---

### Task 8: env + 검증 + README

**Files:**
- Modify: `backend/.env.example`
- Modify: `README.md`

- [ ] **Step 1: `.env.example`에 S3 변수 추가**

`backend/.env.example` 끝에 추가:

```
# 프로필 사진용 오브젝트 스토리지 (S3 호환)
S3_ENDPOINT=http://localhost:9000
S3_REGION=us-east-1
S3_BUCKET=tablemate-photos
S3_ACCESS_KEY_ID=changeme
S3_SECRET_ACCESS_KEY=changeme
S3_FORCE_PATH_STYLE=true
```

- [ ] **Step 2: 백엔드 전체 스위트 + 빌드**

Run: `cd backend && npm run test && npm run build`
Expected: 신규 스펙 전부 통과, `auth.service.spec.ts`만 이 샌드박스의 bcrypt 이슈로 실패, 빌드 성공.

- [ ] **Step 3: README 갱신**

`README.md`를 Read한 뒤:

- 백엔드 `profiles/` 설명에 사진 업로드/서빙(`POST /profiles/me/photo`, `GET /profiles/photos/:key`, 오브젝트 스토리지, 프로필당 1장)을 추가한다.
- "현재 상태 / Known limitations"에 다음을 추가한다: 프로필 사진은 오브젝트 스토리지(S3 호환)에 저장되고 uuid 키로 공개 서빙되며(서명 URL/접근제어는 후속), 모바일 업로드/표시 UI는 다음 서브프로젝트다. 이 개발 샌드박스에서는 실제 S3/MinIO end-to-end 검증이 불가해 `PhotoStorage` 목 유닛 테스트 + `npm run build`로 갈음했다.

- [ ] **Step 4: 커밋**

```bash
git add backend/.env.example README.md
git commit -m "docs: document profile photo storage and add S3 env vars"
```

## Self-Review 결과

- **스펙 커버리지:** 의존성/env(Task 2, 8), `PhotoStorage`+`S3PhotoStorage`(Task 2), `photoKey`/`setPhotoKey`/`photoUrlFor`(Task 1), `ProfilePhotosService` 검증·저장·교체(Task 3), 업로드 엔드포인트+응답 셰이핑(Task 4), 공개 서빙(Task 5), 후보 photoUrl(Task 6), 매칭 counterpartPhotoUrl(Task 7), 검증·문서(Task 8) — 스펙 전 항목 커버.
- **플레이스홀더 스캔:** 없음. 모든 코드 스텝에 실제 코드 포함.
- **타입 일관성:** `PhotoStorage.get` 반환 `{ body: Readable; contentType: string }`이 Task 2 정의·Task 3 소비·Task 5 서빙에서 일치. `ProfilePhotosService.replace(userId, {buffer,mimetype,size})` 시그니처가 Task 3 정의·Task 4 컨트롤러 호출에서 일치. `photoUrlFor`가 Task 1 정의·Task 4/6/7 소비에서 일치. `MatchWithProfile.counterpartPhotoUrl`(Task 7)이 인터페이스·매핑에서 일치. 응답 셰이프 `{userId, displayName, bio, birthYear, photoUrl}`가 Task 4 컨트롤러·스펙에서 일치.
