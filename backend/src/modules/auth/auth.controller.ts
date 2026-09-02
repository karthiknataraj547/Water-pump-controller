import { Router, Request, Response, NextFunction } from 'express';
import { authService, registerSchema, loginSchema, googleAuthSchema } from './auth.service';
import { authenticate, AuthenticatedRequest } from '../../common/middlewares/auth.middleware';

const router = Router();

router.post('/register', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const validated = registerSchema.parse(req.body);
    const result = await authService.register(validated);
    res.status(201).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

router.post('/login', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const validated = loginSchema.parse(req.body);
    const result = await authService.login(validated);
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

router.post('/google', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const validated = googleAuthSchema.parse(req.body);
    const result = await authService.googleLogin(validated);
    res.status(200).json({ status: 'success', data: result });
  } catch (error) {
    next(error);
  }
});

router.post('/refresh', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token) {
      res.status(400).json({ status: 'error', message: 'Missing refresh_token in request body' });
      return;
    }
    const tokens = await authService.refreshTokens(refresh_token);
    res.status(200).json({ status: 'success', data: tokens });
  } catch (error) {
    res.status(401).json({ status: 'error', message: (error as Error).message });
  }
});

router.get('/profile', authenticate, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const user = await authService.getProfile(req.user!.userId);
    res.status(200).json({ status: 'success', data: user });
  } catch (error) {
    next(error);
  }
});

export default router;
