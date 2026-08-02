import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ChatService } from './chat.service';
import { Message } from './message.entity';

describe('ChatService', () => {
  let service: ChatService;
  let repo: { create: jest.Mock; save: jest.Mock; find: jest.Mock };

  beforeEach(async () => {
    repo = {
      create: jest.fn().mockImplementation((data) => data),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Promise.resolve({ id: 'msg-1', ...data }),
        ),
      find: jest.fn().mockResolvedValue([]),
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: getRepositoryToken(Message), useValue: repo },
      ],
    }).compile();

    service = moduleRef.get(ChatService);
  });

  it('saves a message tied to a match', async () => {
    const result = await service.saveMessage('match-1', 'user-1', 'hello');

    expect(repo.create).toHaveBeenCalledWith({
      matchId: 'match-1',
      senderId: 'user-1',
      content: 'hello',
    });
    expect(result.content).toBe('hello');
  });

  it('lists messages ordered by creation time for a match', async () => {
    await service.listMessages('match-1');

    expect(repo.find).toHaveBeenCalledWith({
      where: { matchId: 'match-1' },
      order: { createdAt: 'ASC' },
    });
  });
});
