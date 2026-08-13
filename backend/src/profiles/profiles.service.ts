import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { Profile } from './profile.entity';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class ProfilesService {
  constructor(
    @InjectRepository(Profile)
    private readonly profilesRepo: Repository<Profile>,
  ) {}

  getByUserId(userId: string): Promise<Profile | null> {
    return this.profilesRepo.findOne({ where: { userId } });
  }

  async listByUserIds(userIds: string[]): Promise<Profile[]> {
    if (userIds.length === 0) {
      return [];
    }
    return this.profilesRepo.find({ where: { userId: In(userIds) } });
  }

  async upsert(userId: string, dto: UpdateProfileDto): Promise<Profile> {
    const existing = await this.getByUserId(userId);
    const profile = this.profilesRepo.create({
      ...existing,
      userId,
      displayName: dto.displayName,
      bio: dto.bio ?? null,
      birthYear: dto.birthYear ?? null,
    });
    return this.profilesRepo.save(profile);
  }

  async listCandidates(
    excludeUserId: string,
    excludeTargetIds: string[],
  ): Promise<Profile[]> {
    const excludeIds = [excludeUserId, ...excludeTargetIds];
    return this.profilesRepo
      .createQueryBuilder('profile')
      .where('profile.userId NOT IN (:...excludeIds)', { excludeIds })
      .take(50)
      .getMany();
  }
}
