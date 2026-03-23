# ============================================================================
# Employee Tracker - MQTT Client & SQLite Mirror Database
# ============================================================================
# PURPOSE:
#   This script acts as a backend server that:
#   1. Listens for employee data sent over MQTT from a mobile app (Flutter/Dart).
#   2. Stores that data into a local SQLite database — mirroring 6 tables:
#      users, attendance, leave_requests, employee_expenses, live_locations, travel_attendance
#   3. When an admin requests it, sends back ALL stored data over MQTT.
#
# HOW IT WORKS (High Level):
#   Mobile App  ---[MQTT message]--->  This Script  ---[saves to]--->  SQLite DB
#   Admin App   ---[fetch request]--->  This Script ---[reads DB & replies]---> Admin App
#
# PREREQUISITES:
#   pip install paho-mqtt   (MQTT client library)
#   Python's built-in sqlite3 and json modules (no install needed)
# ============================================================================

# --- IMPORTS ---

# sqlite3: Built-in Python library to create and interact with SQLite databases.
#           SQLite is a lightweight database stored as a single file on disk.
import sqlite3

# json: Built-in Python library to convert between Python dictionaries and JSON strings.
#       JSON (JavaScript Object Notation) is a standard text format for sending data.
import json

# paho.mqtt.client: Third-party library that lets Python connect to an MQTT broker.
#   MQTT = Message Queuing Telemetry Transport — a lightweight messaging protocol where:
#     - A "broker" (server) routes messages between clients
#     - Clients "publish" messages to a "topic" (like a channel name)
#     - Clients "subscribe" to topics to receive messages on those channels
#   Think of it like a group chat: you join a channel (subscribe) and
#   anyone can send a message (publish) to that channel.
import paho.mqtt.client as mqtt

# os: Built-in Python library for file path operations.
import os

# datetime: Built-in Python library to work with dates and times.
from datetime import datetime


# ============================================================================
# CONFIGURATION - Settings that control how the script connects and operates
# ============================================================================

# MQTT_BROKER: The IP address or hostname of the MQTT broker (message server).
#   "localhost" means the broker is running on the SAME machine as this script.
#   In production, change this to a remote server IP like "192.168.1.100".
MQTT_BROKER = "localhost"  # Change to your broker's IP if not local

# MQTT_PORT: The network port the MQTT broker listens on.
#   1883 is the standard default port for unencrypted MQTT connections.
#   (8883 is typically used for encrypted/TLS connections.)
MQTT_PORT = 1883

# DATA_TOPICS: A list of MQTT "topics" (channels) this script subscribes to.
#   Each entry is a tuple: ("topic/name", QoS_level)
#
#   Topic names use "/" as separators (like folder paths) to organize messages.
#   Each topic corresponds to one of the database tables used by the Flutter app:
#     - "employee/tracker"           → attendance table (check-in/check-out, work logs, reports)
#     - "employee/tracker/hr/leaves" → leave_requests table (leave applications)
#     - "employee/tracker/location"  → live_locations table (real-time GPS)
#     - "employee/tracker/expenses"  → employee_expenses table (all expense types)
#     - "employee/tracker/travel_attendance" → travel_attendance table (travel records)
#
#   QoS (Quality of Service) = delivery guarantee level:
#     0 = "At most once"  — fire and forget, message may be lost
#     1 = "At least once" — guaranteed delivery, but may arrive twice
#     2 = "Exactly once"  — arrives exactly once (slowest)
#   We use QoS=1 to ensure data isn't lost, even if a duplicate comes through.
DATA_TOPICS = [
    ("employee/tracker", 1),                    # attendance, work logs, work reports
    ("employee/tracker/hr/leaves", 1),          # leave requests
    ("employee/tracker/location", 1),           # live location updates
    ("employee/tracker/expenses", 1),           # all expense types (claim, travel, additional, combined)
    ("employee/tracker/travel_attendance", 1),  # travel attendance
    ("admin/attendance", 1),                    # admin attendance updates
    ("admin/approvals", 1),                     # admin approval actions
    ("employee/tracker/expenses/food", 1),      # food expense category
    ("employee/tracker/expenses/fuel", 1),      # fuel expense category
    ("employee/tracker/expenses/travel", 1),    # travel expense category
    ("employee/tracker/expenses/material", 1),  # material expense category
    ("admin/employee/details", 1),                # employee details from admin
]

