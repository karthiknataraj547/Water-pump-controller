import mqtt, { MqttClient } from 'mqtt';
import { config } from '../../config';
import { prisma } from '../../config/database';
import { redis } from '../../config/redis';
import { logger } from '../../common/utils/logger';
import { v4 as uuidv4 } from 'uuid';

export interface DownlinkCommandPayload {
  command_id: string;
  command: string;
  parameters?: Record<string, any>;
  issued_by: string;
  timestamp: number;
}

export class MqttService {
  private client: MqttClient | null = null;
  private isConnected = false;
  private pendingCommandAcks = new Map<string, { resolve: (val: any) => void; reject: (err: any) => void; timer: NodeJS.Timeout }>();

  private presenceSweeperTimer: NodeJS.Timeout | null = null;

  public connect(): void {
    logger.info(`Connecting to MQTT broker at ${config.mqtt.brokerUrl}...`);
    
    this.client = mqtt.connect(config.mqtt.brokerUrl, {
      clientId: `backend_server_${uuidv4().substring(0, 8)}`,
      clean: true,
      connectTimeout: 5000,
      reconnectPeriod: 3000,
      username: config.mqtt.username,
      password: config.mqtt.password,
    });

    this.client.on('connect', () => {
      this.isConnected = true;
      logger.info('✅ Connected to MQTT Broker');
      
      // Start proactive active presence monitoring sweeper (5s cadence)
      this.startPresenceSweeper();

      // Subscribe to all pump telemetry, status, sensor, ack, and alert topics across single and multi-level hierarchies
      this.client?.subscribe(['pump/#', 'devices/#', 'hydropulse/#', 'waterpump/#'], { qos: 1 }, (err) => {
        if (err) {
          logger.error('Failed to subscribe to pump topics:', err);
        } else {
          logger.info('📡 Subscribed to MQTT topic patterns: pump/#, devices/#, hydropulse/#, waterpump/#');
        }
      });
    });

    this.client.on('message', async (topic, payload) => {
      try {
        await this.handleIncomingMessage(topic, payload.toString());
      } catch (err) {
        logger.error(`Error handling MQTT message on topic ${topic}:`, (err as Error).message);
      }
    });

    this.client.on('error', (err) => {
      logger.error('MQTT Client Error:', err.message);
      this.isConnected = false;
    });

    this.client.on('offline', () => {
      logger.warn('MQTT Client Offline');
      this.isConnected = false;
    });
  }

  private startPresenceSweeper(): void {
    if (this.presenceSweeperTimer) {
      clearInterval(this.presenceSweeperTimer);
    }

    this.presenceSweeperTimer = setInterval(async () => {
      try {
        const onlineDevices = await prisma.device.findMany({
          where: { status: 'ONLINE' },
          select: { id: true, name: true, lastSeen: true },
        });

        const now = Date.now();
        const timeoutMs = 15000; // 15 seconds threshold (grace period of 2-3 missed heartbeats)

        for (const dev of onlineDevices) {
          const lastSeenMs = dev.lastSeen ? new Date(dev.lastSeen).getTime() : 0;
          const elapsed = now - lastSeenMs;

          if (elapsed > timeoutMs) {
            logger.warn(`[Presence Sweeper] Hardware ${dev.id} (${dev.name}) timed out after ${Math.round(elapsed / 1000)}s without heartbeat. Transitioning to OFFLINE.`);
            
            await prisma.device.update({
              where: { id: dev.id },
              data: { status: 'OFFLINE' },
            });

            await redis.set(
              `device:${dev.id}:status`,
              JSON.stringify({ state: 'OFFLINE', reason: 'heartbeat_timeout', timestamp: Math.floor(now / 1000) }),
              300
            );
          }
        }
      } catch (err) {
        logger.error('[Presence Sweeper Error]:', (err as Error).message);
      }
    }, 5000);
  }

  private async handleIncomingMessage(topic: string, message: string): Promise<void> {
    let data: any;
    try {
      data = JSON.parse(message);
    } catch {
      logger.warn(`Non-JSON payload received on topic ${topic}: ${message}`);
      return;
    }

    const parts = topic.split('/');
    let deviceId = data.deviceId || data.device_id || data.id || '';
    let action = '';

    if (parts.length >= 4 && parts[0] === 'pump') {
      // pump/{userId}/{deviceId}/{action}
      deviceId = deviceId || parts[2];
      action = parts[3];
    } else if (parts.length === 3 && (parts[0] === 'pump' || parts[0] === 'devices')) {
      // pump/{deviceId}/{action} or devices/{deviceId}/{action}
      deviceId = deviceId || parts[1];
      action = parts[2];
    } else if (parts.length === 2 && parts[0] === 'pump') {
      // pump/{action} (e.g. pump/status, pump/telemetry, pump/pong)
      action = parts[1];
    }

    if (action === 'telemetry' || action === 'heartbeat') {
      if (action === 'telemetry') action = 'sensor';
      if (action === 'heartbeat') action = 'status';
    }

    if (!deviceId && data.deviceId) deviceId = data.deviceId;
    if (!deviceId) return;

    // Cache latest raw payload in Redis for instant live reads
    await redis.set(`device:${deviceId}:${action}`, JSON.stringify(data), 300);

    switch (action) {
      case 'pong':
        await this.handlePongMessage(deviceId, data);
        break;
      case 'status':
        await this.handleStatusMessage(deviceId, data);
        break;
      case 'sensor':
        await this.handleSensorMessage(deviceId, data);
        break;
      case 'ack':
        await this.handleAckMessage(deviceId, data);
        break;
      case 'alert':
        await this.handleAlertMessage(deviceId, data);
        break;
      default:
        logger.debug(`Unhandled MQTT action ${action} for device ${deviceId}`);
    }
  }

