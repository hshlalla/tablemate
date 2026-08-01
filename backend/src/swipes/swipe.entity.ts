import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

@Entity('swipes')
@Index(['fromUserId', 'targetUserId'], { unique: true })
export class Swipe {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  fromUserId: string;

  @Column()
  targetUserId: string;

  @Column()
  liked: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