# FETCH_REQUEST_TOPIC: When an admin app publishes a message to THIS topic,
#   it means "please send me all the stored data from all 6 tables."
FETCH_REQUEST_TOPIC = "admin/request/fetch_all"

# FETCH_RESPONSE_TOPIC: This script publishes the full database contents
#   back to THIS topic, so the admin app receives all records.
FETCH_RESPONSE_TOPIC = "admin/response/all_data"

# DB_NAME: The filename for the local SQLite database file.
#   Uses os.path to always save in the same folder as this script,
#   regardless of where you run it from.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_NAME = os.path.join(SCRIPT_DIR, "Employee.db")


# ============================================================================
# DATABASE INITIALIZATION
# ============================================================================

def init_db():
    """
    Creates the SQLite database file and all 6 tables if they don't already exist.
    This mirrors the same table structure used in the Flutter/Dart mobile app
    (from db_helper.dart), so data stays consistent between app and server.
    """

    # sqlite3.connect() opens the database file. If the file doesn't exist,
    # SQLite automatically creates it. Returns a "connection" object.
    conn = sqlite3.connect(DB_NAME)

    # A "cursor" is like a pointer/tool that executes SQL commands on the database.
    # Think of it as: connection = the phone line, cursor = the person talking.
    cursor = conn.cursor()

    # --- TABLE 1: USERS ---
    # Stores employee profiles/accounts.
    # CREATE TABLE IF NOT EXISTS = only create if not already there (safe to run repeatedly).
    #
    # Column breakdown:
    #   id        : Auto-incrementing unique row number (1, 2, 3, ...)
    #   emp_id    : Unique employee ID string (e.g., "EMP001"). TEXT UNIQUE prevents duplicates.
    #   name      : Employee's full name
    #   details   : Additional info/notes about the employee
    #   phone     : Phone number
    #   password  : Account password (stored as text)
    #   email     : Email address
    #   role      : Job role (e.g., "Employee", "Admin", "Manager")
    #   is_active : 1 = active, 0 = deactivated. Defaults to 1 (active).
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            emp_id TEXT UNIQUE,
            name TEXT,
            details TEXT,
            phone TEXT,
            password TEXT,
            email TEXT,
            role TEXT,
            is_active INTEGER DEFAULT 1
        )
    ''')

    # --- TABLE 2: ATTENDANCE ---
    # Tracks employee check-ins and check-outs with GPS location.
    # The request_id (UNIQUE) was added in version 26 update to prevent duplicate entries.
    #
    # Column breakdown:
    #   id           : Auto-incrementing row ID
    #   request_id   : Unique identifier per attendance event (prevents duplicates)
    #   employee_id  : Which employee this record belongs to
    #   checkInTime  : Timestamp when employee checked in
    #   checkOutTime : Timestamp when employee checked out (may be NULL initially)
    #   date         : Calendar date of the record (e.g., "2025-07-04")
    #   latitude     : GPS latitude (decimal number, e.g., 28.6139)
    #   longitude    : GPS longitude (decimal number, e.g., 77.2090)
    #   type         : Type of check-in (e.g., "Office", "Remote", "Field")
    #   status       : Current status (e.g., "Checked-In", "Checked-Out")
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id TEXT UNIQUE,
            employee_id TEXT,
            checkInTime TEXT,
            checkOutTime TEXT,
            date TEXT,
            latitude REAL,
            longitude REAL,
            type TEXT,
            status TEXT
        )
    ''')

    # --- TABLE 3: LEAVE REQUESTS ---
    # Stores employee leave/time-off applications.
    #
    # Column breakdown:
    #   id          : Auto-incrementing row ID
    #   request_id  : Unique leave request identifier (prevents duplicates)
    #   employee_id : Who submitted the leave request
    #   start_date  : First day of leave
    #   end_date    : Last day of leave
    #   reason      : Why the employee is requesting leave
    #   status      : Approval status — defaults to 'Pending', can become 'Approved'/'Rejected'
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS leave_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id TEXT UNIQUE,
            employee_id TEXT,
            start_date TEXT,
            end_date TEXT,
            reason TEXT,
            status TEXT DEFAULT 'Pending'
        )
    ''')

    # --- TABLE 4: EMPLOYEE EXPENSES ---
    # Stores expense claims submitted by employees.
    #
    # Column breakdown:
    #   id               : Auto-incrementing row ID
    #   request_id       : Unique expense request ID (prevents duplicates)
    #   employee_id      : Who submitted the expense
    #   date             : When the expense was submitted
    #   expense_category : Category like "Travel", "Food", "Equipment"
    #   description      : Free-text description of the expense
    #   amount           : The money amount (decimal number, e.g., 1500.50)
    #   status           : Approval status, defaults to 'Pending'
    #   latitude/longitude : GPS location where expense was logged
    #   distance         : Distance traveled (for travel-related expenses)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS employee_expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id TEXT UNIQUE,
            employee_id TEXT,
            date TEXT,
            expense_category TEXT,
            description TEXT,
            amount REAL,
            status TEXT DEFAULT 'Pending',
            latitude REAL,
            longitude REAL,
            distance REAL
        )
    ''')

    # --- TABLE 5: LIVE LOCATIONS ---
    # Stores real-time GPS location pings from employees.
    # Unlike other tables, this has NO request_id — every location ping is stored
    # (not deduplicated), building a GPS trail over time.
    #
    # Column breakdown:
    #   id          : Auto-incrementing row ID
    #   employee_id : Which employee sent this location ping
    #   latitude    : GPS latitude coordinate
    #   longitude   : GPS longitude coordinate
    #   speed       : Movement speed at time of ping (e.g., in km/h)
    #   timestamp   : When this location was recorded
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS live_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id TEXT,
            latitude REAL,
            longitude REAL,
            speed REAL,
            timestamp TEXT
        )
    ''')

    # --- TABLE 6: TRAVEL ATTENDANCE ---
    # Tracks whether an employee is traveling on a given date.
    # Simpler than the main attendance table — just records travel status per day.
    #
    # Column breakdown:
    #   id            : Auto-incrementing row ID
    #   employee_id   : Which employee
    #   date          : The travel date
    #   travel_status : Status like "Traveling", "Arrived", "Returned"
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS travel_attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id TEXT,
            date TEXT,
            travel_status TEXT
        )
    ''')

    # --- TABLE 7: ADMIN ACTIONS ---
    # Stores admin-initiated events: attendance overrides, leave/expense approvals, etc.
    #
    # Column breakdown:
    #   id            : Auto-incrementing row ID
    #   request_id    : Unique action ID (prevents duplicates)
    #   employee_id   : Which employee the action is about
    #   action_type   : Type of admin action (admin_attendance, admin_approval)
    #   approval_type : Sub-type for approvals (leave, expense, etc.)
    #   approved_by   : Admin who performed the action
    #   status        : Result status (Approved, Rejected, etc.)
    #   details       : JSON string with any extra data
    #   timestamp     : When the action occurred
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS admin_actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_id TEXT UNIQUE,
            employee_id TEXT,
            action_type TEXT,
            approval_type TEXT,
            approved_by TEXT,
            status TEXT,
            details TEXT,
            timestamp TEXT
        )
    ''')

    # conn.commit() saves all the changes to the database file on disk.
    # Without this, changes would be lost (like editing a document without saving).
    conn.commit()

    # conn.close() releases the database file so other processes can use it.
    # Always close when done to avoid file locks and data corruption.
    conn.close()

    print(f"Network Database Ready: {DB_NAME} (7 Tables Initialized)")


# ============================================================================
# FETCH HANDLER - Responds to admin requests for all stored data
# ============================================================================

def handle_fetch_request(client):
    """
    When an admin sends a "fetch all" request via MQTT, this function:
    1. Opens the database
    2. Reads ALL rows from ALL 6 tables dynamically
    3. Packages everything into a single JSON object
    4. Publishes (sends) that JSON back over MQTT to the admin app

    Parameters:
        client: The MQTT client object, used to publish the response message.
    """
    print("Fetch request received. Compiling all logs...")

    conn = sqlite3.connect(DB_NAME)

    # row_factory = sqlite3.Row makes query results behave like dictionaries
    # instead of plain tuples. This means you can access columns by name:
    #   row["employee_id"] instead of row[1]
    # Essential for converting rows to JSON later.
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # List of all 7 table names in our database
    tables = ['users', 'attendance', 'leave_requests', 'employee_expenses', 'live_locations', 'travel_attendance', 'admin_actions']

    # Start building the response dictionary
    payload = {
        "status": "success",                          # Indicates the fetch worked
        "sync_time": datetime.now().isoformat()       # Current timestamp in ISO format
                                                      # e.g., "2025-07-04T14:30:00.123456"
    }

    # Dynamically loop through each table name and fetch all its rows.
    # For each table:
    #   - Execute "SELECT * FROM <table_name>" to get all rows
    #   - Convert each Row to a dictionary using dict(row)
    #   - Store the list of dicts in the payload under the table's name
    #
    # NOTE: The table names are hardcoded in the 'tables' list above (not from user input),
    # so using an f-string in the SQL here is safe — no SQL injection risk.
    #
    # After this loop, payload looks like:
    #   { "status": "success", "sync_time": "...",
    #     "users": [...], "attendance": [...], "leave_requests": [...],
    #     "employee_expenses": [...], "live_locations": [...], "travel_attendance": [...] }
    for table in tables:
        cursor.execute(f"SELECT * FROM {table}")
        payload[table] = [dict(row) for row in cursor.fetchall()]

    # client.publish() sends the data as an MQTT message.
    #   - FETCH_RESPONSE_TOPIC: the channel to send on ("admin/response/all_data")
    #   - json.dumps(payload): converts the Python dict to a JSON string
    #   - qos=1: ensures the message is delivered at least once
    client.publish(FETCH_RESPONSE_TOPIC, json.dumps(payload), qos=1)

    print("Full Database Sync Published to App.")
    conn.close()


# ============================================================================
# MESSAGE HANDLER - Called automatically whenever ANY subscribed message arrives
# ============================================================================

def on_message(client, userdata, msg):
    """
    This is a CALLBACK function — it is NOT called by us directly.
    The MQTT library calls it automatically every time a message arrives
    on any topic we've subscribed to.

    Parameters:
        client   : The MQTT client instance (same one we created below)
        userdata : Custom data attached to the client (unused here, so it's None)
        msg      : The incoming message object with two key properties:
                     msg.topic   = the topic string (e.g., "employee/tracker")
                     msg.payload = the raw message content in bytes
    """
    try:
        # --- CHECK: Is this a broker system log message? ---
        # $SYS/broker/log/M contains connect/disconnect events from the broker.
        # When any client connects or disconnects, Mosquitto publishes a log here.
        # Example messages:
        #   "1719061800: New connection from 192.168.0.105:54321 on port 1883."
        #   "1719061800: Client flutter_app disconnected."
        if msg.topic.startswith("$SYS"):
            log_msg = msg.payload.decode()
            print(f"[BROKER LOG] {log_msg}")
            return

        # --- CHECK: Is this a fetch request from admin? ---
        # If the message came on the admin fetch topic, handle it separately
        # and return early (don't try to parse it as employee data).
        if msg.topic == FETCH_REQUEST_TOPIC:
            handle_fetch_request(client)
            return

        # --- PARSE THE INCOMING JSON DATA ---
        # msg.payload is raw bytes (like b'{"employee_id": "EMP001"}')
        # .decode() converts bytes to a string: '{"employee_id": "EMP001"}'
        # json.loads() converts that JSON string to a Python dictionary:
        #   {"employee_id": "EMP001"}
        payload = json.loads(msg.payload.decode())

        # Log the raw incoming message for debugging
        print(f"\n{'='*60}")
        print(f"[RECEIVED] Topic: {msg.topic}")
        print(f"[PAYLOAD]  {json.dumps(payload, indent=2)}")
        print(f"{'='*60}")

        # Open a database connection to save the incoming data
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()

        # Get the message type to determine how to handle it
        msg_type = payload.get('type', '')

        # ---------------------------------------------------------------
        # ROUTING: Based on message type, insert data into correct table
        # This matches the JSON formats sent by the Flutter app
        # ---------------------------------------------------------------

        # --- ATTENDANCE (employee/tracker) ---
        # Handles: attendance, daily_work_log, work_report
        if msg_type in ['attendance', 'daily_work_log', 'work_report']:
            # For attendance: use location.lat/lng, status, timestamp as checkInTime
            # For work logs: store as attendance with type='work_log'
            # For work reports: store as attendance with type='work_report'

            if msg_type == 'attendance':
                # Extract location data
                location = payload.get('location', {})
                lat = location.get('lat')
                lng = location.get('lng')

                cursor.execute('''
                    INSERT OR IGNORE INTO attendance (request_id, employee_id, checkInTime, date, latitude, longitude, type, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    payload.get('request_id'),                                          # Unique attendance event ID
                    payload.get('employee_id'),                                         # Employee ID
                    payload.get('timestamp'),                                           # Check-in timestamp
                    payload.get('timestamp', '').split('T')[0],                        # Date from timestamp
                    lat,                                                               # GPS latitude
                    lng,                                                               # GPS longitude
                    'Office',                                                          # Default type
                    payload.get('status', 'Checked-In')                               # Status
                ))
                print(f"Attendance synced for: {payload.get('employee_id')}")

            elif msg_type == 'daily_work_log':
                # Store work logs as attendance records with type='work_log'
                cursor.execute('''
                    INSERT OR IGNORE INTO attendance (request_id, employee_id, checkInTime, date, type, status)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    payload.get('request_id'),                                          # Unique work log ID
                    payload.get('employee_id'),                                         # Employee ID
                    payload.get('timestamp'),                                           # Timestamp
                    payload.get('timestamp', '').split('T')[0],                        # Date from timestamp
                    'work_log',                                                        # Type
                    payload.get('work_type', 'work_log')                              # Status from work_type
                ))
                print(f"Work log synced for: {payload.get('employee_id')}")

            elif msg_type == 'work_report':
                # Store work reports as attendance records with type='work_report'
                cursor.execute('''
                    INSERT OR IGNORE INTO attendance (request_id, employee_id, checkInTime, date, type, status)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    payload.get('request_id'),                                          # Unique report ID
                    payload.get('employee_id'),                                         # Employee ID
                    payload.get('timestamp'),                                           # Timestamp
                    payload.get('from_date'),                                           # Use from_date as date
                    'work_report',                                                     # Type
                    f"Report: {payload.get('total_worked', 'N/A')}"                   # Status with total worked
                ))
                print(f"Work report synced for: {payload.get('employee_id')}")

        # --- LEAVE REQUESTS (employee/tracker/hr/leaves) ---
        elif msg_type == 'leave_request':
            cursor.execute('''
                INSERT OR IGNORE INTO leave_requests (request_id, employee_id, start_date, end_date, reason, status)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                payload.get('request_id'),               # Unique leave request ID
                payload.get('employee_id'),              # Who is requesting leave
                payload.get('from_date'),                # Leave start date
                payload.get('to_date'),                  # Leave end date
                payload.get('reason'),                   # Reason for leave
                payload.get('status', 'Pending')         # Status, defaults to "Pending"
            ))
            print(f"Leave request synced: {payload.get('request_id')}")

        # --- EXPENSES (employee/tracker/expenses) ---
        # Handles: expense_claim, travel_expense, additional_expense, expense_request
        elif msg_type in ['expense_claim', 'travel_expense', 'additional_expense', 'expense_request']:
            if msg_type == 'expense_request':
                # Handle combined expense request - split into individual expense records
                # This matches the Flutter app's logic for expense_request payloads
                categories = ['food', 'fuel', 'travel', 'material']
                for cat in categories:
                    amount_key = f'{cat}_amount'
                    desc_key = f'{cat}_desc'

                    if payload.get(amount_key) and float(payload.get(amount_key, 0)) > 0:
                        cursor.execute('''
                            INSERT OR IGNORE INTO employee_expenses (request_id, employee_id, date, expense_category, description, amount, status, latitude, longitude, distance)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            f"{payload.get('request_id')}_{cat}",                      # Unique expense ID with category
                            payload.get('employee_id'),                                # Employee ID
                            payload.get('timestamp', '').split('T')[0],               # Date from timestamp
                            cat.capitalize(),                                          # Category (Food, Fuel, etc.)
                            payload.get(desc_key, ''),                                 # Description
                            float(payload.get(amount_key, 0)),                        # Amount
                            payload.get('status', 'Pending'),                         # Status
                            payload.get('latitude'),                                   # GPS latitude
                            payload.get('longitude'),                                  # GPS longitude
                            payload.get('distance')                                    # Distance
                        ))
                print(f"Combined expense request split and synced: {payload.get('request_id')}")

            else:
                # Handle individual expense types
                if msg_type == 'expense_claim':
                    category = payload.get('category', 'General')
                    description = payload.get('description', '')
                    amount = payload.get('amount', 0.0)

                elif msg_type == 'travel_expense':
                    category = 'Travel'
                    description = f"{payload.get('visit_type', '')}: {payload.get('description', '')}"
                    amount = payload.get('amount', 0.0)

                    # Extract route info for distance
                    route_info = payload.get('route_info', {})
                    distance = route_info.get('distance_km')

                elif msg_type == 'additional_expense':
                    category = 'Additional'
                    description = payload.get('description', '')
                    amount = payload.get('amount', 0.0)
                    distance = None

                cursor.execute('''
                    INSERT OR IGNORE INTO employee_expenses (request_id, employee_id, date, expense_category, description, amount, status, latitude, longitude, distance)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    payload.get('request_id'),                                          # Unique expense request ID
                    payload.get('employee_id'),                                         # Who submitted the expense
                    payload.get('timestamp', '').split('T')[0],                        # Date from timestamp
                    category,                                                          # Category
                    description,                                                       # Description
                    amount,                                                            # Amount
                    payload.get('status', 'Pending'),                                 # Status
                    payload.get('latitude'),                                           # GPS latitude
                    payload.get('longitude'),                                          # GPS longitude
                    distance if 'distance' in locals() else None                       # Distance (for travel expenses)
                ))
                print(f"{msg_type} synced: {payload.get('request_id')}")

        # --- LIVE LOCATION (employee/tracker/location) ---
        elif msg_type == 'location_update':
            # Plain INSERT (no OR IGNORE): Every location ping is stored as a new row.
            # We WANT multiple entries per employee — this builds a GPS trail over time.
            cursor.execute('''
                INSERT INTO live_locations (employee_id, latitude, longitude, speed, timestamp)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                payload.get('employee_id'),              # Which employee
                payload.get('lat'),                      # GPS latitude
                payload.get('lng'),                      # GPS longitude
                0.0,                                     # Speed (not provided in payload)
                payload.get('timestamp')                 # When this ping was recorded
            ))
            print(f"Live location synced for: {payload.get('employee_id')}")

        # --- TRAVEL ATTENDANCE (employee/tracker/travel_attendance) ---
        elif msg_type == 'travel_attendance':
            # Plain INSERT: Each travel record is stored as-is.
            # Records travel status per employee per timestamp.
            cursor.execute('''
                INSERT INTO travel_attendance (employee_id, date, travel_status)
                VALUES (?, ?, ?)
            ''', (
                payload.get('employee_id'),              # Which employee
                payload.get('timestamp', '').split('T')[0],  # Date from timestamp
                payload.get('action', 'travel')          # Action as travel status
            ))
            print(f"Travel attendance synced for: {payload.get('employee_id')}")

        # --- ADMIN ATTENDANCE (admin/attendance) ---
        elif msg_type == 'admin_attendance':
            cursor.execute('''
                INSERT OR IGNORE INTO admin_actions (request_id, employee_id, action_type, status, details, timestamp)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                payload.get('request_id'),
                payload.get('employee_id'),
                'admin_attendance',
                'Checked-In',
                json.dumps({"check_in_time": payload.get('check_in_time'), "date": payload.get('date')}),
                payload.get('timestamp')
            ))
            print(f"Admin attendance synced for: {payload.get('employee_id')}")

        # --- ADMIN APPROVAL (admin/approvals) ---
        elif msg_type == 'admin_approval':
            cursor.execute('''
                INSERT OR IGNORE INTO admin_actions (request_id, employee_id, action_type, approval_type, approved_by, status, details, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                payload.get('request_id'),
                payload.get('employee_id'),
                'admin_approval',
                payload.get('approval_type'),
                payload.get('approved_by'),
                payload.get('status', 'Approved'),
                json.dumps({k: v for k, v in payload.items() if k not in ('type', 'request_id', 'employee_id', 'approval_type', 'approved_by', 'status', 'timestamp')}),
                payload.get('timestamp')
            ))
            print(f"Admin approval synced: {payload.get('approval_type')} for {payload.get('employee_id')}")

        # --- EMPLOYEE DETAILS (admin/employee/details) ---
        elif msg_type == 'employee_details':
            emp_id = payload.get('emp_id', '')
            # Check if employee already exists
            cursor.execute('SELECT id FROM users WHERE emp_id = ?', (emp_id,))
            existing = cursor.fetchone()

            if existing:
                # Update existing employee
                cursor.execute('''
                    UPDATE users SET name = ?, role = ?, details = ?
                    WHERE emp_id = ?
                ''', (
                    payload.get('name', ''),
                    payload.get('role', 'Employee'),
                    json.dumps({
                        'pan_no': payload.get('pan_no', ''),
                        'aadhar_no': payload.get('aadhar_no', ''),
                        'bank_acc_no': payload.get('bank_acc_no', ''),
                        'ifsc_code': payload.get('ifsc_code', ''),
                        'father_name': payload.get('father_name', ''),
                        'mother_name': payload.get('mother_name', ''),
                        'salary': payload.get('salary', 0.0),
                    }),
                    emp_id
                ))
                print(f"Employee details UPDATED: {emp_id} - {payload.get('name')}")
            else:
                # Insert new employee
                cursor.execute('''
                    INSERT INTO users (emp_id, name, role, details, is_active)
                    VALUES (?, ?, ?, ?, 1)
                ''', (
                    emp_id,
                    payload.get('name', ''),
                    payload.get('role', 'Employee'),
                    json.dumps({
                        'pan_no': payload.get('pan_no', ''),
                        'aadhar_no': payload.get('aadhar_no', ''),
                        'bank_acc_no': payload.get('bank_acc_no', ''),
                        'ifsc_code': payload.get('ifsc_code', ''),
                        'father_name': payload.get('father_name', ''),
                        'mother_name': payload.get('mother_name', ''),
                        'salary': payload.get('salary', 0.0),
                    })
                ))
                print(f"Employee details INSERTED: {emp_id} - {payload.get('name')}")

        # --- CATEGORY EXPENSES (employee/tracker/expenses/food|fuel|travel|material) ---
        elif msg_type in ['food_expense', 'fuel_expense', 'travel_category_expense', 'material_expense']:
            # Map type to category name
            category_map = {
                'food_expense': 'Food',
                'fuel_expense': 'Fuel',
                'travel_category_expense': 'Travel',
                'material_expense': 'Material'
            }
            cursor.execute('''
                INSERT OR IGNORE INTO employee_expenses (request_id, employee_id, date, expense_category, description, amount, status, latitude, longitude, distance)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                payload.get('request_id'),
                payload.get('employee_id'),
                payload.get('timestamp', '').split('T')[0],
                category_map.get(msg_type, 'General'),
                payload.get('description', ''),
                payload.get('amount', 0.0),
                payload.get('status', 'Pending'),
                payload.get('latitude'),
                payload.get('longitude'),
                payload.get('distance_km')
            ))
            print(f"{msg_type} synced: {payload.get('request_id')}")

        # --- STATUS UPDATE (updates existing records) ---
        elif msg_type == 'status_update':
            # Updates the status of an existing record in the specified category table
            category = payload.get('category', '')
            record_id = payload.get('id', '')
            new_status = payload.get('status', 'Pending')
            table_map = {
                'leave': 'leave_requests',
                'expense': 'employee_expenses',
                'attendance': 'attendance',
                'travel': 'travel_attendance'
            }
            table = table_map.get(category)
            if table and record_id:
                if table == 'travel_attendance':
                    cursor.execute(f"UPDATE {table} SET travel_status = ? WHERE id = ?", (new_status, record_id))
                else:
                    cursor.execute(f"UPDATE {table} SET status = ? WHERE id = ?", (new_status, record_id))
                print(f"Status update: {category} #{record_id} -> {new_status}")
            else:
                print(f"Status update skipped: invalid category '{category}' or missing id")

        else:
            print(f"Unknown message type received: {msg_type}")

        # Save all changes to the database file
        conn.commit()

        # Release the database connection
        conn.close()

    except Exception as e:
        # If ANYTHING goes wrong (bad JSON, database error, missing fields, etc.),
        # catch the error and print it instead of crashing the entire script.
        # This keeps the MQTT client running even if one bad message comes in.
        print(f"Sync Error: {e}")


# ============================================================================
# MAIN EXECUTION - The script starts running from here
# ============================================================================
# In Python, code at the top level (not inside a function) runs immediately
# when the script is executed.

# Step 1: Create the database and all 6 tables (if they don't already exist)
init_db()

# Step 2: Create an MQTT client instance.
# This object manages the connection to the broker and handles sending/receiving.
# CallbackAPIVersion.VERSION2 is required for paho-mqtt v2.0+ to avoid deprecation warnings.
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)

# Step 3: Set up the "on_connect" callback.
#   This function runs automatically once the client successfully connects to the broker.
#   It also prints a confirmation message showing the connection was successful.
#
#   Parameters (paho-mqtt v2.0+ callback signature):
#     c  = client object
#     u  = userdata (None)
#     f  = flags (connection flags from broker)
#     rc = reason code (0 = success, non-zero = error)
#     p  = properties (MQTT v5 properties, can be ignored for basic usage)
#
#   c.subscribe(...) tells the broker: "Send me messages from these topics."
#   We subscribe to all 11 DATA_TOPICS + the FETCH_REQUEST_TOPIC (12 subscriptions total).
def on_connect(c, u, f, rc, p):
    print(f"Connected to Broker successfully! (Result code: {rc})")
    print(f"Subscribed to {len(DATA_TOPICS) + 1} topics. Waiting for messages...\n")
    c.subscribe(DATA_TOPICS + [(FETCH_REQUEST_TOPIC, 1)])

    # Subscribe to the broker's system topic that logs client connect/disconnect events.
    # $SYS/broker/log/M = logs related to MQTT messages and client activity.
    # When any device connects or disconnects, the broker publishes a log message here.
    c.subscribe("$SYS/broker/log/M", 0)

client.on_connect = on_connect

# Step 4: Register our on_message function as the callback for incoming messages.
# Whenever a message arrives on any subscribed topic, MQTT library calls on_message().
client.on_message = on_message

# Step 5: Connect to the MQTT broker.
#   MQTT_BROKER = server address ("localhost")
#   MQTT_PORT   = port number (1883)
#   60          = keepalive interval in seconds. The client sends a small "ping"
#                 every 60 seconds to tell the broker "I'm still alive."
#                 If the broker doesn't hear from us for 1.5x this time (90s),
#                 it assumes we disconnected.
print(f"Connecting to Broker at {MQTT_BROKER}...")

try:
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
except Exception as e:
    print(f"Failed to connect to MQTT broker: {e}")
    print("Make sure Mosquitto is running and accessible.")
    exit(1)

# Step 6: Start the MQTT event loop. This is a BLOCKING call — it runs forever
# and never returns (unless an error occurs or the program is killed).
# Inside this loop, the library:
#   - Maintains the broker connection
#   - Sends keepalive pings
#   - Receives incoming messages and calls on_message() for each one
#   - Handles reconnection if the connection drops
#
# To stop the script, press Ctrl+C in the terminal.
client.loop_forever()