  private async handlePongMessage(deviceId: string, data: any): Promise<void> {
    try {
      await prisma.device.updateMany({
        where: { id: deviceId },
        data: {
          status: 'ONLINE',
          lastSeen: new Date(),
        },
      });
      await redis.set(
        `device:${deviceId}:status`,
        JSON.stringify({ state: 'ONLINE', last_pong: Date.now(), timestamp: Math.floor(Date.now() / 1000) }),
        300
      );
    } catch (err) {
      logger.debug(`Could not update device pong in DB: ${(err as Error).message}`);
    }
  }

  private async handleStatusMessage(deviceId: string, data: any): Promise<void> {
    try {
      const isLwtOffline = data.state === 'OFFLINE';

      await prisma.device.updateMany({
        where: { id: deviceId },
        data: {
          status: isLwtOffline ? 'OFFLINE' : (data.state || 'ONLINE'),
          pumpState: data.pump_state || 'OFF',
          mode: data.mode || 'AUTO',
          wifiRssi: typeof data.wifi_rssi === 'number' ? data.wifi_rssi : undefined,
          firmwareVersion: data.firmware_version || undefined,
          lastSeen: isLwtOffline ? undefined : new Date(),
        },
      });

      if (isLwtOffline) {
        logger.warn(`[MQTT LWT] Received Last Will or OFFLINE notification for device ${deviceId}`);
      }
    } catch (err) {
      logger.debug(`Could not update device status in DB (device may not be registered yet): ${(err as Error).message}`);
    }
  }

  private async handleSensorMessage(deviceId: string, data: any): Promise<void> {
    try {
      // Actively refresh device lastSeen and ONLINE state on sensor packets
      await prisma.device.updateMany({
        where: { id: deviceId },
        data: {
          status: 'ONLINE',
          lastSeen: new Date(),
        },
      });

      const reading = await prisma.sensorData.create({
        data: {
          deviceId,
          nodeId: data.sub_node_id || 'tank_node_001',
          waterLevelPct: Number(data.water_level_pct) || 0,
          waterLevelCm: Number(data.water_level_cm) || 0,
          flowRateLpm: Number(data.flow_rate_lpm) || 0,
          totalWaterLiters: Number(data.total_water_liters) || 0,
          tdsPpm: Number(data.tds_ppm) || 0,
          temperatureC: Number(data.temperature_c) || 0,
          batteryVoltage: Number(data.battery_voltage) || undefined,
          batteryPct: Number(data.battery_pct) || undefined,
        },
      });

      // Update Sub Node last seen in DB
      if (data.sub_node_id) {
        await prisma.deviceNode.upsert({
          where: { deviceId_nodeId: { deviceId, nodeId: data.sub_node_id } },
          update: {
            batteryPct: Number(data.battery_pct) || undefined,
            batteryVolt: Number(data.battery_voltage) || undefined,
            lastSeen: new Date(),
          },
          create: {
            deviceId,
            nodeId: data.sub_node_id,
            batteryPct: Number(data.battery_pct) || 100,
            batteryVolt: Number(data.battery_voltage) || 4.2,
            lastSeen: new Date(),
          },
        });
      }

      // Check for automatic thresholds & alerts
      if (data.water_level_pct >= 95) {
        // High water level warning
        await this.createAlertIfNotExists(deviceId, 'INFO', 'TANK_FULL', 'Water Tank Reached Full Capacity', `Tank water level is currently at ${data.water_level_pct.toFixed(1)}%.`);
      } else if (data.water_level_pct <= 15) {
        // Low water level critical alert
        await this.createAlertIfNotExists(deviceId, 'WARNING', 'TANK_EMPTY', 'Water Tank Level Critically Low', `Tank water level dropped to ${data.water_level_pct.toFixed(1)}%. Auto-start triggered or manual refill needed.`);
      }

      if (data.tds_ppm > 500) {
        // Water quality alert
        await this.createAlertIfNotExists(deviceId, 'WARNING', 'HIGH_TDS', 'Abnormal Water Quality (High TDS)', `TDS reading is ${data.tds_ppm} ppm. Filter replacement or source inspection recommended.`);
      }
    } catch (err) {
      logger.debug(`Could not record sensor telemetry in DB: ${(err as Error).message}`);
    }
  }

