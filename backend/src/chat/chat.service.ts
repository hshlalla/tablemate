import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message } from './message.entity';

@Injectable()
export class ChatService {
  constructor(
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
  ) {}

  async saveMessage(
    matchId: string,
    senderId: string,
    content: string,
  ): Promise<Message> {
    const message = this.messagesRepo.create({ matchId, senderId, content });
    return this.messagesRepo.save(message);
  }

  listMessages(matchId: string): Promise<Message[]> {
    return this.messagesRepo.find({
      where: { matchId },
      order: { createdAt: 'ASC' },
    });
  }
}
