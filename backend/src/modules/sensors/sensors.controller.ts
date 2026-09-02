import { Router, Response, NextFunction } from 'express';
import { sensorsService } from './sensors.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';

const router = Router();

router.get('/:deviceId/live', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const live = await sensorsService.getLiveTelemetry(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: live });
  } catch (error) {
    next(error);
  }
});

router.get('/:deviceId/history', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const hours = req.query.hours ? parseInt(req.query.hours as string, 10) : 24;
    const history = await sensorsService.getTelemetryHistory(req.user!.userId, req.params.deviceId, hours);
    res.status(200).json({ status: 'success', data: history });
  } catch (error) {
    next(error);
  }
});

export default router;
