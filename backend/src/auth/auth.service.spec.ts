import { Test } from '@nestjs/testing';
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
