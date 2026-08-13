import { Test } from '@nestjs/testing';
import { MatchesController } from './matches.controller';
import { MatchesService } from './matches.service';

describe('MatchesController.listMine', () => {
  let controller: MatchesController;
  let matchesService: { listForUserWithProfiles: jest.Mock };

  beforeEach(async () => {
    matchesService = {
      listForUserWithProfiles: jest.fn().mockResolvedValue([
        { id: 'match-1', counterpartUserId: 'user-2', counterpartName: 'Jane' },
      ]),
    };

    const moduleRef = await Test.createTestingModule({
      controllers: [MatchesController],
      providers: [{ provide: MatchesService, useValue: matchesService }],
    }).compile();

    controller = moduleRef.get(MatchesController);
  });

  it('returns the caller matches enriched with counterpart profile names', async () => {
    const req = { user: { userId: 'user-1' } };

    const result = await controller.listMine(req);

    expect(matchesService.listForUserWithProfiles).toHaveBeenCalledWith(
      'user-1',
    );
    expect(result).toEqual([
      { id: 'match-1', counterpartUserId: 'user-2', counterpartName: 'Jane' },
    ]);
  });
});
