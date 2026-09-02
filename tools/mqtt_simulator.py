#!/usr/bin/env python3
"""
IoT Water Pump & Sensor Node Hardware Simulator
Simulates:
- ESP32 Gateway (MQTT connection, Relay status, Command execution & ACK, Local Safety Engine)
- ESP8266 Sub Node (Tank Water Level, Flow Rate, TDS, Temperature, Battery)
"""

import time
import json
import random
import threading
import paho.mqtt.client as mqtt

BROKER_HOST = "localhost"
BROKER_PORT = 1883
USER_ID = "usr_demo_001"
DEVICE_ID = "esp32_pump_94B97E"
SUB_NODE_ID = "tank_node_001"

# Simulated Physical State
state = {
    "pump_state": "OFF",
    "mode": "AUTO",
    "water_level_pct": 74.5,
    "water_level_cm": 149.0,
    "flow_rate_lpm": 0.0,
    "total_water_liters": 3840.0,
    "tds_ppm": 165,
    "temperature_c": 27.2,
    "battery_pct": 94,
    "seq_num": 1,
    "uptime_seconds": 120,
    "emergency_locked": False,
}

running_duration_sec = 0

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[SIMULATOR] ✅ Connected to Mosquitto MQTT Broker at {BROKER_HOST}:{BROKER_PORT}")
        cmd_topic = f"pump/{USER_ID}/{DEVICE_ID}/command"
        cfg_topic = f"pump/{USER_ID}/{DEVICE_ID}/config"
        client.subscribe([(cmd_topic, 1), (cfg_topic, 1)])
        print(f"[SIMULATOR] 📡 Subscribed to command topic: {cmd_topic}")
    else:
        print(f"[SIMULATOR] ❌ Connection failed with code {rc}")

def on_message(client, userdata, msg):
    topic = msg.topic
    payload_str = msg.payload.decode("utf-8")
    print(f"\n[SIMULATOR] 📥 Received message on {topic}:\n{payload_str}")

    try:
        data = json.loads(payload_str)
    except Exception as e:
        print(f"[SIMULATOR] JSON parse error: {e}")
        return

    if topic.endswith("/command"):
        handle_command(client, data)
    elif topic.endswith("/config"):
        print(f"[SIMULATOR] ⚙️ Configuration updated from cloud: {data}")

def handle_command(client, data):
    global state, running_duration_sec
    cmd_id = data.get("command_id", f"cmd_{int(time.time())}")
    cmd = data.get("command", "")
    start_time = time.time()

    ack_topic = f"pump/{USER_ID}/{DEVICE_ID}/ack"
    status_topic = f"pump/{USER_ID}/{DEVICE_ID}/status"

    if cmd == "PUMP_ON":
        if state["emergency_locked"]:
            ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "FAILED", "message": "Rejected: System is EMERGENCY LOCKED.", "execution_time_ms": 15, "timestamp": int(time.time())}
        elif state["water_level_pct"] >= 95.0:
            ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "FAILED", "message": "Rejected by Safety: Tank is already full.", "execution_time_ms": 18, "timestamp": int(time.time())}
        else:
            state["pump_state"] = "ON"
            state["flow_rate_lpm"] = 18.5 + random.uniform(-1.0, 1.0)
            running_duration_sec = 0
            ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "SUCCESS", "message": "Pump relay closed successfully. Motor RUNNING.", "execution_time_ms": 42, "timestamp": int(time.time())}
    elif cmd == "PUMP_OFF":
        state["pump_state"] = "OFF"
        state["flow_rate_lpm"] = 0.0
        running_duration_sec = 0
        ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "SUCCESS", "message": "Pump stopped successfully.", "execution_time_ms": 30, "timestamp": int(time.time())}
    elif cmd == "EMERGENCY_STOP":
        state["pump_state"] = "EMERGENCY_STOP"
        state["emergency_locked"] = True
        state["flow_rate_lpm"] = 0.0
        running_duration_sec = 0
        ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "SUCCESS", "message": "🚨 EMERGENCY HARD SHUTDOWN EXECUTED. Relay locked.", "execution_time_ms": 12, "timestamp": int(time.time())}
    elif cmd == "SET_MODE":
        new_mode = data.get("parameters", {}).get("mode", "AUTO")
        state["mode"] = new_mode
        ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "SUCCESS", "message": f"Mode changed to {new_mode}.", "execution_time_ms": 20, "timestamp": int(time.time())}
    elif cmd == "RESTART_DEVICE":
        ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "SUCCESS", "message": "ESP32 restarting...", "execution_time_ms": 10, "timestamp": int(time.time())}
    else:
        ack = {"command_id": cmd_id, "device_id": DEVICE_ID, "status": "FAILED", "message": f"Unknown command {cmd}", "execution_time_ms": 10, "timestamp": int(time.time())}

    client.publish(ack_topic, json.dumps(ack), qos=1)
    print(f"[SIMULATOR] 📤 Published ACK for {cmd_id}: {ack['status']}")

