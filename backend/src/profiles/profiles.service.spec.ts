import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
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
