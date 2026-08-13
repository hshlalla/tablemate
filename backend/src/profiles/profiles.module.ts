import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Profile } from './profile.entity';
import { ProfilesService } from './profiles.service';
import { ProfilesController } from './profiles.controller';
import { PhotosController } from './photos.controller';
import { ProfilePhotosService } from './profile-photos.service';
import { PhotoStorage } from './photo-storage';
import { S3PhotoStorage } from './s3-photo-storage';

@Module({
  imports: [TypeOrmModule.forFeature([Profile])],
  controllers: [ProfilesController, PhotosController],
  providers: [
    ProfilesService,
    ProfilePhotosService,
    { provide: PhotoStorage, useClass: S3PhotoStorage },
  ],
  exports: [ProfilesService],
})
export class ProfilesModule {}
