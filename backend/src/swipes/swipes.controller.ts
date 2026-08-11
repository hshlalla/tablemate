import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';
import { ProfilesService } from '../profiles/profiles.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(
    private readonly swipesService: SwipesService,
    private readonly matchesService: MatchesService,
    private readonly profilesService: ProfilesService,
  ) {}

  @Get('candidates')
  async listCandidates(@Req() req: any) {
    const excludeTargetIds = await this.swipesService.listSwipedTargetIds(
      req.user.userId,
    );
    const candidates = await this.profilesService.listCandidates(
      req.user.userId,
      excludeTargetIds,
    );
    return {
      candidates: candidates.map((c) => ({
        userId: c.userId,
        displayName: c.displayName,
        bio: c.bio,
      })),
    };
  }

  @Post()
  async create(@Req() req: any, @Body() dto: CreateSwipeDto) {
    if (dto.targetUserId === req.user.userId) {
      throw new BadRequestException('Cannot swipe on yourself');
    }

    const swipe = await this.swipesService.record(
      req.user.userId,
      dto.targetUserId,
      dto.liked,
    );
    const match = dto.liked
      ? await this.matchesService.createIfMutual(
          req.user.userId,
          dto.targetUserId,
        )
      : null;
    return { swipe, match };
  }
}
