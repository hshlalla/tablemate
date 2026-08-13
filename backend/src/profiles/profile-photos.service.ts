import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Readable } from 'stream';
import { PhotoStorage } from './photo-storage';
import { ProfilesService } from './profiles.service';
import { Profile } from './profile.entity';

const MAX_SIZE = 5 * 1024 * 1024;
const EXT_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
};

@Injectable()
export class ProfilePhotosService {
  constructor(
    private readonly storage: PhotoStorage,
    private readonly profilesService: ProfilesService,
  ) {}

  async replace(
    userId: string,
    file: { buffer: Buffer; mimetype: string; size: number },
  ): Promise<Profile> {
    const ext = EXT_BY_MIME[file.mimetype];
    if (!ext) {
      throw new BadRequestException('Only JPEG and PNG images are allowed');
    }
    if (file.size > MAX_SIZE) {
      throw new BadRequestException('Image must be 5MB or smaller');
    }

    const key = `${randomUUID()}.${ext}`;
    await this.storage.put(key, file.buffer, file.mimetype);

    const current = await this.profilesService.getByUserId(userId);
    if (current?.photoKey) {
      try {
        await this.storage.delete(current.photoKey);
      } catch {
        // best-effort cleanup of the previous object
      }
    }

    return this.profilesService.setPhotoKey(userId, key);
  }

  get(key: string): Promise<{ body: Readable; contentType: string }> {
    return this.storage.get(key);
  }
}
