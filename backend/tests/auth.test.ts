import request from 'supertest';
import { app } from '../src/server';

describe('Auth Endpoints', () => {
  const testEmail = `test_${Date.now()}@waterpump.io`;
  let accessToken = '';

  it('should register a new user successfully', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({
        email: testEmail,
        password: 'Password123!',
        firstName: 'Test',
        lastName: 'User',
      });

    expect(res.status).toBe(201);
    expect(res.body.status).toBe('success');
    expect(res.body.data.user.email).toBe(testEmail);
    expect(res.body.data.tokens.accessToken).toBeDefined();
    accessToken = res.body.data.tokens.accessToken;
  });

  it('should login with valid credentials', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email: testEmail,
        password: 'Password123!',
      });

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('success');
    expect(res.body.data.tokens.accessToken).toBeDefined();
  });

  it('should reject login with wrong password', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email: testEmail,
        password: 'WrongPassword!',
      });

    expect(res.status).toBe(500);
  });

  it('should retrieve current user profile with valid JWT token', async () => {
    const res = await request(app)
      .get('/api/v1/auth/profile')
      .set('Authorization', `Bearer ${accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.email).toBe(testEmail);
  });
});
