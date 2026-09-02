import { prisma } from '../../config/database';
import { mqttService } from '../mqtt/mqtt.service';

export class PumpsService {
  async executePumpCommand(userId: string, deviceId: string, command: string, parameters: Record<string, any> = {}) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    // Dispatch command through MQTT with device acknowledgment tracking
    const ackResponse = await mqttService.sendCommand(userId, deviceId, command, parameters);

    // Record pump event if state change
    if (command === 'PUMP_ON') {
      await prisma.pumpEvent.create({
        data: {
          deviceId,
          eventType: 'START',
          triggeredBy: parameters.triggeredBy || 'MANUAL_APP',
          status: 'RUNNING',
        },
      });
      await prisma.device.update({
        where: { id: deviceId },
        data: { pumpState: 'ON' },
      });
    } else if (command === 'PUMP_OFF' || command === 'EMERGENCY_STOP') {
      // Find open pump event to calculate duration
      const latestStart = await prisma.pumpEvent.findFirst({
        where: { deviceId, status: 'RUNNING' },
        orderBy: { createdAt: 'desc' },
      });

      const durationSeconds = latestStart
        ? Math.floor((Date.now() - new Date(latestStart.createdAt).getTime()) / 1000)
        : 0;

      if (latestStart) {
        await prisma.pumpEvent.update({
          where: { id: latestStart.id },
          data: {
            durationSeconds,
            status: command === 'EMERGENCY_STOP' ? 'EMERGENCY_ABORTED' : 'COMPLETED',
          },
        });
      }

      await prisma.device.update({
        where: { id: deviceId },
        data: { pumpState: command === 'EMERGENCY_STOP' ? 'EMERGENCY_STOP' : 'OFF' },
      });
    } else if (command === 'SET_MODE') {
      const mode = parameters.mode || 'AUTO';
      await prisma.device.update({
        where: { id: deviceId },
        data: { mode },
      });
    }

    return ackResponse;
  }

  async getPumpHistory(userId: string, deviceId: string, limit = 50) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    return await prisma.pumpEvent.findMany({
      where: { deviceId },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }
}

export const pumpsService = new PumpsService();
