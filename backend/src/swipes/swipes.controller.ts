import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SwipesService } from './swipes.service';
import { CreateSwipeDto } from './dto/create-swipe.dto';

@Controller('swipes')
@UseGuards(JwtAuthGuard)
export class SwipesController {
  constructor(private readonly swipesService: SwipesService) {}

  @Post()
  create(@Req() req: any, @Body() dto: CreateSwipeDto) {
    return this.swipesService.record(
      req.user.userId,
      dto.targetUserId,
      dto.liked,
    );
  }
}
