import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('restaurants')
export class Restaurant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  overtureId: string;

  @Column()
  name: string;

  @Column()
  category: string;

  @Column('double precision')
  latitude: number;

  @Column('double precision')
  longitude: number;

  @Column({ type: 'text', nullable: true })
  address: string | null;
}
