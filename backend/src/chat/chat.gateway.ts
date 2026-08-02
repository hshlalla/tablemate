import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { ChatService } from './chat.service';
import { MatchesService } from '../matches/matches.service';

interface SendMessagePayload {
  matchId: string;
  senderId: string;
  content: string;
}

@WebSocketGateway({ cors: { origin: '*' } })
export class ChatGateway {
  @WebSocketServer()
  server: Server;

  constructor(
    private readonly chatService: ChatService,
    private readonly matchesService: MatchesService,
  ) {}

  @SubscribeMessage('joinMatch')
  async handleJoinMatch(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { matchId: string; userId: string },
  ) {
    const matches = await this.matchesService.listForUser(data.userId);
    const isParticipant = matches.some((m) => m.id === data.matchId);
    if (!isParticipant) {
      client.emit('error', { message: 'Not a participant of this match' });
      return;
    }
    client.join(data.matchId);
    const history = await this.chatService.listMessages(data.matchId);
    client.emit('history', history);
  }

  @SubscribeMessage('sendMessage')
  async handleSendMessage(@MessageBody() data: SendMessagePayload) {
    const message = await this.chatService.saveMessage(
      data.matchId,
      data.senderId,
      data.content,
    );
    this.server.to(data.matchId).emit('newMessage', message);
    return message;
  }
}
