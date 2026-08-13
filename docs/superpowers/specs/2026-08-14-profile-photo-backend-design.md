# 프로필 사진 (백엔드) 설계 문서

**작성일:** 2026-08-14
**상태:** 설계 승인됨 (구현 계획 대기)

## 목표

프로필에 사진을 올릴 수 있게 하는 기능의 **백엔드 부분**을 구현한다. 사진 바이트는 오브젝트 스토리지(S3 호환)에 저장하고, 업로드/서빙 엔드포인트를 제공하며, 프로필·후보·매칭 응답에 `photoUrl`을 노출한다. 모바일 표시/업로드 UI는 다음 서브프로젝트로 분리한다.

## 설계 결정 (확정)

- **범위:** 백엔드 먼저(업로드/저장/서빙 + 응답의 photoUrl). 모바일은 후속 서브프로젝트.
- **저장소:** 오브젝트 스토리지(S3/MinIO). `@aws-sdk/client-s3` 사용. `PhotoStorage` 추상화 뒤에 두어 테스트에서 목킹.
- **서빙:** 백엔드 GET 프록시(`GET /profiles/photos/:key`)로 스토리지 스트림을 중계 — 안정적 상대 URL, 버킷 비공개 유지, 저장소 종류에 무관, 테스트 용이. (프로덕션의 서명 URL/접근제어는 후속.)
- **사진 수:** 프로필당 1장(primary). 다중 사진은 후속.
- **파일 제한:** `image/jpeg`·`image/png`만, 최대 5MB.

## 비목표

- 모바일 표시/업로드 UI, 이미지 리사이즈·썸네일, 다중 사진, 서명 URL/접근제어, EXIF 처리.

## 실현가능성 스파이크 (수행됨)

- `npm view @aws-sdk/client-s3 version` → `3.1109.0` (레지스트리 도달 가능).
- `@nestjs/platform-express`(^10) + `multer` 번들 확인 → `FileInterceptor`로 멀티파트 처리(신규 top-level 의존성 불필요, `@types/multer` dev만 추가).

---

## 아키텍처

### 의존성 & 설정

- 추가: `@aws-sdk/client-s3`(prod), `@types/multer`(dev).
- `.env.example`에 추가: `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_FORCE_PATH_STYLE`(MinIO 경로형 접근용, 기본 false).

### 저장 추상화 (`backend/src/profiles/photo-storage.ts`)

```
export abstract class PhotoStorage {
  abstract put(key: string, body: Buffer, contentType: string): Promise<void>;
  abstract get(key: string): Promise<{ body: Readable; contentType: string }>;
  abstract delete(key: string): Promise<void>;
}
```

- DI 토큰으로 추상 클래스 `PhotoStorage`를 사용한다.
- `S3PhotoStorage implements PhotoStorage` (`backend/src/profiles/s3-photo-storage.ts`): `S3Client`를 ConfigService로 구성(`PutObjectCommand`/`GetObjectCommand`/`DeleteObjectCommand`). 생성자에 `S3Client` 주입 가능하게 하여 목으로 테스트.
- `ProfilesModule`이 `{ provide: PhotoStorage, useClass: S3PhotoStorage }`로 바인딩. 테스트는 `PhotoStorage` 목 제공(실제 S3 불필요).

### 데이터 모델

- `Profile`에 `photoKey: string | null` 컬럼 추가(스토리지 오브젝트 키, 예: `<uuid>.jpg`). 응답에는 절대 노출하지 않고 `photoUrl`로 파생한다.
- `ProfilesService.photoUrlFor(photoKey: string | null): string | null` = `photoKey == null ? null : '/profiles/photos/' + photoKey`. 키는 URL-safe(`<uuid>.<ext>`)라 인코딩 불필요. 모바일이 base URL을 앞에 붙인다.

### 서비스

- `ProfilesService`(기존 확장):
  - `setPhotoKey(userId: string, photoKey: string): Promise<Profile>` — 프로필의 `photoKey` 갱신(프로필이 없으면 예외/무시는 아래 참고).
  - `photoUrlFor(...)` (위).
