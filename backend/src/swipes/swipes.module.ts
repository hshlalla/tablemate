import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Swipe } from './swipe.entity';
import { SwipesService } from './swipes.service';
import { SwipesController } from './swipes.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Swipe])],
  controllers: [SwipesController],
  providers: [SwipesService],
  exports: [SwipesService],
})
export class SwipesModule {}
