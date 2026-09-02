import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding IoT Water Pump Database...');

  // 1. Create Admin & Demo User
  const salt = await bcrypt.genSalt(10);
  const passwordHash = await bcrypt.hash('AdminPassword123!', salt);

  const demoUser = await prisma.user.upsert({
    where: { email: 'admin@waterpump.io' },
    update: {},
    create: {
      id: 'usr_demo_001',
      email: 'admin@waterpump.io',
      passwordHash,
      firstName: 'Karthik',
      lastName: 'N',
      role: 'ADMIN',
    },
  });

  console.log(`👤 User created: ${demoUser.email} (ID: ${demoUser.id})`);

  // 2. Create Demo ESP32 Gateway Device
  const device = await prisma.device.upsert({
    where: { id: 'esp32_pump_94B97E' },
    update: {},
    create: {
      id: 'esp32_pump_94B97E',
      name: 'Main Agricultural Pump',
      macAddress: '24:6F:28:94:B9:7E',
      userId: demoUser.id,
      status: 'ONLINE',
      pumpState: 'OFF',
      mode: 'AUTO',
      wifiRssi: -58,
      firmwareVersion: '1.0.0',
      ipAddress: '192.168.1.105',
      settings: {
        create: {
          autoStartLevelPct: 30.0,
          autoStopLevelPct: 90.0,
          maxContinuousRunMinutes: 45,
          dryRunTimeoutSeconds: 60,
          minFlowRateLpm: 2.0,
          tankHeightCm: 200.0,
          tankCapacityLiters: 5000.0,
          telemetryIntervalSec: 5,
        },
      },
      nodes: {
        create: {
          nodeId: 'tank_node_001',
          name: 'Overhead Tank Sensor',
          nodeType: 'ESP8266_TANK_SENSOR',
          isActive: true,
          batteryPct: 95,
          batteryVolt: 4.12,
        },
      },
      rules: {
        create: [
          {
            name: 'Auto Tank Refill',
            isEnabled: true,
            conditionType: 'WATER_LEVEL_BELOW',
            conditionValue: 30.0,
            actionType: 'START_PUMP',
            autoStopLevelPct: 90.0,
            maxRunMinutes: 30,
          },
        ],
      },
    },
  });

  console.log(`🔌 Device seeded: ${device.name} (ID: ${device.id})`);
  console.log('✅ Seeding completed successfully!');
}

main()
  .catch((e) => {
    console.error('Error during seeding:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
