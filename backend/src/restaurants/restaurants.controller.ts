import { Controller, Get } from '@nestjs/common';
import { RestaurantsService } from './restaurants.service';

const OVERTURE_ATTRIBUTION =
  'Restaurant data © Overture Maps Foundation contributors, licensed under CDLA Permissive v2.0';

@Controller('restaurants')
export class RestaurantsController {
  constructor(private readonly restaurantsService: RestaurantsService) {}

  @Get()
  async list() {
    const restaurants = await this.restaurantsService.list();
    return { restaurants, attribution: OVERTURE_ATTRIBUTION };
  }
}
