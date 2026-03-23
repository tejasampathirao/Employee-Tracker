"""
Test Publisher Client for Employee_client.py
Publishes sample data to all MQTT topics in a loop every 5 seconds.
Covers all message types from the Flutter app's MqttHandler.
Press Ctrl+C to stop.
"""

import json
import time
import paho.mqtt.client as mqtt

MQTT_BROKER = "localhost"
MQTT_PORT = 1883

# Sample test data matching ALL message types from the Flutter MqttHandler
test_data = [
    # 1. Attendance (employee/tracker) — type: attendance
    ("employee/tracker", {
        "type": "attendance",
        "request_id": "ATT-001",
        "employee_id": "EMP001",
        "timestamp": "2026-03-20T09:00:00",
        "location": {"lat": 28.6139, "lng": 77.2090},
        "status": "Checked-In"
    }),
    # 2. Daily work log (employee/tracker) — type: daily_work_log
    ("employee/tracker", {
        "type": "daily_work_log",
        "request_id": "WL-001",
        "employee_id": "EMP001",
        "timestamp": "2026-03-20T17:00:00",
        "description": "Completed field inspection",
        "work_type": "Field Work"
    }),
    # 3. Work report (employee/tracker) — type: work_report
    ("employee/tracker", {
        "type": "work_report",
        "request_id": "WR-001",
        "employee_id": "EMP001",
        "from_date": "2026-03-18",
        "to_date": "2026-03-20",
        "total_worked": "24h 30m",
        "timestamp": "2026-03-20T18:00:00"
    }),
    # 4. Leave request (employee/tracker/hr/leaves) — type: leave_request
    ("employee/tracker/hr/leaves", {
        "type": "leave_request",
        "request_id": "LV-001",
        "employee_id": "EMP001",
        "leave_type": "Casual Leave",
        "from_date": "2026-03-22",
        "to_date": "2026-03-23",
        "reason": "Family function",
        "status": "Pending"
    }),
    # 5. Expense claim (employee/tracker/expenses) — type: expense_claim
    ("employee/tracker/expenses", {
        "type": "expense_claim",
        "request_id": "EXP-001",
        "employee_id": "EMP001",
        "timestamp": "2026-03-20T12:00:00",
        "category": "Travel",
        "description": "Cab to office",
        "amount": 350.00,
        "status": "Pending"
    }),
    # 6. Travel expense (employee/tracker/expenses) — type: travel_expense
    ("employee/tracker/expenses", {
        "type": "travel_expense",
        "request_id": "TEXP-001",
        "employee_id": "EMP001",
        "amount": 1200.00,
        "description": "Client site visit",
        "visit_type": "Client Visit",
        "timestamp": "2026-03-20T10:00:00",
        "route_info": {
            "source": {"lat": 28.6139, "lng": 77.2090},
            "destination": {"lat": 28.7041, "lng": 77.1025},
            "distance_km": 15.3
        }
    }),
    # 7. Additional expense (employee/tracker/expenses) — type: additional_expense
    ("employee/tracker/expenses", {
        "type": "additional_expense",
        "request_id": "AEXP-001",
        "employee_id": "EMP001",
        "description": "Parking charges",
        "amount": 100.00,
        "timestamp": "2026-03-20T11:00:00",
        "bill_image_path": None
    }),
    # 8. Combined expense request (employee/tracker/expenses) — type: expense_request
    ("employee/tracker/expenses", {
        "type": "expense_request",
        "request_id": "CEXP-001",
        "employee_id": "EMP001",
        "status": "Pending",
        "timestamp": "2026-03-20T14:00:00",
        "food_amount": 250.00,
        "food_desc": "Lunch with client",
        "fuel_amount": 500.00,
        "fuel_desc": "Petrol for site visit",
        "travel_amount": 0,
        "travel_desc": "",
        "material_amount": 800.00,
        "material_desc": "Office supplies"
    }),
    # 9. Live location (employee/tracker/location) — type: location_update
    ("employee/tracker/location", {
        "type": "location_update",
        "request_id": "LOC-001",
        "employee_id": "EMP001",
        "lat": 28.6139,
        "lng": 77.2090,
        "timestamp": "2026-03-20T09:05:00"
    }),
    # 10. Travel attendance (employee/tracker/travel_attendance) — type: travel_attendance
    ("employee/tracker/travel_attendance", {
        "type": "travel_attendance",
        "request_id": "TA-001",
        "employee_id": "EMP001",
        "action": "Traveling",
        "lat": 28.6139,
        "lng": 77.2090,
        "timestamp": "2026-03-20T08:30:00"
    }),
    # 11. Admin attendance (admin/attendance) — type: admin_attendance
    ("admin/attendance", {
        "type": "admin_attendance",
        "request_id": "AATT-001",
        "employee_id": "EMP001",
        "check_in_time": "09:00",
        "date": "2026-03-20",
        "timestamp": "2026-03-20T09:00:00"
    }),
    # 12. Admin approval (admin/approvals) — type: admin_approval
    ("admin/approvals", {
        "type": "admin_approval",
        "request_id": "LV-001",
        "employee_id": "EMP001",
        "approval_type": "leave",
        "approved_by": "ADMIN001",
        "status": "Approved",
        "timestamp": "2026-03-20T10:30:00",
        "remarks": "Approved by manager"
    }),
    # 13. Food expense (employee/tracker/expenses/food) — type: food_expense
    ("employee/tracker/expenses/food", {
        "type": "food_expense",
        "request_id": "FEXP-001",
        "employee_id": "EMP001",
        "amount": 200.00,
        "description": "Team lunch",
        "timestamp": "2026-03-20T13:00:00"
    }),
    # 14. Fuel expense (employee/tracker/expenses/fuel) — type: fuel_expense
    ("employee/tracker/expenses/fuel", {
        "type": "fuel_expense",
        "request_id": "FLEXP-001",
        "employee_id": "EMP001",
        "amount": 500.00,
        "description": "Petrol refill",
        "timestamp": "2026-03-20T08:00:00"
    }),
    # 15. Travel category expense (employee/tracker/expenses/travel) — type: travel_category_expense
    ("employee/tracker/expenses/travel", {
        "type": "travel_category_expense",
        "request_id": "TCEXP-001",
        "employee_id": "EMP001",
        "amount": 750.00,
        "description": "Train ticket",
        "distance_km": 120.5,
        "timestamp": "2026-03-20T07:00:00"
    }),
    # 16. Material expense (employee/tracker/expenses/material) — type: material_expense
    ("employee/tracker/expenses/material", {
        "type": "material_expense",
        "request_id": "MEXP-001",
        "employee_id": "EMP001",
        "amount": 1500.00,
        "description": "Safety equipment",
        "timestamp": "2026-03-20T15:00:00"
    }),
]

# Simple connect, publish in a loop, no callbacks
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
print("Connecting to broker...", flush=True)
client.connect(MQTT_BROKER, MQTT_PORT, 60)
client.loop_start()  # handles network in background thread

count = 0
try:
    while True:
        count += 1
        print(f"\n--- Round {count} ---", flush=True)
        for topic, data in test_data:
            payload = json.dumps(data)
            client.publish(topic, payload, qos=1)
            print(f"  Published -> {topic}", flush=True)
            time.sleep(0.2)
        print(f"Round {count} done. Waiting 5 seconds...", flush=True)
        time.sleep(5)
except KeyboardInterrupt:
    print("\nStopped by user.")
finally:
    client.loop_stop()
    client.disconnect()
    print("Disconnected.")
