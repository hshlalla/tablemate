import { BadRequestException } from '@nestjs/common';
import { ProfilesController } from './profiles.controller';

describe('ProfilesController', () => {
  let profilesService: {
    getByUserId: jest.Mock;
    upsert: jest.Mock;
    photoUrlFor: jest.Mock;
  };
  let profilePhotosService: { replace: jest.Mock };
  let controller: ProfilesController;

  beforeEach(() => {
    profilesService = {
      getByUserId: jest.fn(),
      upsert: jest.fn(),
      photoUrlFor: jest.fn((key: string | null) =>
        key ? `/profiles/photos/${key}` : null,
      ),
    };
    profilePhotosService = { replace: jest.fn() };
    controller = new ProfilesController(
      profilesService as any,
      profilePhotosService as any,
    );
  });

  it('getMyProfile returns a shaped profile with photoUrl', async () => {
    profilesService.getByUserId.mockResolvedValue({
      id: 'internal',
      userId: 'u1',
      displayName: 'Jane',
      bio: 'Hi',
      birthYear: 1990,
      photoKey: 'k.jpg',
    });

    const result = await controller.getMyProfile({ user: { userId: 'u1' } });

    expect(result).toEqual({
      userId: 'u1',
      displayName: 'Jane',
      bio: 'Hi',
      birthYear: 1990,
      photoUrl: '/profiles/photos/k.jpg',
    });
  });

  it('uploadPhoto delegates to the photos service and shapes the result', async () => {
    profilePhotosService.replace.mockResolvedValue({
      userId: 'u1',
      displayName: 'Jane',
      bio: null,
      birthYear: null,
      photoKey: 'new.jpg',
    });
    const file = { buffer: Buffer.from('x'), mimetype: 'image/jpeg', size: 10 };

    const result = await controller.uploadPhoto(
      { user: { userId: 'u1' } },
      file as any,
    );

    expect(profilePhotosService.replace).toHaveBeenCalledWith('u1', file);
    expect(result.photoUrl).toBe('/profiles/photos/new.jpg');
  });

  it('uploadPhoto throws when no file is provided', async () => {
    await expect(
      controller.uploadPhoto({ user: { userId: 'u1' } }, undefined as any),
    ).rejects.toThrow(BadRequestException);
  });
});
