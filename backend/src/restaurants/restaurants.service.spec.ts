import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { RestaurantsService } from './restaurants.service';
import { Restaurant } from './restaurant.entity';

describe('RestaurantsService.list', () => {
  let service: RestaurantsService;
  let repo: { find: jest.Mock };

  beforeEach(async () => {
    repo = {
      find: jest.fn().mockResolvedValue([{ id: 'r1', name: '서울식당' }]),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        RestaurantsService,
        { provide: getRepositoryToken(Restaurant), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(RestaurantsService);
  });

  it('returns all seeded restaurants', async () => {
    const result = await service.list();

    expect(result).toEqual([{ id: 'r1', name: '서울식당' }]);
  });
});
