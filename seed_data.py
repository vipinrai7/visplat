#!/usr/bin/env python3
"""
ShotGrid Demo Data Generator
Generates realistic animation production data for the demo stack.

Structure:
- 1 Project
- 3 Episodes
- 10 Shots per Episode (30 total)
- 6 Tasks per Shot (180 total)
- 12 Users across departments
"""

import json
import os
import random
from datetime import datetime, timedelta

import psycopg2
from psycopg2.extras import execute_values

# ===================
# CONFIGURATION
# ===================

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": int(os.getenv("PGPORT", "5432")),
    "database": os.getenv("PGDATABASE", "shotgrid_demo"),
    "user": os.getenv("PGUSER", "admin"),
    "password": os.getenv("PGPASSWORD", "demodemo123"),
}

# Task types (the 6 tasks per shot)
TASK_TYPES = ["Layout", "Animation", "FX", "Lighting", "Compositing", "Review"]

# Shot statuses with weighted distribution
SHOT_STATUSES = ["Not Started", "In Progress", "Pending Review", "Approved", "Final"]
SHOT_STATUS_WEIGHTS = [0.1, 0.3, 0.2, 0.25, 0.15]

# Task statuses
TASK_STATUSES = ["Waiting", "Ready", "In Progress", "Pending Review", "Complete"]

# Departments
DEPARTMENTS = ["Layout", "Animation", "FX", "Lighting", "Compositing", "Production"]

# ===================
# DATA GENERATORS
# ===================


def generate_users():
    """Generate 12 artists across departments."""
    first_names = [
        "Alex",
        "Jordan",
        "Casey",
        "Morgan",
        "Taylor",
        "Riley",
        "Quinn",
        "Avery",
        "Cameron",
        "Drew",
        "Jamie",
        "Skyler",
    ]
    last_names = [
        "Chen",
        "Patel",
        "Kim",
        "Garcia",
        "Smith",
        "Johnson",
        "Williams",
        "Brown",
        "Jones",
        "Davis",
        "Miller",
        "Wilson",
    ]

    users = []
    for i, (first, last) in enumerate(zip(first_names, last_names), start=1):
        dept = DEPARTMENTS[i % len(DEPARTMENTS)]
        users.append(
            {
                "sg_id": 1000 + i,
                "data": {
                    "name": f"{first} {last}",
                    "email": f"{first.lower()}.{last.lower()}@studio.local",
                    "department": dept,
                    "is_active": True,
                },
            }
        )
    return users


def generate_project():
    """Generate the main project."""
    return {
        "sg_id": 100,
        "data": {
            "code": "COSMOS",
            "name": "Cosmos: A Space Journey",
            "status": "Active",
            "start_date": "2025-01-06",
            "end_date": "2025-12-19",
        },
    }


def generate_episodes(project_id):
    """Generate 3 episodes."""
    episode_names = [
        ("EP101", "The Launch"),
        ("EP102", "First Contact"),
        ("EP103", "The Return"),
    ]

    episodes = []
    for i, (code, name) in enumerate(episode_names, start=1):
        episodes.append(
            {
                "sg_id": 200 + i,
                "data": {
                    "project_id": project_id,
                    "code": code,
                    "name": name,
                    "status": "In Production" if i <= 2 else "Pre-Production",
                    "cut_order": i,
                },
            }
        )
    return episodes


def generate_shots(episodes):
    """Generate 10 shots per episode."""
    shots = []
    shot_id = 300

    for ep in episodes:
        ep_code = ep["data"]["code"]
        ep_id = ep["sg_id"]

        for shot_num in range(1, 11):
            shot_id += 1
            shot_code = f"{ep_code}_SH{shot_num:03d}"

            # Random frame range (typical animation shots)
            frame_in = 1001
            frame_count = random.randint(48, 240)  # 2-10 seconds at 24fps
            frame_out = frame_in + frame_count - 1

            # Bid hours based on complexity (frame count)
            base_bid = frame_count * 0.15  # ~0.15 hours per frame as baseline
            bid_hours = round(base_bid * random.uniform(0.8, 1.3), 2)

            # Actual hours - some variance from bid
            status = random.choices(SHOT_STATUSES, weights=SHOT_STATUS_WEIGHTS)[0]
            if status in ["Approved", "Final"]:
                # Completed shots have actual hours
                variance = random.uniform(0.7, 1.4)  # Some under, some over budget
                actual_hours = round(bid_hours * variance, 2)
            elif status == "In Progress":
                # Partial progress
                actual_hours = round(bid_hours * random.uniform(0.2, 0.8), 2)
            else:
                actual_hours = 0

            shots.append(
                {
                    "sg_id": shot_id,
                    "data": {
                        "episode_id": ep_id,
                        "code": shot_code,
                        "name": f"Shot {shot_num}",
                        "status": status,
                        "frame_count": frame_count,
                        "frame_in": frame_in,
                        "frame_out": frame_out,
                        "bid_hours": bid_hours,
                        "actual_hours": actual_hours,
                        "cut_order": shot_num,
                    },
                }
            )

    return shots


