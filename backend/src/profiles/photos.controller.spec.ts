import { StreamableFile } from '@nestjs/common';
import { Readable } from 'stream';
import { PhotosController } from './photos.controller';

describe('PhotosController', () => {
  it('serves the stored object as a StreamableFile', async () => {
    const body = Readable.from([Buffer.from('img')]);
    const profilePhotosService = {
      get: jest.fn().mockResolvedValue({ body, contentType: 'image/jpeg' }),
    };
    const controller = new PhotosController(profilePhotosService as any);

    const result = await controller.serve('k.jpg');

    expect(profilePhotosService.get).toHaveBeenCalledWith('k.jpg');
    expect(result).toBeInstanceOf(StreamableFile);
    expect(result.getStream()).toBe(body);
  });
});
