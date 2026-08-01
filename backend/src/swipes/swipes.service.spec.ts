import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { SwipesService } from './swipes.service';
import { Swipe } from './swipe.entity';

describe('SwipesService', () => {
  let service: SwipesService;
  let repo: { create: jest.Mock; save: jest.Mock; findOne: jest.Mock };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Promise.resolve({ id: 'swipe-1', ...data }),
        ),
      findOne: jest.fn(),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        SwipesService,
        { provide: getRepositoryToken(Swipe), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(SwipesService);
  });

  it('records a like swipe', async () => {
    const result = await service.record('user-1', 'user-2', true);

    expect(repo.create).toHaveBeenCalledWith({
      fromUserId: 'user-1',
      targetUserId: 'user-2',
      liked: true,
    });
    expect(result.liked).toBe(true);
  });

  it('reports whether a user has liked another', async () => {
    repo.findOne.mockResolvedValue({ id: 'swipe-1', liked: true });

    const result = await service.hasLiked('user-1', 'user-2');

    expect(repo.findOne).toHaveBeenCalledWith({
      where: { fromUserId: 'user-1', targetUserId: 'user-2', liked: true },
    });
    expect(result).toBe(true);
  });
});
