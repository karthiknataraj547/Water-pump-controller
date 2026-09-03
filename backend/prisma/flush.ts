import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function flushDatabase() {
  console.log('🧹 [HydroPulse] Flushing all database accounts, devices, and telemetry...');

  try {
    // Delete in order to ensure clean cascade
    const deletedSensorData = await prisma.sensorData.deleteMany();
    const deletedPumpEvents = await prisma.pumpEvent.deleteMany();
    const deletedAlerts = await prisma.alert.deleteMany();
    const deletedCommands = await prisma.mqttCommand.deleteMany();
    const deletedLogs = await prisma.deviceLog.deleteMany();
    const deletedRules = await prisma.automationRule.deleteMany();
    const deletedNodes = await prisma.deviceNode.deleteMany();
    const deletedSettings = await prisma.deviceSettings.deleteMany();
    const deletedNotifications = await prisma.notification.deleteMany();
    const deletedDevices = await prisma.device.deleteMany();
    const deletedUsers = await prisma.user.deleteMany();

    console.log('✅ [HydroPulse] Database successfully flushed:');
    console.log(`   - Users Deleted: ${deletedUsers.count}`);
    console.log(`   - Devices Deleted: ${deletedDevices.count}`);
    console.log(`   - Device Nodes Deleted: ${deletedNodes.count}`);
    console.log(`   - Sensor Data Records Deleted: ${deletedSensorData.count}`);
    console.log(`   - Pump Events Deleted: ${deletedPumpEvents.count}`);
    console.log(`   - Alerts Cleared: ${deletedAlerts.count}`);
    console.log(`   - MQTT Commands Cleared: ${deletedCommands.count}`);
    console.log(`   - Notifications Cleared: ${deletedNotifications.count}`);
    console.log('✨ All tables are now clean and empty.');
  } catch (error) {
    console.error('⚠️ [HydroPulse] Flush encountered an error (or DB was not running):', error);
  } finally {
    await prisma.$disconnect();
  }
}

flushDatabase();
