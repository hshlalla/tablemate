import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { MatchesService } from './matches.service';
import { Match } from './match.entity';
import { SwipesService } from '../swipes/swipes.service';
import { ProfilesService } from '../profiles/profiles.service';

describe('MatchesService.createIfMutual', () => {
  let service: MatchesService;
  let repo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock };
  let swipesService: { hasLiked: jest.Mock };

  beforeEach(async () => {
    repo = {
      findOne: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation((data) => data),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Promise.resolve({ id: 'match-1', ...data }),
        ),
    };
    swipesService = { hasLiked: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        MatchesService,
        { provide: getRepositoryToken(Match), useValue: repo },
        { provide: SwipesService, useValue: swipesService },
        { provide: ProfilesService, useValue: {} },
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
    swipesService.hasLiked
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(false);

    const result = await service.createIfMutual('user-1', 'user-2');

    expect(result).toBeNull();
    expect(repo.save).not.toHaveBeenCalled();
  });

  it('returns the existing match instead of creating a duplicate when one already exists', async () => {
    swipesService.hasLiked.mockResolvedValue(true);
    const existingMatch = {
      id: 'match-existing',
      userAId: 'user-1',
      userBId: 'user-2',
      createdAt: new Date('2026-01-01'),
    };
    repo.findOne.mockResolvedValue(existingMatch);

    const result = await service.createIfMutual('user-1', 'user-2');

    expect(result).toBe(existingMatch);
    expect(repo.create).not.toHaveBeenCalled();
    expect(repo.save).not.toHaveBeenCalled();
  });
});

describe('MatchesService.listForUserWithProfiles', () => {
  let service: MatchesService;
  let queryBuilder: { where: jest.Mock; getMany: jest.Mock };
  let repo: { createQueryBuilder: jest.Mock };
  let profilesService: { listByUserIds: jest.Mock };

  beforeEach(async () => {
    queryBuilder = {
      where: jest.fn().mockReturnThis(),
      getMany: jest.fn(),
    };
    repo = {
      createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
    };
    profilesService = { listByUserIds: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        MatchesService,
        { provide: getRepositoryToken(Match), useValue: repo },
        { provide: SwipesService, useValue: {} },
        { provide: ProfilesService, useValue: profilesService },
      ],
    }).compile();

    service = moduleRef.get(MatchesService);
  });

  it('resolves the counterpart on each side of the match and attaches their display name', async () => {
    queryBuilder.getMany.mockResolvedValue([
      { id: 'match-1', userAId: 'user-1', userBId: 'user-2' },
      { id: 'match-2', userAId: 'user-3', userBId: 'user-1' },
    ]);
    profilesService.listByUserIds.mockResolvedValue([
      { userId: 'user-2', displayName: 'Jane' },
      { userId: 'user-3', displayName: 'Amy' },
    ]);

    const result = await service.listForUserWithProfiles('user-1');

    expect(profilesService.listByUserIds).toHaveBeenCalledWith([
      'user-2',
      'user-3',
    ]);
    expect(result).toEqual([
      { id: 'match-1', counterpartUserId: 'user-2', counterpartName: 'Jane' },
      { id: 'match-2', counterpartUserId: 'user-3', counterpartName: 'Amy' },
    ]);
  });

  it('sets counterpartName to null when the counterpart has no profile', async () => {
    queryBuilder.getMany.mockResolvedValue([
      { id: 'match-1', userAId: 'user-1', userBId: 'user-2' },
    ]);
    profilesService.listByUserIds.mockResolvedValue([]);

    const result = await service.listForUserWithProfiles('user-1');

    expect(result).toEqual([
      { id: 'match-1', counterpartUserId: 'user-2', counterpartName: null },
    ]);
  });
});
