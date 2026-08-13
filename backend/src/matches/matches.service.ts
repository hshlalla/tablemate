import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Match } from './match.entity';
import { SwipesService } from '../swipes/swipes.service';
import { ProfilesService } from '../profiles/profiles.service';

export interface MatchWithProfile {
  id: string;
  counterpartUserId: string;
  counterpartName: string | null;
}

@Injectable()
export class MatchesService {
  constructor(
    @InjectRepository(Match) private readonly matchesRepo: Repository<Match>,
    private readonly swipesService: SwipesService,
    private readonly profilesService: ProfilesService,
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

    const existing = await this.matchesRepo.findOne({
      where: [
        { userAId, userBId },
        { userAId: userBId, userBId: userAId },
      ],
    });

    if (existing) {
      return existing;
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

  async listForUserWithProfiles(userId: string): Promise<MatchWithProfile[]> {
    const matches = await this.listForUser(userId);
    const counterpartIds = matches.map((match) =>
      match.userAId === userId ? match.userBId : match.userAId,
    );
    const profiles = await this.profilesService.listByUserIds(counterpartIds);
    const nameByUserId = new Map(
      profiles.map((profile) => [profile.userId, profile.displayName]),
    );

    return matches.map((match) => {
      const counterpartUserId =
        match.userAId === userId ? match.userBId : match.userAId;
      return {
        id: match.id,
        counterpartUserId,
        counterpartName: nameByUserId.get(counterpartUserId) ?? null,
      };
    });
  }
}
