import { Test } from '@nestjs/testing';
import { JwtModule } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UsersService } from '../users/users.service';

describe('AuthService.signup', () => {
  let authService: AuthService;
  let usersService: { create: jest.Mock; findByEmail: jest.Mock };

  beforeEach(async () => {
    usersService = {
      create: jest
        .fn()
        .mockImplementation((email, passwordHash) =>
          Promise.resolve({ id: 'user-1', email, passwordHash }),
        ),
      findByEmail: jest.fn().mockResolvedValue(null),
    };

    const moduleRef = await Test.createTestingModule({
      imports: [JwtModule.register({ secret: 'test-secret' })],
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
      imports: [JwtModule.register({ secret: 'test-secret' })],
      providers: [
        AuthService,
        { provide: UsersService, useValue: usersService },
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
