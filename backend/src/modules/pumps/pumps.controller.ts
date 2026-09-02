import { Router, Response, NextFunction } from 'express';
import { pumpsService } from './pumps.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';
import { z } from 'zod';

const router = Router();

const commandSchema = z.object({
  command: z.enum(['PUMP_ON', 'PUMP_OFF', 'EMERGENCY_STOP', 'SET_MODE', 'RESTART_DEVICE', 'FACTORY_RESET']),
  parameters: z.record(z.any()).optional().default({}),
});

router.post('/:deviceId/command', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const validated = commandSchema.parse(req.body);
    const result = await pumpsService.executePumpCommand(
      req.user!.userId,
      req.params.deviceId,
      validated.command,
      validated.parameters
    );
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

router.get('/:deviceId/history', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const limit = req.query.limit ? parseInt(req.query.limit as string, 10) : 50;
    const history = await pumpsService.getPumpHistory(req.user!.userId, req.params.deviceId, limit);
    res.status(200).json({ status: 'success', data: history });
  } catch (error) {
    next(error);
  }
});

export default router;
