import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Put,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProfilesService } from './profiles.service';
import { ProfilePhotosService } from './profile-photos.service';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { Profile } from './profile.entity';

@Controller('profiles')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(
    private readonly profilesService: ProfilesService,
    private readonly profilePhotosService: ProfilePhotosService,
  ) {}

  @Get('me')
  async getMyProfile(@Req() req: any) {
    const profile = await this.profilesService.getByUserId(req.user.userId);
    return profile ? this.toResponse(profile) : null;
  }

  @Put('me')
  async updateMyProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
    const profile = await this.profilesService.upsert(req.user.userId, dto);
    return this.toResponse(profile);
  }

  @Post('me/photo')
  @UseInterceptors(
    FileInterceptor('photo', { limits: { fileSize: 5 * 1024 * 1024 } }),
  )
  async uploadPhoto(@Req() req: any, @UploadedFile() file: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('photo file is required');
    }
    const profile = await this.profilePhotosService.replace(
      req.user.userId,
      file,
    );
    return this.toResponse(profile);
  }

  private toResponse(profile: Profile) {
    return {
      userId: profile.userId,
      displayName: profile.displayName,
      bio: profile.bio,
      birthYear: profile.birthYear,
      photoUrl: this.profilesService.photoUrlFor(profile.photoKey),
    };
  }
}
