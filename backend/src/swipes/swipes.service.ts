import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Swipe } from './swipe.entity';

@Injectable()
export class SwipesService {
  constructor(
    @InjectRepository(Swipe) private readonly swipesRepo: Repository<Swipe>,
  ) {}

  async record(
    fromUserId: string,
    targetUserId: string,
    liked: boolean,
  ): Promise<Swipe> {
    const swipe = this.swipesRepo.create({ fromUserId, targetUserId, liked });
    return this.swipesRepo.save(swipe);
  }

  async hasLiked(fromUserId: string, targetUserId: string): Promise<boolean> {
    const swipe = await this.swipesRepo.findOne({
      where: { fromUserId, targetUserId, liked: true },
    });
    return !!swipe;
  }
}
