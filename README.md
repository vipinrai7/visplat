# ShotGrid Demo Stack

A self-contained demo environment for the Internal Data Visualization & Reporting Platform strategy. Includes TimescaleDB (PostgreSQL + time-series), Metabase, and Apache Superset with realistic animation production data.

## What's Included

| Component | Port | Purpose |
|-----------|------|---------|
| TimescaleDB (PostgreSQL 15) | 5432 | Data warehouse + time-series |
| Metabase | 3000 | Coordinator dashboards (Excel-like) |
| Apache Superset | 8088 | Executive visualizations |

> **Note:** Superset's lean image doesn't include database drivers. We use a custom Dockerfile (`superset/Dockerfile`) that layers `psycopg2-binary` on top of the official image.

### Demo Data

- **1 Project:** "Cosmos: A Space Journey"
- **3 Episodes:** EP101, EP102, EP103
- **30 Shots:** 10 per episode with frame counts, bid/actual hours
- **180 Tasks:** Layout → Animation → FX → Lighting → Compositing → Review
- **12 Users:** Across 6 departments

### Time-Series Data (TimescaleDB Hypertables)

- **Status History:** Track when shots/tasks changed status over time
- **Time Logs:** Daily hour entries per user/task

---

## Quick Start

### Prerequisites

- Docker & Docker Compose installed
- Python 3.8+ with `psycopg2` (`pip install psycopg2-binary`)
- ~2GB free disk space

### 1. Start the Stack

```bash
cd shotgrid-demo
docker-compose up -d
```

Wait ~60 seconds for all services to initialize. Check status:

```bash
docker-compose ps
```

All three containers should show "Up" or "healthy".

### 2. Load Demo Data

**Option A: Using Helper Scripts (Easiest)**

**Windows:**
```cmd
seed.bat
```

**Linux/Mac:**
```bash
./seed.sh
```

These scripts automatically start PostgreSQL and wait for it to be ready before seeding.

**Option B: Using Docker Manually**

```bash
# Ensure postgres is running
docker-compose up -d postgres

# Wait for postgres to be healthy (30-60 seconds)
docker-compose ps

# Run the containerized seeding tool
docker-compose run --rm seeding_tool
```

**Option C: Using Local Python**

```bash
pip install psycopg2-binary  # if not installed
python seed_data.py
```

You should see:
```
✓ Inserted 12 records into raw_users
✓ Inserted 1 records into raw_projects
✓ Inserted 3 records into raw_episodes
✓ Inserted 30 records into raw_shots
✓ Inserted 180 records into raw_tasks
```

> **Note:** The seeding tool container is built with Poetry and includes all dependencies from `pyproject.toml`.

### 3. Access the Tools

| Tool | URL | Credentials |
|------|-----|-------------|
| **Metabase** | http://localhost:3000 | Set up on first visit |
| **Superset** | http://localhost:8088 | admin / admin |

---

## Metabase Setup (First Time)

1. Go to http://localhost:3000
2. Click "Let's get started"
3. Create your admin account
4. When asked to add a database:
   - **Database type:** PostgreSQL
   - **Host:** postgres (not localhost!)
   - **Port:** 5432
   - **Database name:** shotgrid_demo
   - **Username:** read_only_user
   - **Password:** readonly123

### Recommended First Questions

Try these in Metabase's "New Question" → "Native query":

```sql
-- Shot status by episode
SELECT episode_code, status, COUNT(*) as shot_count
FROM view_shot_status_summary
GROUP BY episode_code, status
ORDER BY episode_code, status;
```

```sql
-- Tasks over budget
SELECT shot_code, task_type, assignee_name, 
       task_bid_hours, task_actual_hours, task_efficiency_pct
FROM view_production_tasks
WHERE task_efficiency_pct > 100
ORDER BY task_efficiency_pct DESC;
```

```sql
-- User workload
SELECT * FROM view_user_workload
ORDER BY active_tasks DESC;
```

---

## Superset Setup (First Time)

1. Go to http://localhost:8088
2. Login: admin / admin
3. Add database connection:
   - Settings (gear icon) → Database Connections → + Database
   - Select PostgreSQL
   - **SQLAlchemy URI:** `postgresql://read_only_user:readonly123@postgres:5432/shotgrid_demo`
   - Test connection, then save

### Recommended First Chart

1. Go to Charts → + Chart
2. Select `view_production_tasks` as dataset
3. Try a "Bar Chart" showing task counts by status and department

---

## Available Views

These are pre-built for dashboards:

| View | Best For | Key Columns |
|------|----------|-------------|
| `view_production_tasks` | Detailed task grid | All columns joined |
| `view_shot_status_summary` | Episode progress | Shot counts, bid vs actual |
| `view_department_burndown` | Burn rate by dept | Completed vs remaining |
| `view_user_workload` | Individual capacity | Active tasks, overdue count |

