import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { JwtService } from '@nestjs/jwt';
import { Server, Socket } from 'socket.io';
import { ChatService } from './chat.service';
import { MatchesService } from '../matches/matches.service';

interface JoinMatchPayload {
  matchId: string;
}

interface SendMessagePayload {
  matchId: string;
  content: string;
}

@WebSocketGateway({ cors: { origin: '*' } })
export class ChatGateway implements OnGatewayConnection {
  @WebSocketServer()
  server: Server;

  constructor(
    private readonly chatService: ChatService,
    private readonly matchesService: MatchesService,
    private readonly jwtService: JwtService,
  ) {}

  handleConnection(client: Socket) {
    const token = client.handshake.auth?.token;
    if (!token) {
      client.disconnect(true);
      return;
    }

    try {
      const payload = this.jwtService.verify(token);
      client.data.userId = payload.sub;
    } catch {
      client.disconnect(true);
    }
  }

  @SubscribeMessage('joinMatch')
  async handleJoinMatch(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: JoinMatchPayload,
  ) {
    const userId = client.data.userId;
    const matches = await this.matchesService.listForUser(userId);
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
  async handleSendMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: SendMessagePayload,
  ) {
    const userId = client.data.userId;
    const matches = await this.matchesService.listForUser(userId);
    const isParticipant = matches.some((m) => m.id === data.matchId);
    if (!isParticipant) {
      client.emit('error', { message: 'Not a participant of this match' });
      return;
    }

    const message = await this.chatService.saveMessage(
      data.matchId,
      userId,
      data.content,
    );
    this.server.to(data.matchId).emit('newMessage', message);
    return message;
  }
}
