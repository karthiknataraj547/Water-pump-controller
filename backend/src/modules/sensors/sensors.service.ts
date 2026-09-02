import { prisma } from '../../config/database';
import { redis } from '../../config/redis';

export class SensorsService {
  async getLiveTelemetry(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    const liveDataRaw = await redis.get(`device:${deviceId}:sensor`);
    if (liveDataRaw) {
      return JSON.parse(liveDataRaw);
    }

    // Fallback to latest database record
    return await prisma.sensorData.findFirst({
      where: { deviceId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getTelemetryHistory(userId: string, deviceId: string, hours = 24) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
    return await prisma.sensorData.findMany({
      where: {
        deviceId,
        createdAt: { gte: cutoff },
      },
      orderBy: { createdAt: 'asc' },
      take: 1000,
    });
  }
}

export const sensorsService = new SensorsService();
