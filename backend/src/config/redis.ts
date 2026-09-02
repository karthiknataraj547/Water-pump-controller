import Redis from 'ioredis';
import { config } from './index';

class RedisService {
  private client: Redis | null = null;
  private memoryCache = new Map<string, string>();
  public isConnected = false;

  constructor() {
    try {
      this.client = new Redis({
        host: config.redis.host,
        port: config.redis.port,
        password: config.redis.password,
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        retryStrategy: () => null, // don't loop endlessly if redis is not running locally
      });

      this.client.on('connect', () => {
        this.isConnected = true;
        console.log('✅ Redis connected successfully');
      });

      this.client.on('error', (err) => {
        this.isConnected = false;
        // Silent fallback to in-memory cache
      });
    } catch {
      this.isConnected = false;
    }
  }

  public async connect(): Promise<void> {
    if (this.client) {
      try {
        await this.client.connect();
      } catch {
        console.log('ℹ️ Redis not available, using in-memory state store');
      }
    }
  }

  public async get(key: string): Promise<string | null> {
    if (this.isConnected && this.client) {
      try {
        return await this.client.get(key);
      } catch {
        return this.memoryCache.get(key) || null;
      }
    }
    return this.memoryCache.get(key) || null;
  }

  public async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (this.isConnected && this.client) {
      try {
        if (ttlSeconds) {
          await this.client.setex(key, ttlSeconds, value);
        } else {
          await this.client.set(key, value);
        }
        return;
      } catch {
        // fallback
      }
    }
    this.memoryCache.set(key, value);
  }

  public async del(key: string): Promise<void> {
    if (this.isConnected && this.client) {
      try {
        await this.client.del(key);
      } catch {
        // fallback
      }
    }
    this.memoryCache.delete(key);
  }
}

export const redis = new RedisService();
