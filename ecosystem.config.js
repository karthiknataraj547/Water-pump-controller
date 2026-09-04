/**
 * HydroPulse IoT Water Pump Ecosystem PM2 Configuration
 * Manages full lifecycle of Web Application, API, and Microservices
 */

module.exports = {
  apps: [
    {
      name: 'hydropulse-webapp',
      script: 'api/server.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      }
    },
    {
      name: 'hydropulse-backend',
      cwd: './backend',
      script: 'dist/server.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 4000
      }
    }
  ]
};
