import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { In } from 'typeorm';
import { ProfilesService } from './profiles.service';
import { Profile } from './profile.entity';

describe('ProfilesService.upsert', () => {
  let service: ProfilesService;
  let repo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock };

  beforeEach(async () => {
    repo = {
      findOne: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation((data) => data),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Promise.resolve({ id: 'profile-1', ...data }),
        ),
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
    const result = await service.upsert('user-1', {
      displayName: 'Jane',
      bio: 'Hi',
    });

    expect(repo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 'user-1',
        displayName: 'Jane',
        bio: 'Hi',
      }),
    );
    expect(result.displayName).toBe('Jane');
  });
});

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

describe('ProfilesService.listByUserIds', () => {
  let service: ProfilesService;
  let repo: { find: jest.Mock };

  beforeEach(async () => {
    repo = { find: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ProfilesService,
        { provide: getRepositoryToken(Profile), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(ProfilesService);
  });

  it('fetches the profiles for the given user ids in one query', async () => {
    repo.find.mockResolvedValue([
      { userId: 'user-2', displayName: 'Jane', bio: 'Hi' },
      { userId: 'user-3', displayName: 'Amy', bio: 'Hey' },
    ]);

    const result = await service.listByUserIds(['user-2', 'user-3']);

    expect(repo.find).toHaveBeenCalledWith({
      where: { userId: In(['user-2', 'user-3']) },
    });
    expect(result).toEqual([
      { userId: 'user-2', displayName: 'Jane', bio: 'Hi' },
      { userId: 'user-3', displayName: 'Amy', bio: 'Hey' },
    ]);
  });

  it('returns an empty list without querying when given no ids', async () => {
    const result = await service.listByUserIds([]);

    expect(result).toEqual([]);
    expect(repo.find).not.toHaveBeenCalled();
  });
});
