# Production Deployment Guide

This guide covers running the complete backend, database, and MQTT broker stack via Docker, as well as setting up production SSL/TLS certificates and domain endpoints.

---

## 1. Prerequisites

- Docker Engine 20.10+ and Docker Compose v2+
- Node.js 18+ (for local development/testing)
- Python 3.9+ (for running simulators and testing harnesses)
- Flutter 3.19+ (for building Android APK / iOS bundles)

---

## 2. Fast-Start with Docker Compose

1. Copy `.env.example` to `.env` and set your credentials:
```bash
cp backend/.env.example backend/.env
```

2. Start all services in detached mode:
```bash
docker compose up -d --build
```

3. Verify service health status:
```bash
docker compose ps
```

Services exposed:
- **Backend REST API**: `http://localhost:4000`
- **Mosquitto MQTT**: `localhost:1883` (TCP) and `localhost:9001` (WebSockets)
- **PostgreSQL Database**: `localhost:5432`
- **Redis**: `localhost:6379`

---

## 3. Database Migrations & Seeding

Inside the backend container or locally:
```bash
cd backend
npx prisma db push
npx prisma db seed
```

---

## 4. Production Domain & TLS Setup

For production cloud deployments (AWS EC2, DigitalOcean, GCP Compute):
1. Point your domain DNS (e.g. `api.yourdomain.com` and `mqtt.yourdomain.com`) to your server IP.
2. Put an Nginx or Traefik reverse proxy in front of Docker containers with Let's Encrypt automated SSL.
3. Enable SSL for Mosquitto on port 8883 (MQTTS) and WSS on port 9001.

---

## 5. Firmware Flashing (ESP32 & ESP8266)

Using PlatformIO CLI or VS Code PlatformIO extension:

```bash
# Flash ESP32 Main Node
cd firmware/esp32_main_node
pio run --target upload
pio device monitor

# Flash ESP8266 Sub Node
cd firmware/esp8266_sub_node
pio run --target upload
pio device monitor
```
