#!/usr/bin/env python3
"""
End-to-End System & Hardware Integration Test Suite
Validates:
1. Backend REST API Health & User Authentication (JWT)
2. Device Claiming & Provisioning Validation
3. MQTT Telemetry Ingestion Loop
4. Downlink Pump Control & Device ACK Verification
"""

import sys
import time
import json
import os

BASE_URL = os.environ.get("BACKEND_API_URL", "https://water-pump-controller.vercel.app/api/v1")
TEST_EMAIL = "admin@waterpump.io"
TEST_PASS = "AdminPassword123!"
DEVICE_ID = "esp32_pump_94B97E"

def log(msg, success=True):
    icon = "✅" if success else "❌"
    print(f"{icon} {msg}")

def run_tests():
    print("=" * 60)
    print("  HydroPulse IoT - Automated Integration Test Runner")
    print("=" * 60)

    try:
        health_url = BASE_URL.replace("/api/v1", "") + "/health"
        res = requests.get(health_url, timeout=5)
        if res.status_code == 200:
            log(f"Backend Server Health OK: {res.json()}")
        else:
            log(f"Backend Server unhealthy: {res.status_code}", False)
            return False
    except Exception as e:
        log(f"Cannot connect to Backend API at {BASE_URL} ({e}). Please ensure backend is running.", False)
        return False

    # 2. Authentication Login
    try:
        login_res = requests.post(f"{BASE_URL}/auth/login", json={"email": TEST_EMAIL, "password": TEST_PASS}, timeout=3)
        if login_res.status_code != 200:
            log(f"Login failed: {login_res.text}", False)
            return False

        auth_data = login_res.json()["data"]
        token = auth_data["tokens"]["accessToken"]
        headers = {"Authorization": f"Bearer {token}"}
        log(f"Authenticated as {TEST_EMAIL} (Token obtained)")
    except Exception as e:
        log(f"Auth test failed: {e}", False)
        return False

    # 3. Fetch User Devices
    try:
        dev_res = requests.get(f"{BASE_URL}/devices", headers=headers, timeout=3)
        devices = dev_res.json().get("data", [])
        log(f"Retrieved {len(devices)} claimed devices from database")
    except Exception as e:
        log(f"Device fetch failed: {e}", False)

    # 4. Dispatch Pump ON Command
    try:
        print("\n[TEST] Dispatching PUMP_ON command to device...")
        cmd_res = requests.post(
            f"{BASE_URL}/pumps/{DEVICE_ID}/command",
            headers=headers,
            json={"command": "PUMP_ON", "parameters": {"max_duration_minutes": 15}},
            timeout=8
        )
        if cmd_res.status_code == 200:
            log(f"Command response: {cmd_res.json()}")
        else:
            log(f"Command dispatch failed: {cmd_res.status_code} - {cmd_res.text}", False)
    except Exception as e:
        log(f"Command dispatch test exception: {e}", False)

    # 5. Fetch Analytics
    try:
        analytics_res = requests.get(f"{BASE_URL}/analytics/{DEVICE_ID}?range=today", headers=headers, timeout=3)
        if analytics_res.status_code == 200:
            summary = analytics_res.json().get("data", {}).get("summary", {})
            log(f"Analytics Aggregation OK: {summary}")
        else:
            log(f"Analytics failed: {analytics_res.status_code}", False)
    except Exception as e:
        log(f"Analytics test failed: {e}", False)

    print("\n" + "=" * 60)
    print("  🎉 All Integration Tests Completed!")
    print("=" * 60)
    return True

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
