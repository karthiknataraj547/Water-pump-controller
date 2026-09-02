import { prisma } from '../../config/database';
import { mqttService } from '../mqtt/mqtt.service';

export class AutomationService {
  async getRulesByDevice(userId: string, deviceId: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    return await prisma.automationRule.findMany({
      where: { deviceId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async createRule(userId: string, deviceId: string, data: any) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    const rule = await prisma.automationRule.create({
      data: {
        deviceId,
        name: data.name,
        isEnabled: data.isEnabled ?? true,
        conditionType: data.conditionType,
        conditionValue: data.conditionValue,
        actionType: data.actionType,
        autoStopLevelPct: data.autoStopLevelPct ?? 90.0,
        maxRunMinutes: data.maxRunMinutes ?? 30,
      },
    });

    // Synchronize automation config to ESP32 Gateway
    await this.syncRulesToDevice(userId, deviceId);

    return rule;
  }

  async updateRule(userId: string, deviceId: string, ruleId: string, data: any) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    const updated = await prisma.automationRule.update({
      where: { id: ruleId },
      data,
    });

    await this.syncRulesToDevice(userId, deviceId);
    return updated;
  }

  async deleteRule(userId: string, deviceId: string, ruleId: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    await prisma.automationRule.delete({ where: { id: ruleId } });
    await this.syncRulesToDevice(userId, deviceId);
    return { success: true };
  }

  private async syncRulesToDevice(userId: string, deviceId: string) {
    const activeRules = await prisma.automationRule.findMany({
      where: { deviceId, isEnabled: true },
    });

    await mqttService.syncConfig(userId, deviceId, {
      rules: activeRules.map((r) => ({
        id: r.id,
        cond_type: r.conditionType,
        cond_val: r.conditionValue,
        action: r.actionType,
        auto_stop_level: r.autoStopLevelPct,
        max_run_mins: r.maxRunMinutes,
      })),
    });
  }
}

export const automationService = new AutomationService();
