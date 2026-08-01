import { IsBoolean, IsUUID } from 'class-validator';

export class CreateSwipeDto {
  @IsUUID()
  targetUserId: string;

  @IsBoolean()
  liked: boolean;
}
