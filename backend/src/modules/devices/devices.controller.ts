import { Router, Response, NextFunction } from 'express';
import { devicesService } from './devices.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';
import { z } from 'zod';

const router = Router();

const claimSchema = z.object({
  deviceId: z.string().min(1),
  name: z.string().min(1),
  macAddress: z.string().min(12),
});

const settingsSchema = z.object({
  autoStartLevelPct: z.number().min(5).max(90).optional(),
  autoStopLevelPct: z.number().min(20).max(100).optional(),
  maxContinuousRunMinutes: z.number().min(1).max(180).optional(),
  dryRunTimeoutSeconds: z.number().min(10).max(300).optional(),
  minFlowRateLpm: z.number().min(0).max(50).optional(),
  tankHeightCm: z.number().min(20).max(2000).optional(),
  tankCapacityLiters: z.number().min(50).max(100000).optional(),
  telemetryIntervalSec: z.number().min(1).max(60).optional(),
});

router.get('/', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const devices = await devicesService.getDevicesByUser(req.user!.userId);
    res.status(200).json({ status: 'success', data: devices });
  } catch (error) {
    next(error);
  }
});

router.get('/claim-token', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const tokenData = await devicesService.generateClaimToken(req.user!.userId);
    res.status(200).json({ status: 'success', data: tokenData });
  } catch (error) {
    next(error);
  }
});

router.post('/claim', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const validated = claimSchema.parse(req.body);
    const device = await devicesService.claimDevice(req.user!.userId, validated);
    res.status(201).json({ status: 'success', data: device });
  } catch (error) {
    next(error);
  }
});

router.get('/:deviceId/live-status', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const liveStatus = await devicesService.getDeviceLiveStatus(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: liveStatus });
  } catch (error) {
    next(error);
  }
});

router.get('/:deviceId', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const device = await devicesService.getDeviceById(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: device });
  } catch (error) {
    next(error);
  }
});

router.put('/:deviceId/settings', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const validated = settingsSchema.parse(req.body);
    const updated = await devicesService.updateSettings(req.user!.userId, req.params.deviceId, validated);
    res.status(200).json({ status: 'success', data: updated });
  } catch (error) {
    next(error);
  }
});

router.post('/:deviceId/change-wifi', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const result = await devicesService.triggerChangeWifi(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

router.delete('/:deviceId', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const result = await devicesService.deleteDevice(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

export default router;
