import { Body, Controller, Get, Put, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProfilesService } from './profiles.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Controller('profiles')
@UseGuards(JwtAuthGuard)
export class ProfilesController {
  constructor(private readonly profilesService: ProfilesService) {}

  @Get('me')
  getMyProfile(@Req() req: any) {
    return this.profilesService.getByUserId(req.user.userId);
  }

  @Put('me')
  updateMyProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
    return this.profilesService.upsert(req.user.userId, dto);
  }
}
