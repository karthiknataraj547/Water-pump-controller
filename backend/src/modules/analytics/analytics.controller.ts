import { Router, Response, NextFunction } from 'express';
import { analyticsService } from './analytics.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';

const router = Router();

router.get('/:deviceId', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const range = (req.query.range as any) || 'today';
    const startDate = req.query.start_date as string | undefined;
    const endDate = req.query.end_date as string | undefined;

    const data = await analyticsService.getDeviceAnalytics(
      req.user!.userId,
      req.params.deviceId,
      range,
      startDate,
      endDate
    );
    res.status(200).json({ status: 'success', data });
  } catch (error) {
    next(error);
  }
});

export default router;
