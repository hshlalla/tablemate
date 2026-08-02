import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Match } from './match.entity';
import { SwipesService } from '../swipes/swipes.service';

@Injectable()
export class MatchesService {
  constructor(
    @InjectRepository(Match) private readonly matchesRepo: Repository<Match>,
    private readonly swipesService: SwipesService,
  ) {}

  async createIfMutual(
    userAId: string,
    userBId: string,
  ): Promise<Match | null> {
    const aLikedB = await this.swipesService.hasLiked(userAId, userBId);
    const bLikedA = await this.swipesService.hasLiked(userBId, userAId);

    if (!aLikedB || !bLikedA) {
      return null;
    }

    const match = this.matchesRepo.create({ userAId, userBId });
    return this.matchesRepo.save(match);
  }

  listForUser(userId: string): Promise<Match[]> {
    return this.matchesRepo
      .createQueryBuilder('match')
      .where('match.userAId = :userId OR match.userBId = :userId', { userId })
      .getMany();
  }
}