- `ProfilePhotosService`(신규, `backend/src/profiles/profile-photos.service.ts`): `PhotoStorage` + `ProfilesService` 주입.
  - `replace(userId, file: { buffer: Buffer; mimetype: string; size: number }): Promise<Profile>` — 검증(`image/jpeg`|`image/png`, ≤5MB, 아니면 `BadRequestException`) → `key = randomUUID() + ext(mimetype)` → `storage.put(key, buffer, mimetype)` → 기존 `photoKey`가 있으면 `storage.delete(old)`(best-effort) → `profilesService.setPhotoKey(userId, key)` 반환.
  - `get(key: string): Promise<{ body: Readable; contentType: string }>` → `storage.get(key)`.
  - `ext(mimetype)`: `image/jpeg`→`jpg`, `image/png`→`png`.
  - 키 생성은 Node 내장 `crypto.randomUUID()` 사용(신규 의존성 없음).

### 엔드포인트

- `POST /profiles/me/photo` — `ProfilesController`(기존, `@UseGuards(JwtAuthGuard)`)에 추가. `@UseInterceptors(FileInterceptor('photo', { limits: { fileSize: 5 * 1024 * 1024 } }))` + `@UploadedFile() file`. `ProfilePhotosService.replace(req.user.userId, file)` 호출 후, 셰이핑된 프로필 응답(아래) 반환. 파일 누락 시 `BadRequestException`.
- `GET /profiles/photos/:key` — 신규 **공개** 컨트롤러 `PhotosController`(`@Controller('profiles/photos')`, 가드 없음). `ProfilePhotosService.get(key)`의 스트림을 해당 content-type으로 서빙(`@Res({ passthrough: false })` 또는 `StreamableFile`). 키는 uuid라 사실상 추측 불가 — 이번 서브프로젝트는 공개 서빙.
- `GET /profiles/me`(기존): 엔티티를 그대로 반환하던 것을 셰이핑해 `{ userId, displayName, bio, birthYear, photoUrl }` 반환(`photoKey`·내부 `id` 비노출).

### 응답 보강 (photoUrl 노출)

- `GET /swipes/candidates`(`SwipesController.listCandidates`): 각 후보 매핑에 `photoUrl: this.profilesService.photoUrlFor(c.photoKey)` 추가.
- `GET /matches`(`MatchesService.listForUserWithProfiles` → `MatchWithProfile`): `counterpartPhotoUrl: string | null` 추가. 상대 프로필을 `displayName`뿐 아니라 `photoKey`까지 매핑하도록 확장하고 `ProfilesService.photoUrlFor`로 변환.

---

## 테스트 & 검증

모든 신규 스펙은 이 개발 샌드박스에서 실행된다(profiles/swipes/matches 계열은 bcrypt를 import하지 않음).

- `ProfilePhotosService`(`profile-photos.service.spec.ts`, `PhotoStorage`·`ProfilesService` 목): jpeg 업로드가 키 생성·`storage.put`·`setPhotoKey`를 호출; 기존 키가 있으면 `storage.delete` 호출; 잘못된 mimetype/과대 파일이면 `BadRequestException`; `get`이 `storage.get` 위임.
- `S3PhotoStorage`(`s3-photo-storage.spec.ts`, 목 `S3Client`): `put`이 올바른 Bucket/Key/Body/ContentType로 `PutObjectCommand`를 `send`; `delete`가 `DeleteObjectCommand`를 `send`.
- `ProfilesService`: `setPhotoKey`가 `photoKey`를 저장; `photoUrlFor` 매핑(널/비널).
- `SwipesController.listCandidates`: 응답 후보에 `photoUrl` 포함.
- `MatchesService.listForUserWithProfiles`: `counterpartPhotoUrl` 포함(프로필 있음/없음).
- `PhotosController`: `get`이 서비스 스트림/타입을 서빙(목 `ProfilePhotosService`).
- `npm run test`(신규 스펙 실행, `auth.service.spec.ts`만 기존 bcrypt 이슈로 실패) + `npm run build`.
- 각 단위 TDD.

## 알려진 제약 (구현 후 README 반영)

- 프로필 사진은 오브젝트 스토리지(S3 호환)에 저장되고 `GET /profiles/photos/:key`로 서빙된다. 프로필당 1장.
- 이 개발 샌드박스에서는 실제 S3/MinIO를 띄운 end-to-end 검증이 불가하다 — `PhotoStorage` 목 기반 유닛 테스트 + `npm run build`로 갈음한다.
- 사진 서빙은 uuid 키 공개 접근 방식이다(서명 URL/접근제어 미구현). 모바일 업로드/표시 UI는 후속 서브프로젝트.
