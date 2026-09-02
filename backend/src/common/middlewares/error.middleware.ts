import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { logger } from '../utils/logger';

export function errorHandler(err: Error, req: Request, res: Response, next: NextFunction): void {
  logger.error(`Unhandled Error: ${err.message}`, { stack: err.stack, path: req.path });

  if (err instanceof ZodError) {
    res.status(400).json({
      status: 'error',
      message: 'Validation failed',
      errors: err.errors.map((e) => ({ field: e.path.join('.'), message: e.message })),
    });
    return;
  }

  res.status(500).json({
    status: 'error',
    message: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
}