### TimescaleDB Time-Series Views

| View | Best For | Key Columns |
|------|----------|-------------|
| `view_daily_status_changes` | Activity trends | day, entity_type, change_count |
| `view_daily_hours` | Time tracking | day, user_id, total_hours |
| `view_weekly_burndown` | Sprint progress | week, tasks_completed, tasks_started |

### TimescaleDB Hypertables (Raw)

| Table | Purpose | Use With |
|-------|---------|----------|
| `status_history` | All status change events | `time_bucket()` for aggregation |
| `time_logs` | Individual time entries | `time_bucket()` for daily/weekly sums |

#### Example TimescaleDB Queries

```sql
-- Tasks completed per day (last 30 days)
SELECT 
    time_bucket('1 day', time) AS day,
    COUNT(*) AS completed
FROM status_history
WHERE new_status = 'Complete' 
  AND entity_type = 'task'
  AND time > NOW() - INTERVAL '30 days'
GROUP BY day
ORDER BY day;

-- Cumulative hours by user per week
SELECT 
    time_bucket('1 week', time) AS week,
    user_id,
    SUM(hours_logged) AS weekly_hours
FROM time_logs
GROUP BY week, user_id
ORDER BY week, user_id;
```

---

## Database Access

### Direct Connection (for testing)

```bash
# Using psql
psql -h localhost -U admin -d shotgrid_demo
# Password: demodemo123

# Or via Docker
docker exec -it shotgrid_postgres psql -U admin -d shotgrid_demo
```

### Connection Strings

| User | Use Case | Connection String |
|------|----------|-------------------|
| admin | Full access | `postgresql://admin:demodemo123@localhost:5432/shotgrid_demo` |
| read_only_user | BI tools | `postgresql://read_only_user:readonly123@localhost:5432/shotgrid_demo` |

---

## Stopping the Stack

```bash
# Stop but keep data
docker-compose down

# Stop and DELETE all data
docker-compose down -v
```

---

## Seeding Tool Container

The project includes a containerized seeding tool that runs in an isolated environment with all dependencies managed by Poetry.

### Quick Usage

**Using Helper Scripts (Recommended):**

```bash
# Windows
seed.bat

# Linux/Mac
./seed.sh
```

**Manual Docker Commands:**

```bash
# Run the seeding tool (waits for postgres to be healthy)
docker-compose run --rm seeding_tool

# Rebuild after dependency changes
docker-compose build seeding_tool
```

### Configuration

The seeding tool connects to the PostgreSQL database using environment variables (configured in `docker-compose.yml`):
- `PGHOST=postgres` - Database host
- `PGPORT=5432` - Database port  
- `PGDATABASE=shotgrid_demo` - Database name
- `PGUSER=admin` - Database user
- `PGPASSWORD=demodemo123` - Database password

For more details, see [SEEDING_TOOL.md](SEEDING_TOOL.md).

---

## Troubleshooting

### "Connection refused" when running seed_data.py

Postgres isn't ready yet. Wait 30-60 seconds after `docker-compose up`.

### Metabase shows "postgres" as host, not "localhost"

This is correct! Inside Docker, containers communicate using service names. Use `postgres` when configuring from Metabase/Superset, use `localhost` when connecting from your host machine.

### Superset stuck on "Loading..."

The first startup takes 2-3 minutes while it runs migrations. Check logs:

```bash
docker-compose logs -f superset
```

### Need to reset everything

```bash
docker-compose down -v
docker-compose up -d
# Wait 60 seconds
python seed_data.py
```

### Windows: Line ending issues

If you see errors like `syntax error at or near "..."` in SQL or `$'\r': command not found` in shell:

1. The repo includes `.gitattributes` to enforce LF line endings
2. If you cloned before this file existed, run:
   ```bash
   git config core.autocrlf false
   git rm --cached -r .
   git reset --hard
   ```
3. Or re-clone the repository

### Windows: Docker Desktop requirements

- Ensure Docker Desktop is running with WSL 2 backend (recommended)
- If using Hyper-V backend, ensure you have enough memory allocated (4GB minimum)

---

## Next Steps for Demo

1. **Coordinator Demo (Metabase):**
   - Show the "Questions" feature
   - Demonstrate CSV export
   - Build a simple filter on `view_production_tasks`

2. **Executive Demo (Superset):**
   - Create a bar chart: shots by status per episode
   - Create a pie chart: task distribution by department
   - Show the SQL Lab for ad-hoc queries

3. **Talking Points:**
   - All data stays on-prem (TPN compliant)
   - Zero licensing cost
   - Single VM deployment
   - Real-time updates from ShotGrid (simulated here)
