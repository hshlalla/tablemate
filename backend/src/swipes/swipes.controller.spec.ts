import { Test } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { SwipesController } from './swipes.controller';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';
import { ProfilesService } from '../profiles/profiles.service';

describe('SwipesController.create', () => {
  let controller: SwipesController;
  let swipesService: { record: jest.Mock };
  let matchesService: { createIfMutual: jest.Mock };

  beforeEach(async () => {
    swipesService = {
      record: jest.fn().mockResolvedValue({ id: 'swipe-1', liked: true }),
    };
    matchesService = {
      createIfMutual: jest.fn().mockResolvedValue(null),
    };

    const moduleRef = await Test.createTestingModule({
      controllers: [SwipesController],
      providers: [
        { provide: SwipesService, useValue: swipesService },
        { provide: MatchesService, useValue: matchesService },
        { provide: ProfilesService, useValue: {} },
      ],
    }).compile();

    controller = moduleRef.get(SwipesController);
  });

  it('rejects swiping on yourself without recording a swipe or creating a match', async () => {
    const req = { user: { userId: 'user-1' } };

    await expect(
      controller.create(req, { targetUserId: 'user-1', liked: true }),
    ).rejects.toThrow(BadRequestException);
    await expect(
      controller.create(req, { targetUserId: 'user-1', liked: true }),
    ).rejects.toThrow('Cannot swipe on yourself');

    expect(swipesService.record).not.toHaveBeenCalled();
    expect(matchesService.createIfMutual).not.toHaveBeenCalled();
  });

  it('records the swipe and checks for a match when targeting another user', async () => {
    const req = { user: { userId: 'user-1' } };

    const result = await controller.create(req, {
      targetUserId: 'user-2',
      liked: true,
    });

    expect(swipesService.record).toHaveBeenCalledWith('user-1', 'user-2', true);
    expect(matchesService.createIfMutual).toHaveBeenCalledWith(
      'user-1',
      'user-2',
    );
    expect(result.swipe).toEqual({ id: 'swipe-1', liked: true });
  });
});

describe('SwipesController.listCandidates', () => {
  let controller: SwipesController;
  let swipesService: { listSwipedTargetIds: jest.Mock };
  let profilesService: { listCandidates: jest.Mock; photoUrlFor: jest.Mock };

  beforeEach(async () => {
    swipesService = {
      listSwipedTargetIds: jest.fn().mockResolvedValue(['user-2']),
    };
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

    const moduleRef = await Test.createTestingModule({
      controllers: [SwipesController],
      providers: [
        { provide: SwipesService, useValue: swipesService },
        { provide: MatchesService, useValue: {} },
        { provide: ProfilesService, useValue: profilesService },
      ],
    }).compile();

    controller = moduleRef.get(SwipesController);
  });

  it('excludes already-swiped users and returns candidate profiles', async () => {
    const req = { user: { userId: 'user-1' } };

    const result = await controller.listCandidates(req);

    expect(swipesService.listSwipedTargetIds).toHaveBeenCalledWith('user-1');
    expect(profilesService.listCandidates).toHaveBeenCalledWith('user-1', [
      'user-2',
    ]);
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
  });
});
