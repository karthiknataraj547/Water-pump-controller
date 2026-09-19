/**
 * HydroPulse IoT Water Pump Ecosystem PM2 Configuration
 * Manages full lifecycle of Web Application, API, and Microservices
 */

module.exports = {
  apps: [
    {
      name: 'hydropulse-webapp',
      script: 'api/server.js',
      exec_mode: 'fork',
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
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 4000,
        MQTT_BROKER_URL: 'mqtt://broker.emqx.io:1883',
        CLOUD_API_URL: 'https://water-pump-controller.vercel.app/api/v1',
        DATABASE_URL: 'postgresql://iot_user:iot_password@localhost:5432/water_pump_db?schema=public'
      }
    }
  ]
};
