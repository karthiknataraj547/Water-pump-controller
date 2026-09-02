import { prisma } from '../../config/database';

export class AnalyticsService {
  async getDeviceAnalytics(userId: string, deviceId: string, range: 'today' | 'week' | 'month' | 'custom' = 'today', startDateStr?: string, endDateStr?: string) {
    const device = await prisma.device.findFirst({ where: { id: deviceId, userId } });
    if (!device) throw new Error('Device not found or unauthorized');

    let startDate: Date;
    const endDate = endDateStr ? new Date(endDateStr) : new Date();

    const now = new Date();
    if (range === 'today') {
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
    } else if (range === 'week') {
      startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    } else if (range === 'month') {
      startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    } else if (startDateStr) {
      startDate = new Date(startDateStr);
    } else {
      startDate = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    }

    // Query pump events in timeframe
    const pumpEvents = await prisma.pumpEvent.findMany({
      where: {
        deviceId,
        createdAt: { gte: startDate, lte: endDate },
      },
      orderBy: { createdAt: 'asc' },
    });

    const totalCycles = pumpEvents.length;
    let totalRuntimeSeconds = 0;
    let totalVolumeLiters = 0;

    for (const ev of pumpEvents) {
      totalRuntimeSeconds += ev.durationSeconds || 0;
      totalVolumeLiters += ev.volumePumpedLiters || 0;
    }

    // Default: 1.5 HP motor ~ 1.1 kW
    const estimatedKWh = ((totalRuntimeSeconds / 3600) * 1.1).toFixed(2);

    // Grouping for time-series charts
    const timeSeriesData = this.groupTimeSeries(pumpEvents, range, startDate, endDate);

    return {
      deviceId,
      range,
      startDate,
      endDate,
      summary: {
        totalRuntimeMinutes: Math.round(totalRuntimeSeconds / 60),
        totalRuntimeHours: Number((totalRuntimeSeconds / 3600).toFixed(2)),
        totalVolumePumpedLiters: Math.round(totalVolumeLiters),
        totalVolumeCubicMeters: Number((totalVolumeLiters / 1000).toFixed(2)),
        totalPumpCycles: totalCycles,
        estimatedEnergyKWh: parseFloat(estimatedKWh),
        avgFlowRateLpm: totalRuntimeSeconds > 0 ? Number(((totalVolumeLiters / (totalRuntimeSeconds / 60))).toFixed(1)) : 0,
      },
      timeSeries: timeSeriesData,
    };
  }

  private groupTimeSeries(events: any[], range: string, start: Date, end: Date) {
    const buckets: Record<string, { label: string; runtimeMins: number; volumeLiters: number; cycles: number }> = {};

    if (range === 'today') {
      // 24 hourly buckets
      for (let h = 0; h < 24; h++) {
        const key = `${h.toString().padStart(2, '0')}:00`;
        buckets[key] = { label: key, runtimeMins: 0, volumeLiters: 0, cycles: 0 };
      }

      for (const ev of events) {
        const hour = new Date(ev.createdAt).getHours();
        const key = `${hour.toString().padStart(2, '0')}:00`;
        if (buckets[key]) {
          buckets[key].runtimeMins += Math.round((ev.durationSeconds || 0) / 60);
          buckets[key].volumeLiters += Math.round(ev.volumePumpedLiters || 0);
          buckets[key].cycles += 1;
        }
      }
    } else {
      // Daily buckets for week or month
      const daysCount = Math.ceil((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));
      for (let i = 0; i <= Math.min(daysCount, 31); i++) {
        const d = new Date(start.getTime() + i * 24 * 60 * 60 * 1000);
        const key = d.toISOString().split('T')[0];
        buckets[key] = { label: key, runtimeMins: 0, volumeLiters: 0, cycles: 0 };
      }

      for (const ev of events) {
        const key = new Date(ev.createdAt).toISOString().split('T')[0];
        if (buckets[key]) {
          buckets[key].runtimeMins += Math.round((ev.durationSeconds || 0) / 60);
          buckets[key].volumeLiters += Math.round(ev.volumePumpedLiters || 0);
          buckets[key].cycles += 1;
        }
      }
    }

    return Object.values(buckets);
  }
}

export const analyticsService = new AnalyticsService();
