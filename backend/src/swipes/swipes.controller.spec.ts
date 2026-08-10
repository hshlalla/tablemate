import { Test } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { SwipesController } from './swipes.controller';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';

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
