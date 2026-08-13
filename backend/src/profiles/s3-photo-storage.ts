import { Injectable, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { Readable } from 'stream';
import { PhotoStorage } from './photo-storage';

@Injectable()
export class S3PhotoStorage implements PhotoStorage {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(config: ConfigService, @Optional() client?: S3Client) {
    this.bucket = config.get<string>('S3_BUCKET') ?? '';
    this.client =
      client ??
      new S3Client({
        region: config.get<string>('S3_REGION') ?? 'us-east-1',
        endpoint: config.get<string>('S3_ENDPOINT'),
        forcePathStyle: config.get<string>('S3_FORCE_PATH_STYLE') === 'true',
        credentials: {
          accessKeyId: config.get<string>('S3_ACCESS_KEY_ID') ?? '',
          secretAccessKey: config.get<string>('S3_SECRET_ACCESS_KEY') ?? '',
        },
      });
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
      }),
    );
  }

  async get(key: string): Promise<{ body: Readable; contentType: string }> {
    const res = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
    );
    return {
      body: res.Body as Readable,
      contentType: res.ContentType ?? 'application/octet-stream',
    };
  }

  async delete(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }
}