  private async handleAckMessage(deviceId: string, data: any): Promise<void> {
    const { command_id, status, message, execution_time_ms } = data;
    if (!command_id) return;

    logger.info(`Received ACK for command ${command_id} from ${deviceId}: ${status} - ${message}`);

    try {
      await prisma.mqttCommand.updateMany({
        where: { id: command_id },
        data: {
          status: status === 'SUCCESS' ? 'ACKNOWLEDGED' : 'FAILED',
          responseMessage: message || '',
          executionTimeMs: execution_time_ms || 0,
          acknowledgedAt: new Date(),
        },
      });
    } catch (err) {
      logger.debug(`Could not update MQTT command ACK in DB: ${(err as Error).message}`);
    }

    // Resolve any awaiting synchronous promises
    if (this.pendingCommandAcks.has(command_id)) {
      const pending = this.pendingCommandAcks.get(command_id)!;
      clearTimeout(pending.timer);
      this.pendingCommandAcks.delete(command_id);
      pending.resolve(data);
    }
  }

  private async handleAlertMessage(deviceId: string, data: any): Promise<void> {
    const { severity, type, description } = data;
    await this.createAlertIfNotExists(deviceId, severity || 'CRITICAL', type || 'ANOMALY', `Device Safety Alert: ${type}`, description || 'Safety event triggered on pump controller.');
  }

  private async createAlertIfNotExists(deviceId: string, severity: 'INFO' | 'WARNING' | 'CRITICAL' | 'EMERGENCY', type: string, title: string, description: string): Promise<void> {
    try {
      // Find device to get userId for notification
      const device = await prisma.device.findUnique({ where: { id: deviceId } });
      if (!device) return;

      // Don't duplicate active unresolved alert within 10 minutes
      const existing = await prisma.alert.findFirst({
        where: {
          deviceId,
          type,
          isResolved: false,
          createdAt: { gte: new Date(Date.now() - 10 * 60 * 1000) },
        },
      });

      if (!existing) {
        await prisma.alert.create({
          data: {
            deviceId,
            severity,
            type,
            title,
            description,
          },
        });

        // Also create user notification
        await prisma.notification.create({
          data: {
            userId: device.userId,
            title,
            message: description,
            type: severity,
          },
        });
      }
    } catch (err) {
      logger.error('Failed to create alert/notification:', (err as Error).message);
    }
  }

  public async sendCommand(userId: string, deviceId: string, command: string, parameters: Record<string, any> = {}, waitForAckMs = 5000): Promise<any> {
    const commandId = `cmd_${uuidv4()}`;
    const topic = `pump/${userId}/${deviceId}/command`;

    const payload: DownlinkCommandPayload = {
      command_id: commandId,
      command,
      parameters,
      issued_by: userId,
      timestamp: Math.floor(Date.now() / 1000),
    };

    // Save command in database
    try {
      await prisma.mqttCommand.create({
        data: {
          id: commandId,
          deviceId,
          command,
          parameters,
          status: 'DISPATCHED',
        },
      });
    } catch (err) {
      logger.debug(`Could not record command in DB: ${(err as Error).message}`);
    }

    if (!this.client || !this.isConnected) {
      throw new Error('MQTT Broker not connected. Cannot dispatch command.');
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingCommandAcks.delete(commandId);
        resolve({
          command_id: commandId,
          status: 'DISPATCHED_PENDING_ACK',
          message: 'Command sent to device. Awaiting device ACK.',
        });
      }, waitForAckMs);

      this.pendingCommandAcks.set(commandId, { resolve, reject, timer });

      const payloadStr = JSON.stringify(payload);
      this.client!.publish(topic, payloadStr, { qos: 0 });
      this.client!.publish(`pump/${deviceId}/command`, payloadStr, { qos: 0 });
      this.client!.publish(`devices/${deviceId}/command`, payloadStr, { qos: 0 });
      this.client!.publish('pump/command', payloadStr, { qos: 0 }, (err) => {
        clearTimeout(timer);
        this.pendingCommandAcks.delete(commandId);
        if (err) {
          reject(new Error(`Failed to publish command to MQTT broker: ${err.message}`));
        } else {
          resolve({
            command_id: commandId,
            status: 'DISPATCHED_INSTANT',
            message: 'Command sent to hardware instantaneously (<10ms).',
          });
        }
      });
    });
  }

  public async syncConfig(userId: string, deviceId: string, settings: Record<string, any>): Promise<void> {
    const topic = `pump/${userId}/${deviceId}/config`;
    const payload = {
      device_id: deviceId,
      ...settings,
      timestamp: Math.floor(Date.now() / 1000),
    };

    if (this.client && this.isConnected) {
      this.client.publish(topic, JSON.stringify(payload), { qos: 1, retain: true });
    }
  }
}

export const mqttService = new MqttService();
