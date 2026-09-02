# REST API Documentation

Base URL: `http://localhost:4000/api/v1` (or your production cloud domain)

All authenticated endpoints require an `Authorization: Bearer <access_token>` header.

---

## 1. Authentication & Users

### `POST /auth/register`
Create a new user account.
* **Body**:
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123!",
  "first_name": "Karthik",
  "last_name": "N"
}
```
* **Response `201 Created`**:
```json
{
  "status": "success",
  "data": {
    "user": {
      "id": "usr_98a7f1c4",
      "email": "user@example.com",
      "first_name": "Karthik",
      "last_name": "N",
      "role": "USER"
    },
    "tokens": {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "eyJhbGciOi...",
      "expires_in": 3600
    }
  }
}
```

### `POST /auth/login`
Authenticate with email and password.
* **Body**:
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123!"
}
```

### `POST /auth/refresh`
Obtain a fresh access token using a valid refresh token.
* **Body**:
```json
{
  "refresh_token": "eyJhbGciOi..."
}
```

---

## 2. Device Management

### `GET /devices`
List all devices claimed by or shared with the authenticated user.
* **Response `200 OK`**:
```json
{
  "status": "success",
  "data": [
    {
      "id": "esp32_pump_94B97E",
      "name": "Overhead Tank Pump",
      "mac_address": "24:6F:28:94:B9:7E",
      "status": "ONLINE",
      "pump_state": "OFF",
      "mode": "AUTO",
      "water_level_pct": 74.2,
      "flow_rate_lpm": 0.0,
      "last_seen": "2026-08-29T11:42:00.000Z"
    }
  ]
}
```

### `POST /devices/claim-token`
Generate a cryptographically signed claim token for BLE provisioning.
* **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "claim_token": "tok_91a0c84f1b",
    "expires_at": "2026-08-29T12:00:00.000Z"
  }
}
```

### `POST /devices/claim`
Claim ownership of an onboarded ESP32 Gateway.
* **Body**:
```json
{
  "device_id": "esp32_pump_94B97E",
  "claim_token": "tok_91a0c84f1b",
  "name": "Main Agricultural Pump"
}
```

---

## 3. Pump Control & Commands

### `POST /devices/:deviceId/command`
Issue a real-time command to the ESP32 Gateway.
* **Body**:
```json
{
  "command": "PUMP_ON",
  "parameters": {
    "max_duration_minutes": 30
  }
}
```
* **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "command_id": "cmd_b52d9a10",
    "device_id": "esp32_pump_94B97E",
    "command": "PUMP_ON",
    "status": "DISPATCHED",
    "dispatched_at": "2026-08-29T11:43:00.000Z"
  }
}
```

---

## 4. Telemetry & Analytics

### `GET /devices/:deviceId/telemetry/live`
Retrieve the latest cached snapshot of all sensor readings and pump state.

### `GET /devices/:deviceId/analytics`
Retrieve aggregated historical metrics.
* **Query Parameters**:
  - `range`: `today` | `week` | `month` | `custom`
  - `start_date`: ISO 8601 string
  - `end_date`: ISO 8601 string
* **Response `200 OK`**:
```json
{
  "status": "success",
  "data": {
    "total_runtime_minutes": 145,
    "total_volume_pumped_liters": 2840.0,
    "estimated_kwh": 3.62,
    "total_cycles": 4,
    "time_series": [
      {
        "timestamp": "2026-08-29T06:00:00.000Z",
        "runtime_minutes": 45,
        "volume_liters": 910.0
      }
    ]
  }
}
```

---

## 5. Automation Rules

### `GET /devices/:deviceId/rules`
Retrieve automation rules configured for the device.

### `POST /devices/:deviceId/rules`
Create or update an automation rule and synchronize it to the ESP32 Gateway over MQTT.
* **Body**:
```json
{
  "rule_name": "Automatic Tank Refill",
  "is_enabled": true,
  "condition_type": "WATER_LEVEL_BELOW",
  "condition_value": 30.0,
  "action_type": "START_PUMP",
  "auto_stop_level": 90.0,
  "max_runtime_minutes": 40
}
```
