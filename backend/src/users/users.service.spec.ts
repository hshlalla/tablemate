import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { UsersService } from './users.service';
import { User } from './user.entity';

describe('UsersService.findById', () => {
  let service: UsersService;
  let repo: { findOne: jest.Mock };

  beforeEach(async () => {
    repo = { findOne: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: getRepositoryToken(User), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(UsersService);
  });

  it('looks up a user by id', async () => {
    const user = { id: 'user-1', email: 'jane@example.com' };
    repo.findOne.mockResolvedValue(user);

    const result = await service.findById('user-1');

    expect(repo.findOne).toHaveBeenCalledWith({ where: { id: 'user-1' } });
    expect(result).toBe(user);
  });
});