def telemetry_loop(client):
    global state, running_duration_sec
    sensor_topic = f"pump/{USER_ID}/{DEVICE_ID}/sensor"
    status_topic = f"pump/{USER_ID}/{DEVICE_ID}/status"

    status_counter = 0

    while True:
        time.sleep(3.0)
        state["seq_num"] += 1
        state["uptime_seconds"] += 3

        # Physics simulation: If pump is ON, water level rises and flow is active
        if state["pump_state"] == "ON":
            running_duration_sec += 3
            state["water_level_pct"] = min(100.0, state["water_level_pct"] + 0.8)
            state["water_level_cm"] = (state["water_level_pct"] / 100.0) * 200.0
            state["flow_rate_lpm"] = 18.5 + random.uniform(-0.8, 0.8)
            state["total_water_liters"] += (state["flow_rate_lpm"] / 60.0) * 3.0

            # Autonomous Auto-Stop local safety cutoff at 95%
            if state["water_level_pct"] >= 95.0 and state["mode"] == "AUTO":
                print("\n[SIMULATOR SAFETY] 🛑 Tank reached 95% full. Autonomous local auto-stop triggered!")
                state["pump_state"] = "OFF"
                state["flow_rate_lpm"] = 0.0
                running_duration_sec = 0
        else:
            # Water slow natural consumption drain
            state["water_level_pct"] = max(5.0, state["water_level_pct"] - 0.05)
            state["water_level_cm"] = (state["water_level_pct"] / 100.0) * 200.0
            state["flow_rate_lpm"] = 0.0

            # Autonomous Auto-Start local safety rule if level drops < 30% in AUTO mode
            if state["water_level_pct"] <= 30.0 and state["mode"] == "AUTO" and not state["emergency_locked"]:
                print("\n[SIMULATOR AUTOMATION] ⚡ Water level < 30%. Autonomous local auto-start triggered!")
                state["pump_state"] = "ON"
                state["flow_rate_lpm"] = 18.0

        # Publish sensor packet (ESP8266 -> ESP-NOW -> ESP32 -> MQTT)
        sensor_packet = {
            "device_id": DEVICE_ID,
            "sub_node_id": SUB_NODE_ID,
            "seq_num": state["seq_num"],
            "water_level_pct": round(state["water_level_pct"], 1),
            "water_level_cm": round(state["water_level_cm"], 1),
            "flow_rate_lpm": round(state["flow_rate_lpm"], 1),
            "total_water_liters": round(state["total_water_liters"], 1),
            "tds_ppm": state["tds_ppm"] + random.randint(-2, 2),
            "temperature_c": round(state["temperature_c"] + random.uniform(-0.1, 0.1), 1),
            "battery_voltage": 4.12,
            "battery_pct": state["battery_pct"],
            "timestamp": int(time.time()),
        }
        client.publish(sensor_topic, json.dumps(sensor_packet), qos=1)
        print(f"[SIMULATOR] 🌊 Telemetry sent | Level: {sensor_packet['water_level_pct']}% | Flow: {sensor_packet['flow_rate_lpm']} LPM | Pump: {state['pump_state']}")

        # Publish periodic Gateway status every 9s
        status_counter += 1
        if status_counter % 3 == 0:
            status_packet = {
                "device_id": DEVICE_ID,
                "user_id": USER_ID,
                "firmware_version": "1.0.0",
                "uptime_seconds": state["uptime_seconds"],
                "wifi_rssi": -58 + random.randint(-3, 3),
                "state": "ONLINE",
                "pump_state": state["pump_state"],
                "mode": state["mode"],
                "running_duration_seconds": running_duration_sec,
                "safety_status": "NORMAL" if not state["emergency_locked"] else "CRITICAL_LOCKED",
                "free_heap_bytes": 174200,
                "timestamp": int(time.time()),
            }
            client.publish(status_topic, json.dumps(status_packet), qos=1, retain=True)

def main():
    print("=" * 60)
    print("  HydroPulse IoT - ESP32 & ESP8266 Hardware Simulator")
    print("=" * 60)

    client = mqtt.Client(client_id=f"esp32_simulator_{random.randint(100, 999)}")
    client.on_connect = on_connect
    client.on_message = on_message

    try:
        client.connect(BROKER_HOST, BROKER_PORT, 60)
    except Exception as e:
        print(f"[SIMULATOR] Could not connect to MQTT Broker ({e}). Ensure Mosquitto is running on port 1883.")
        return

    telemetry_thread = threading.Thread(target=telemetry_loop, args=(client,), daemon=True)
    telemetry_thread.start()

    client.loop_forever()

if __name__ == "__main__":
    main()
