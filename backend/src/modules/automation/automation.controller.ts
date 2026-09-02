import { Router, Response, NextFunction } from 'express';
import { automationService } from './automation.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';
import { z } from 'zod';

const router = Router();

const ruleSchema = z.object({
  name: z.string().min(1),
  isEnabled: z.boolean().optional().default(true),
  conditionType: z.enum(['WATER_LEVEL_BELOW', 'WATER_LEVEL_ABOVE', 'SCHEDULE_TIME']),
  conditionValue: z.number(),
  actionType: z.enum(['START_PUMP', 'STOP_PUMP']),
  autoStopLevelPct: z.number().min(20).max(100).optional(),
  maxRunMinutes: z.number().min(1).max(180).optional(),
});

router.get('/:deviceId/rules', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const rules = await automationService.getRulesByDevice(req.user!.userId, req.params.deviceId);
    res.status(200).json({ status: 'success', data: rules });
  } catch (error) {
    next(error);
  }
});

router.post('/:deviceId/rules', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const validated = ruleSchema.parse(req.body);
    const rule = await automationService.createRule(req.user!.userId, req.params.deviceId, validated);
    res.status(201).json({ status: 'success', data: rule });
  } catch (error) {
    next(error);
  }
});

router.put('/:deviceId/rules/:ruleId', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const updated = await automationService.updateRule(req.user!.userId, req.params.deviceId, req.params.ruleId, req.body);
    res.status(200).json({ status: 'success', data: updated });
  } catch (error) {
    next(error);
  }
});

router.delete('/:deviceId/rules/:ruleId', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const result = await automationService.deleteRule(req.user!.userId, req.params.deviceId, req.params.ruleId);
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

export default router;
