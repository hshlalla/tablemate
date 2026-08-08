import { Test } from '@nestjs/testing';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { MatchesService } from '../matches/matches.service';
import { JwtService } from '@nestjs/jwt';

describe('ChatGateway', () => {
  let gateway: ChatGateway;
  let chatService: { saveMessage: jest.Mock; listMessages: jest.Mock };
  let matchesService: { listForUser: jest.Mock };
  let jwtService: { verify: jest.Mock };
  let server: { to: jest.Mock; emit: jest.Mock };

  const makeClient = (overrides: Partial<any> = {}) => ({
    id: 'socket-1',
    handshake: { auth: {} },
    data: {} as { userId?: string },
    join: jest.fn(),
    emit: jest.fn(),
    disconnect: jest.fn(),
    ...overrides,
  });

  beforeEach(async () => {
    chatService = {
      saveMessage: jest
        .fn()
        .mockImplementation((matchId, senderId, content) =>
          Promise.resolve({ id: 'msg-1', matchId, senderId, content }),
        ),
      listMessages: jest.fn().mockResolvedValue([]),
    };
    matchesService = { listForUser: jest.fn() };
    jwtService = { verify: jest.fn() };

    const moduleRef = await Test.createTestingModule({
      providers: [
        ChatGateway,
        { provide: ChatService, useValue: chatService },
        { provide: MatchesService, useValue: matchesService },
        { provide: JwtService, useValue: jwtService },
      ],
    }).compile();

    gateway = moduleRef.get(ChatGateway);

    server = { to: jest.fn().mockReturnThis(), emit: jest.fn() };
    gateway.server = server as any;
  });

  describe('handleConnection', () => {
    it('sets client.data.userId when the token is valid and does not disconnect', () => {
      jwtService.verify.mockReturnValue({ sub: 'user-1', email: 'a@b.com' });
      const client = makeClient({
        handshake: { auth: { token: 'good-token' } },
      });

      gateway.handleConnection(client as any);

      expect(jwtService.verify).toHaveBeenCalledWith('good-token');
      expect(client.data.userId).toBe('user-1');
      expect(client.disconnect).not.toHaveBeenCalled();
    });

    it('disconnects the client when the token is missing', () => {
      const client = makeClient({ handshake: { auth: {} } });

      gateway.handleConnection(client as any);

      expect(client.disconnect).toHaveBeenCalledWith(true);
      expect(client.data.userId).toBeUndefined();
    });

    it('disconnects the client when the token is invalid/expired', () => {
      jwtService.verify.mockImplementation(() => {
        throw new Error('jwt expired');
      });
      const client = makeClient({
        handshake: { auth: { token: 'bad-token' } },
      });

      gateway.handleConnection(client as any);

      expect(client.disconnect).toHaveBeenCalledWith(true);
      expect(client.data.userId).toBeUndefined();
    });
  });

  describe('handleJoinMatch', () => {
    it('joins the room and emits history when the authenticated user is a participant', async () => {
      const client = makeClient({ data: { userId: 'user-1' } });
      matchesService.listForUser.mockResolvedValue([{ id: 'match-1' }]);
      chatService.listMessages.mockResolvedValue([{ id: 'msg-1' }]);

      await gateway.handleJoinMatch(client as any, { matchId: 'match-1' });

      expect(matchesService.listForUser).toHaveBeenCalledWith('user-1');
      expect(client.join).toHaveBeenCalledWith('match-1');
      expect(client.emit).toHaveBeenCalledWith('history', [{ id: 'msg-1' }]);
    });

    it('emits error and does not join when the authenticated user is not a participant', async () => {
      const client = makeClient({ data: { userId: 'user-1' } });
      matchesService.listForUser.mockResolvedValue([{ id: 'other-match' }]);

      await gateway.handleJoinMatch(client as any, { matchId: 'match-1' });

      expect(client.join).not.toHaveBeenCalled();
      expect(client.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({ message: expect.any(String) }),
      );
    });
  });

  describe('handleSendMessage', () => {
    it('saves and broadcasts the message when the authenticated user is a participant', async () => {
      const client = makeClient({ data: { userId: 'user-1' } });
      matchesService.listForUser.mockResolvedValue([{ id: 'match-1' }]);

      await gateway.handleSendMessage(client as any, {
        matchId: 'match-1',
        content: 'hello',
      });

      expect(chatService.saveMessage).toHaveBeenCalledWith(
        'match-1',
        'user-1',
        'hello',
      );
      expect(server.to).toHaveBeenCalledWith('match-1');
      expect(server.emit).toHaveBeenCalledWith(
        'newMessage',
        expect.objectContaining({ senderId: 'user-1', content: 'hello' }),
      );
    });

    it('does not save or broadcast, and emits error, when the user is not a participant', async () => {
      const client = makeClient({ data: { userId: 'user-1' } });
      matchesService.listForUser.mockResolvedValue([{ id: 'other-match' }]);

      await gateway.handleSendMessage(client as any, {
        matchId: 'match-1',
        content: 'hello',
      });

      expect(chatService.saveMessage).not.toHaveBeenCalled();
      expect(server.emit).not.toHaveBeenCalled();
      expect(client.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({ message: expect.any(String) }),
      );
    });
  });
});
