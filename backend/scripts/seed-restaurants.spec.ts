import { readFileSync } from 'fs';
import { join } from 'path';
import { parseRestaurantsCsv } from './seed-restaurants';

describe('parseRestaurantsCsv', () => {
  it('parses the fixture CSV into typed restaurant rows', () => {
    const csvContent = readFileSync(
      join(__dirname, 'fixtures/sample-restaurants.csv'),
      'utf-8',
    );

    const rows = parseRestaurantsCsv(csvContent);

    expect(rows).toHaveLength(5);
    expect(rows[0]).toEqual({
      overtureId: 'ovt-001',
      name: '서울식당',
      category: 'restaurant',
      latitude: 37.5665,
      longitude: 126.978,
      address: '서울 중구 세종대로 110',
    });
  });
});
