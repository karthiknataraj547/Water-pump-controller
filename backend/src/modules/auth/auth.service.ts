import bcrypt from 'bcryptjs';
import { prisma } from '../../config/database';
import { generateAccessToken, generateRefreshToken, verifyRefreshToken } from '../../common/utils/jwt.util';
import { z } from 'zod';

export const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8, 'Password must be at least 8 characters long'),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  role: z.enum(['ADMIN', 'USER', 'TECHNICIAN']).optional(),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

export const googleAuthSchema = z.object({
  email: z.string().email(),
  firstName: z.string().optional().default('Google'),
  lastName: z.string().optional().default('User'),
  googleId: z.string().optional(),
  idToken: z.string().optional(),
});

export class AuthService {
  async register(data: z.infer<typeof registerSchema>) {
    const existing = await prisma.user.findUnique({ where: { email: data.email } });
    if (existing) {
      throw new Error('An account with this email address already exists');
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(data.password, salt);

    const user = await prisma.user.create({
      data: {
        email: data.email,
        passwordHash,
        firstName: data.firstName,
        lastName: data.lastName,
        role: data.role || 'USER',
      },
      select: { id: true, email: true, firstName: true, lastName: true, role: true, createdAt: true },
    });

    const tokens = this.generateUserTokens(user);
    await prisma.user.update({ where: { id: user.id }, data: { refreshToken: tokens.refreshToken } });

    return { user, tokens };
  }

  async googleLogin(data: z.infer<typeof googleAuthSchema>) {
    let user = await prisma.user.findUnique({ where: { email: data.email } });
    if (!user) {
      const salt = await bcrypt.genSalt(10);
      const passwordHash = await bcrypt.hash(`google_oauth_${Date.now()}`, salt);
      user = await prisma.user.create({
        data: {
          email: data.email,
          passwordHash,
          firstName: data.firstName || 'Google',
          lastName: data.lastName || 'User',
          role: 'USER',
        },
      });
    }

    const tokens = this.generateUserTokens(user);
    await prisma.user.update({ where: { id: user.id }, data: { refreshToken: tokens.refreshToken } });

    return {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
      },
      tokens,
    };
  }

  async login(data: z.infer<typeof loginSchema>) {
    const user = await prisma.user.findUnique({ where: { email: data.email } });
    if (!user) {
      throw new Error('Invalid email or password');
    }

    const isMatch = await bcrypt.compare(data.password, user.passwordHash);
    if (!isMatch) {
      throw new Error('Invalid email or password');
    }

    const tokens = this.generateUserTokens(user);
    await prisma.user.update({ where: { id: user.id }, data: { refreshToken: tokens.refreshToken } });

    return {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
      },
      tokens,
    };
  }

  async refreshTokens(refreshToken: string) {
    const payload = verifyRefreshToken(refreshToken);
    const user = await prisma.user.findUnique({ where: { id: payload.userId } });

    if (!user || user.refreshToken !== refreshToken) {
      throw new Error('Invalid or revoked refresh token');
    }

    const tokens = this.generateUserTokens(user);
    await prisma.user.update({ where: { id: user.id }, data: { refreshToken: tokens.refreshToken } });

    return tokens;
  }

  async getProfile(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, firstName: true, lastName: true, role: true, createdAt: true },
    });
    if (!user) throw new Error('User not found');
    return user;
  }

  private generateUserTokens(user: { id: string; email: string; role: string }) {
    const payload = { userId: user.id, email: user.email, role: user.role };
    return {
      accessToken: generateAccessToken(payload),
      refreshToken: generateRefreshToken(payload),
      tokenType: 'Bearer',
    };
  }
}

export const authService = new AuthService();