def generate_tasks(shots, users):
    """Generate 6 tasks per shot."""
    tasks = []
    task_id = 400

    # Group users by department for assignment
    users_by_dept = {}
    for u in users:
        dept = u["data"]["department"]
        if dept not in users_by_dept:
            users_by_dept[dept] = []
        users_by_dept[dept].append(u["sg_id"])

    # Map task types to departments
    task_dept_map = {
        "Layout": "Layout",
        "Animation": "Animation",
        "FX": "FX",
        "Lighting": "Lighting",
        "Compositing": "Compositing",
        "Review": "Production",
    }

    base_date = datetime(2025, 1, 13)  # Project start + 1 week

    for shot in shots:
        shot_id_val = shot["sg_id"]
        shot_status = shot["data"]["status"]
        shot_bid = shot["data"]["bid_hours"]

        # Distribute bid hours across tasks
        task_bid_weights = {
            "Layout": 0.10,
            "Animation": 0.35,
            "FX": 0.15,
            "Lighting": 0.15,
            "Compositing": 0.20,
            "Review": 0.05,
        }

        # Determine task completion based on shot status
        if shot_status == "Final":
            completed_tasks = 6
        elif shot_status == "Approved":
            completed_tasks = 5
        elif shot_status == "Pending Review":
            completed_tasks = random.randint(4, 5)
        elif shot_status == "In Progress":
            completed_tasks = random.randint(1, 3)
        else:
            completed_tasks = 0

        for task_idx, task_type in enumerate(TASK_TYPES):
            task_id += 1

            # Assign to appropriate department
            dept = task_dept_map[task_type]
            if dept in users_by_dept and users_by_dept[dept]:
                assignee_id = random.choice(users_by_dept[dept])
            else:
                assignee_id = random.choice([u["sg_id"] for u in users])

            # Calculate task bid hours
            task_bid = round(shot_bid * task_bid_weights[task_type], 2)

            # Determine task status and actual hours
            if task_idx < completed_tasks:
                task_status = "Complete"
                variance = random.uniform(0.75, 1.35)
                task_actual = round(task_bid * variance, 2)

                # Calculate dates
                start_offset = task_idx * 3 + random.randint(0, 2)
                duration = max(1, int(task_bid / 8) + random.randint(0, 2))
                start_date = base_date + timedelta(days=start_offset)
                due_date = start_date + timedelta(days=duration + 2)
                completed_date = start_date + timedelta(days=duration)
            elif task_idx == completed_tasks and shot_status in [
                "In Progress",
                "Pending Review",
            ]:
                task_status = "In Progress"
                task_actual = round(task_bid * random.uniform(0.2, 0.7), 2)
                start_offset = task_idx * 3 + random.randint(0, 2)
                start_date = base_date + timedelta(days=start_offset)
                due_date = start_date + timedelta(days=5)
                completed_date = None
            else:
                if task_idx == completed_tasks + 1:
                    task_status = "Ready"
                else:
                    task_status = "Waiting"
                task_actual = 0
                start_offset = task_idx * 3 + random.randint(5, 10)
                start_date = base_date + timedelta(days=start_offset)
                due_date = start_date + timedelta(days=5)
                completed_date = None

            tasks.append(
                {
                    "sg_id": task_id,
                    "data": {
                        "shot_id": shot_id_val,
                        "task_type": task_type,
                        "status": task_status,
                        "assignee_id": assignee_id,
                        "bid_hours": task_bid,
                        "actual_hours": task_actual,
                        "start_date": start_date.strftime("%Y-%m-%d"),
                        "due_date": due_date.strftime("%Y-%m-%d"),
                        "completed_date": completed_date.strftime("%Y-%m-%d")
                        if completed_date
                        else None,
                    },
                }
            )

    return tasks


# ===================
# DATABASE INSERTION
# ===================


def insert_data(conn, table_name, records):
    """Insert records into a raw table."""
    cursor = conn.cursor()

    values = [(r["sg_id"], json.dumps(r["data"])) for r in records]

    query = f"""
        INSERT INTO {table_name} (sg_id, data)
        VALUES %s
        ON CONFLICT (sg_id) DO UPDATE SET
            data = EXCLUDED.data,
            synced_at = NOW()
    """

    execute_values(cursor, query, values)
    conn.commit()
    cursor.close()

    print(f"  ✓ Inserted {len(records)} records into {table_name}")


def main():
    print("=" * 50)
    print("ShotGrid Demo Data Generator")
    print("=" * 50)

    # Generate all data
    print("\n📦 Generating data...")

    users = generate_users()
    print(f"  → {len(users)} users")

    project = generate_project()
    print(f"  → 1 project: {project['data']['name']}")

    episodes = generate_episodes(project["sg_id"])
    print(f"  → {len(episodes)} episodes")

    shots = generate_shots(episodes)
    print(f"  → {len(shots)} shots")

    tasks = generate_tasks(shots, users)
    print(f"  → {len(tasks)} tasks")

    # Connect and insert
    print("\n💾 Inserting into database...")

    try:
        conn = psycopg2.connect(**DB_CONFIG)

        insert_data(conn, "raw_users", users)
        insert_data(conn, "raw_projects", [project])
        insert_data(conn, "raw_episodes", episodes)
        insert_data(conn, "raw_shots", shots)
        insert_data(conn, "raw_tasks", tasks)

        conn.close()

        print("\n✅ Demo data loaded successfully!")
        print("\n📊 Quick Stats:")
        print(f"   Project: {project['data']['code']} - {project['data']['name']}")
        print(f"   Episodes: {len(episodes)}")
        print(f"   Total Shots: {len(shots)}")
        print(f"   Total Tasks: {len(tasks)}")
        print(f"   Team Size: {len(users)} artists")

    except psycopg2.OperationalError as e:
        print(f"\n❌ Database connection failed: {e}")
        print("\nMake sure the Docker stack is running:")
        print("  docker-compose up -d")
        print("  # Wait 30 seconds for Postgres to initialize")
        print("  python seed_data.py")


if __name__ == "__main__":
    main()
