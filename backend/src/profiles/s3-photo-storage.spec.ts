import {
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { S3PhotoStorage } from './s3-photo-storage';

function makeStorage(send: jest.Mock): S3PhotoStorage {
  const config = {
    get: (key: string) => (key === 'S3_BUCKET' ? 'my-bucket' : undefined),
  };
  return new S3PhotoStorage(config as any, { send } as any);
}

describe('S3PhotoStorage', () => {
  it('put sends a PutObjectCommand with bucket/key/body/content-type', async () => {
    const send = jest.fn().mockResolvedValue({});
    const storage = makeStorage(send);
    const body = Buffer.from('bytes');

    await storage.put('k.jpg', body, 'image/jpeg');

    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(PutObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'my-bucket',
      Key: 'k.jpg',
      Body: body,
      ContentType: 'image/jpeg',
    });
  });

  it('get returns the object body and content type', async () => {
    const fakeBody = { pipe: jest.fn() };
    const send = jest
      .fn()
      .mockResolvedValue({ Body: fakeBody, ContentType: 'image/png' });
    const storage = makeStorage(send);

    const result = await storage.get('k.png');

    expect(send.mock.calls[0][0]).toBeInstanceOf(GetObjectCommand);
    expect(result.body).toBe(fakeBody);
    expect(result.contentType).toBe('image/png');
  });

  it('delete sends a DeleteObjectCommand', async () => {
    const send = jest.fn().mockResolvedValue({});
    const storage = makeStorage(send);

    await storage.delete('k.jpg');

    const command = send.mock.calls[0][0];
    expect(command).toBeInstanceOf(DeleteObjectCommand);
    expect(command.input).toEqual({ Bucket: 'my-bucket', Key: 'k.jpg' });
  });
});
