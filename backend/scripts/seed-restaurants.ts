import { config } from 'dotenv';
import { join } from 'path';
import { parse } from 'csv-parse/sync';
import { readFileSync } from 'fs';
import { DataSource } from 'typeorm';
import { Restaurant } from '../src/restaurants/restaurant.entity';

// Load environment variables from .env file
config({ path: join(__dirname, '..', '.env') });

export interface RestaurantRow {
  overtureId: string;
  name: string;
  category: string;
  latitude: number;
  longitude: number;
  address: string | null;
}

export function parseRestaurantsCsv(csvContent: string): RestaurantRow[] {
  const records: Record<string, string>[] = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
  });

  return records.map((r) => ({
    overtureId: r.overture_id,
    name: r.name,
    category: r.category,
    latitude: parseFloat(r.latitude),
    longitude: parseFloat(r.longitude),
    address: r.address || null,
  }));
}

async function run() {
  const csvPath = process.argv[2];
  if (!csvPath) {
    console.error('Usage: ts-node seed-restaurants.ts <path-to-csv>');
    process.exit(1);
  }

  const dataSource = new DataSource({
    type: 'postgres',
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    username: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_DATABASE,
    entities: [Restaurant],
  });
  await dataSource.initialize();

  const rows = parseRestaurantsCsv(readFileSync(csvPath, 'utf-8'));
  const repo = dataSource.getRepository(Restaurant);
  for (const row of rows) {
    await repo.upsert(row, ['overtureId']);
  }

  console.log(`Seeded ${rows.length} restaurants`);
  await dataSource.destroy();
}

if (require.main === module) {
  run();
}
