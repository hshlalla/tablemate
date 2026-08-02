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
});
