import { Readable } from 'stream';

export abstract class PhotoStorage {
  abstract put(key: string, body: Buffer, contentType: string): Promise<void>;
  abstract get(key: string): Promise<{ body: Readable; contentType: string }>;
  abstract delete(key: string): Promise<void>;
}
