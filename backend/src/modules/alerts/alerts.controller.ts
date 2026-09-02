import { Router, Response, NextFunction } from 'express';
import { alertsService } from './alerts.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';

const router = Router();

router.get('/', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const isResolved = req.query.resolved !== undefined ? req.query.resolved === 'true' : undefined;
    const alerts = await alertsService.getAlerts(req.user!.userId, isResolved);
    res.status(200).json({ status: 'success', data: alerts });
  } catch (error) {
    next(error);
  }
});

router.put('/:alertId/resolve', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const alert = await alertsService.resolveAlert(req.user!.userId, req.params.alertId);
    res.status(200).json({ status: 'success', data: alert });
  } catch (error) {
    next(error);
  }
});

router.get('/notifications', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const isRead = req.query.isRead !== undefined ? req.query.isRead === 'true' : undefined;
    const notifications = await alertsService.getNotifications(req.user!.userId, isRead);
    res.status(200).json({ status: 'success', data: notifications });
  } catch (error) {
    next(error);
  }
});

router.put('/notifications/:notificationId/read', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    await alertsService.markNotificationRead(req.user!.userId, req.params.notificationId);
    res.status(200).json({ status: 'success', message: 'Notification marked as read' });
  } catch (error) {
    next(error);
  }
});

router.put('/notifications/mark-all-read', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    await alertsService.markAllNotificationsRead(req.user!.userId);
    res.status(200).json({ status: 'success', message: 'All notifications marked as read' });
  } catch (error) {
    next(error);
  }
});

export default router;
