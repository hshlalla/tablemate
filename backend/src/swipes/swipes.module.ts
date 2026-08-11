import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Swipe } from './swipe.entity';
import { SwipesService } from './swipes.service';
import { SwipesController } from './swipes.controller';
import { MatchesModule } from '../matches/matches.module';
import { ProfilesModule } from '../profiles/profiles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Swipe]),
    forwardRef(() => MatchesModule),
    ProfilesModule,
  ],
  controllers: [SwipesController],
  providers: [SwipesService],
  exports: [SwipesService],
})
export class SwipesModule {}
