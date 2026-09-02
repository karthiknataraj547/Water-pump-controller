import { prisma } from '../../config/database';
import { redis } from '../../config/redis';
import { mqttService } from '../mqtt/mqtt.service';
import { v4 as uuidv4 } from 'uuid';

export class DevicesService {
  async getDevicesByUser(userId: string) {
    const devices = await prisma.device.findMany({
      where: { userId },
      include: {
        settings: true,
        nodes: true,
        _count: {
          select: { alerts: { where: { isResolved: false } } },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Merge with latest live sensor metrics from Redis
    return await Promise.all(
      devices.map(async (dev) => {
        const liveSensorRaw = await redis.get(`device:${dev.id}:sensor`);
        const liveSensor = liveSensorRaw ? JSON.parse(liveSensorRaw) : null;
        return {
          ...dev,
          liveMetrics: liveSensor,
          unresolvedAlertCount: dev._count.alerts,
        };
      })
    );
  }

  async getDeviceById(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({
      where: { id: deviceId, userId },
      include: {
        settings: true,
        nodes: true,
        alerts: { where: { isResolved: false }, take: 5, orderBy: { createdAt: 'desc' } },
        rules: { where: { isEnabled: true } },
      },
    });

    if (!device) throw new Error('Device not found or unauthorized');

    const liveSensorRaw = await redis.get(`device:${deviceId}:sensor`);
    const liveStatusRaw = await redis.get(`device:${deviceId}:status`);

    return {
      ...device,
      liveSensor: liveSensorRaw ? JSON.parse(liveSensorRaw) : null,
      liveStatus: liveStatusRaw ? JSON.parse(liveStatusRaw) : null,
    };
  }

  async generateClaimToken(userId: string) {
    const token = `claim_${uuidv4().replace(/-/g, '').substring(0, 16)}`;
    // Store in Redis with 15 min TTL
    await redis.set(`claim_token:${token}`, userId, 900);
    return {
      claimToken: token,
      expiresInSeconds: 900,
    };
  }

  async claimDevice(userId: string, data: { deviceId: string; name: string; macAddress: string }) {
    const existing = await prisma.device.findUnique({ where: { id: data.deviceId } });
    if (existing && existing.userId !== userId) {
      throw new Error('Device is already claimed by another account');
    }

    const device = await prisma.device.upsert({
      where: { id: data.deviceId },
      update: {
        name: data.name,
        macAddress: data.macAddress,
        userId,
        status: 'ONLINE',
      },
      create: {
        id: data.deviceId,
        name: data.name,
        macAddress: data.macAddress,
        userId,
        status: 'ONLINE',
        pumpState: 'OFF',
        mode: 'AUTO',
        settings: {
          create: {
            autoStartLevelPct: 30.0,
            autoStopLevelPct: 90.0,
            maxContinuousRunMinutes: 45,
            dryRunTimeoutSeconds: 60,
            minFlowRateLpm: 2.0,
            tankHeightCm: 200.0,
            tankCapacityLiters: 5000.0,
          },
        },
      },
      include: { settings: true },
    });

    return device;
  }

  async updateSettings(userId: string, deviceId: string, settingsData: any) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found');

    const updated = await prisma.deviceSettings.upsert({
      where: { deviceId },
      update: settingsData,
      create: {
        deviceId,
        ...settingsData,
      },
    });

    // Synchronize new settings to ESP32 Gateway via MQTT
    await mqttService.syncConfig(userId, deviceId, updated);

    return updated;
  }

  async triggerChangeWifi(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found');

    return await mqttService.sendCommand(userId, deviceId, 'ENTER_PROVISIONING_MODE', {});
  }

  async deleteDevice(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found');

    await prisma.device.delete({ where: { id: deviceId } });
    return { success: true };
  }

  async getDeviceLiveStatus(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({
      where: { id: deviceId, userId },
      include: { settings: true },
    });

    if (!device) throw new Error('Device not found');

    const liveSensorRaw = await redis.get(`device:${deviceId}:sensor`);
    const liveStatusRaw = await redis.get(`device:${deviceId}:status`);

    const liveSensor = liveSensorRaw ? JSON.parse(liveSensorRaw) : null;
    const liveStatus = liveStatusRaw ? JSON.parse(liveStatusRaw) : null;

    const lastSeenTime = device.lastSeen ? new Date(device.lastSeen).getTime() : 0;
    const now = Date.now();
    const elapsedSeconds = Math.max(0, Math.floor((now - lastSeenTime) / 1000));

    // Strict 10-second hardware heartbeat threshold
    const isStrictlyOnline = elapsedSeconds <= 10 && device.status !== 'OFFLINE';

    return {
      deviceId: device.id,
      name: device.name,
      status: isStrictlyOnline ? 'ONLINE' : 'OFFLINE',
      isOnline: isStrictlyOnline,
      lastSeen: device.lastSeen,
      lastSeenSecondsAgo: elapsedSeconds,
      pumpState: liveStatus?.pump_state || device.pumpState,
      mode: liveStatus?.mode || device.mode,
      wifiRssi: liveStatus?.wifi_rssi || device.wifiRssi,
      firmwareVersion: liveStatus?.firmware_version || device.firmwareVersion,
      liveSensor,
      liveStatus,
    };
  }
}

export const devicesService = new DevicesService();
