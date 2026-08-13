import { BadRequestException } from '@nestjs/common';
import { ProfilePhotosService } from './profile-photos.service';

describe('ProfilePhotosService', () => {
  let storage: { put: jest.Mock; get: jest.Mock; delete: jest.Mock };
  let profilesService: { getByUserId: jest.Mock; setPhotoKey: jest.Mock };
  let service: ProfilePhotosService;

  beforeEach(() => {
    storage = {
      put: jest.fn().mockResolvedValue(undefined),
      get: jest.fn(),
      delete: jest.fn().mockResolvedValue(undefined),
    };
    profilesService = {
      getByUserId: jest.fn(),
      setPhotoKey: jest
        .fn()
        .mockImplementation((userId, photoKey) =>
          Promise.resolve({ userId, photoKey }),
        ),
    };
    service = new ProfilePhotosService(storage as any, profilesService as any);
  });

  it('stores a jpeg under a uuid key and records it on the profile', async () => {
    profilesService.getByUserId.mockResolvedValue({
      userId: 'u1',
      photoKey: null,
    });

    const result = await service.replace('u1', {
      buffer: Buffer.from('x'),
      mimetype: 'image/jpeg',
      size: 100,
    });

    const key = storage.put.mock.calls[0][0];
    expect(key).toMatch(/^[0-9a-f-]{36}\.jpg$/);
    expect(storage.put).toHaveBeenCalledWith(
      key,
      expect.any(Buffer),
      'image/jpeg',
    );
    expect(storage.delete).not.toHaveBeenCalled();
    expect(profilesService.setPhotoKey).toHaveBeenCalledWith('u1', key);
    expect(result.photoKey).toBe(key);
  });

  it('deletes the previous object when replacing an existing photo', async () => {
    profilesService.getByUserId.mockResolvedValue({
      userId: 'u1',
      photoKey: 'old.jpg',
    });

    await service.replace('u1', {
      buffer: Buffer.from('x'),
      mimetype: 'image/png',
      size: 100,
    });

    expect(storage.delete).toHaveBeenCalledWith('old.jpg');
    const key = storage.put.mock.calls[0][0];
    expect(key).toMatch(/^[0-9a-f-]{36}\.png$/);
  });

  it('rejects a non image/jpeg-png mimetype', async () => {
    await expect(
      service.replace('u1', {
        buffer: Buffer.from('x'),
        mimetype: 'image/gif',
        size: 100,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(storage.put).not.toHaveBeenCalled();
  });

  it('rejects a file larger than 5MB', async () => {
    await expect(
      service.replace('u1', {
        buffer: Buffer.from('x'),
        mimetype: 'image/jpeg',
        size: 6 * 1024 * 1024,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(storage.put).not.toHaveBeenCalled();
  });

  it('get delegates to storage', async () => {
    storage.get.mockResolvedValue({ body: 'stream', contentType: 'image/jpeg' });

    const result = await service.get('k.jpg');

    expect(storage.get).toHaveBeenCalledWith('k.jpg');
    expect(result).toEqual({ body: 'stream', contentType: 'image/jpeg' });
  });
});
