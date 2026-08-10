import { Test, TestingModule } from '@nestjs/testing';
import {
  Body,
  Controller,
  INestApplication,
  Module,
  Post,
  ValidationPipe,
} from '@nestjs/common';
import * as request from 'supertest';
import { SignupDto } from '../src/auth/dto/signup.dto';
import { CreateSwipeDto } from '../src/swipes/dto/create-swipe.dto';

// This suite exercises the exact `app.useGlobalPipes(new ValidationPipe(...))`
// configuration wired up in `src/main.ts`, using the real DTOs from the
// codebase (`SignupDto`, `CreateSwipeDto`), against a minimal throwaway
// controller/module instead of the real `AppModule`.
//
// Why not boot the real `AppModule` here: `AppModule` transitively imports
// `AuthModule` -> `AuthService` -> `bcrypt`, and this sandbox's Node binary
// rejects bcrypt's native `.node` module at `dlopen` time (Hardened Runtime
// + Team ID mismatch — see README "Known limitations"). That crash is
// unrelated to routing/validation and reproduces on ANY module graph that
// includes AuthModule, including a live Postgres. So a true end-to-end test
// of `POST /auth/signup` is not reachable in this environment; this suite
// verifies the same global ValidationPipe wiring and the same DTOs instead.

@Controller()
class TestValidationController {
  @Post('signup')
  signup(@Body() dto: SignupDto) {
    return dto;
  }

  @Post('swipes')
  swipe(@Body() dto: CreateSwipeDto) {
    return dto;
  }
}

@Module({ controllers: [TestValidationController] })
class TestValidationModule {}

describe('Global ValidationPipe (e2e-style, no AppModule/bcrypt)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [TestValidationModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects signup with an invalid email and too-short password', () => {
    return request(app.getHttpServer())
      .post('/signup')
      .send({ email: 'not-an-email', password: 'short' })
      .expect(400);
  });

  it('accepts signup with a valid email and password', () => {
    return request(app.getHttpServer())
      .post('/signup')
      .send({ email: 'jane@example.com', password: 'long-enough-password' })
      .expect(201);
  });

  it('rejects a swipe with a non-UUID targetUserId', () => {
    return request(app.getHttpServer())
      .post('/swipes')
      .send({ targetUserId: 'not-a-uuid', liked: true })
      .expect(400);
  });

  it('accepts a swipe with a valid UUID targetUserId', () => {
    return request(app.getHttpServer())
      .post('/swipes')
      .send({
        targetUserId: '123e4567-e89b-12d3-a456-426614174000',
        liked: true,
      })
      .expect(201);
  });
});
