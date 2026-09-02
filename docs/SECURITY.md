# Security Architecture & Best Practices

This document outlines the security controls, encryption mechanisms, authentication flows, and fail-safe defenses implemented across the IoT Water Pump platform.

---

## 1. Network & Transport Security

- **MQTT Encryption & Isolation**:
  - In production, all MQTT traffic uses TLS 1.3 on port 8883.
  - Mosquitto ACLs enforce topic isolation: a device authenticated with credentials `esp32_94B97E` can only publish and subscribe to `pump/{userId}/esp32_94B97E/*`. It cannot intercept or forge messages for other devices or users.
- **REST API Transport**:
  - All HTTP endpoints enforce HTTPS with HSTS headers, CORS origin whitelisting, and rate limiting (via Redis token-bucket).

---

## 2. Authentication & Authorization

- **Password Storage**: Argon2id / bcrypt with work factor 12.
- **JWT Token Architecture**:
  - Access tokens have a short lifespan (15 to 60 minutes).
  - Refresh tokens are cryptographically randomized strings stored in the database with one-time rotation and device fingerprinting.
- **Device Claiming Protocol**:
  - Devices are not bound to an account at the factory.
  - A user generates a time-limited signed Claim Token (`tok_...`) from the mobile app.
  - The token is transmitted to the ESP32 over encrypted BLE. The ESP32 submits this token during its first MQTT handshake to prove device ownership.

---

## 3. Firmware & Hardware Level Safety

- **NVS Encrypted Storage**: Wi-Fi passwords and device claim tokens stored in ESP32 Non-Volatile Storage (NVS) can utilize Flash Encryption and Secure Boot on ESP32-WROOM-32.
- **Anti-Replay & Packet Tampering**:
  - ESP-NOW packets contain a 16-bit CRC checksum and monotonic 32-bit sequence numbers.
  - Out-of-order or duplicate packets are discarded.
- **Local Hardcoded Safety Interlocks**:
  - Even if the cloud backend is compromised or sends a malicious `PUMP_ON` command when the tank is full, the ESP32's local safety manager inspects real-time water levels and hard-aborts the relay actuation if the level is $\ge 98\%$.
  - Maximum continuous runtime cutoff (e.g. 45 minutes) prevents infinite running regardless of downlink commands.
