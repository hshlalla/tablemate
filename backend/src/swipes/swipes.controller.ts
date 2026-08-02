import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { MatchesService } from '../matches/matches.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(
    private readonly swipesService: SwipesService,
    private readonly matchesService: MatchesService,
  ) {}

  @Post()
  async create(@Req() req: any, @Body() dto: CreateSwipeDto) {
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
