import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import { UnauthorizedException } from '@nestjs/common';
import { IsNull } from 'typeorm';
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
