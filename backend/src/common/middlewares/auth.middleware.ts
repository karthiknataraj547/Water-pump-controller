import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken, JwtPayload } from '../utils/jwt.util';

export interface AuthenticatedRequest extends Request {
  user?: JwtPayload;
}

export function authenticate(req: AuthenticatedRequest, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ status: 'error', message: 'Authentication required. Missing or malformed token.' });
    return;
  }

  const token = authHeader.split(' ')[1];
  try {
    const payload = verifyAccessToken(token);
    req.user = payload;
    next();
  } catch (error) {
    res.status(401).json({ status: 'error', message: 'Invalid or expired access token.' });
  }
}

export function authorizeRoles(...allowedRoles: string[]) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction): void => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      res.status(403).json({ status: 'error', message: 'Forbidden: Insufficient privileges.' });
      return;
    }
    next();
  };
}
