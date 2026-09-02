import { prisma } from '../../config/database';

export class AlertsService {
  async getAlerts(userId: string, isResolved?: boolean) {
    const devices = await prisma.device.findMany({
      where: { userId },
      select: { id: true },
    });

    const deviceIds = devices.map((d) => d.id);

    return await prisma.alert.findMany({
      where: {
        deviceId: { in: deviceIds },
        ...(typeof isResolved === 'boolean' ? { isResolved } : {}),
      },
      include: { device: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  async resolveAlert(userId: string, alertId: string) {
    const alert = await prisma.alert.findUnique({
      where: { id: alertId },
      include: { device: true },
    });

    if (!alert || alert.device.userId !== userId) {
      throw new Error('Alert not found or unauthorized');
    }

    return await prisma.alert.update({
      where: { id: alertId },
      data: {
        isResolved: true,
        resolvedAt: new Date(),
      },
    });
  }

  async getNotifications(userId: string, isRead?: boolean) {
    return await prisma.notification.findMany({
      where: {
        userId,
        ...(typeof isRead === 'boolean' ? { isRead } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }

  async markNotificationRead(userId: string, notificationId: string) {
    return await prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { isRead: true },
    });
  }

  async markAllNotificationsRead(userId: string) {
    return await prisma.notification.updateMany({
      where: { userId },
      data: { isRead: true },
    });
  }
}

export const alertsService = new AlertsService();
