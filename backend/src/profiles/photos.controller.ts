import { Controller, Get, Param, StreamableFile } from '@nestjs/common';
import { ProfilePhotosService } from './profile-photos.service';

@Controller('profiles/photos')
export class PhotosController {
  constructor(private readonly profilePhotosService: ProfilePhotosService) {}

  @Get(':key')
  async serve(@Param('key') key: string): Promise<StreamableFile> {
    const { body, contentType } = await this.profilePhotosService.get(key);
    return new StreamableFile(body, { type: contentType });
  }
}
