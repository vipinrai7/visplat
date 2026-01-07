-- ============================================
-- ShotGrid Demo Database Schema
-- Strategy: "Lazy Loading" with JSONB + Views
-- ============================================

-- ===================
-- RAW DATA TABLES (JSONB)
-- These simulate the "Lazy Loading" approach from the strategy doc
-- ===================

CREATE TABLE raw_projects (
    id SERIAL PRIMARY KEY,
    sg_id INTEGER UNIQUE NOT NULL,
    data JSONB NOT NULL,
    synced_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE raw_episodes (
    id SERIAL PRIMARY KEY,
    sg_id INTEGER UNIQUE NOT NULL,
    data JSONB NOT NULL,
    synced_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE raw_shots (
    id SERIAL PRIMARY KEY,
    sg_id INTEGER UNIQUE NOT NULL,
    data JSONB NOT NULL,
    synced_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE raw_tasks (
    id SERIAL PRIMARY KEY,
    sg_id INTEGER UNIQUE NOT NULL,
    data JSONB NOT NULL,
    synced_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE raw_users (
    id SERIAL PRIMARY KEY,
    sg_id INTEGER UNIQUE NOT NULL,
    data JSONB NOT NULL,
    synced_at TIMESTAMP DEFAULT NOW()
);

-- ===================
-- PARSED VIEWS
-- These flatten the JSONB into queryable columns
-- ===================

-- Users View
CREATE VIEW view_users AS
SELECT
    sg_id AS user_id,
    data->>'name' AS name,
    data->>'email' AS email,
    data->>'department' AS department,
    (data->>'is_active')::BOOLEAN AS is_active,
    synced_at
FROM raw_users;

-- Projects View
CREATE VIEW view_projects AS
SELECT
    sg_id AS project_id,
    data->>'code' AS project_code,
    data->>'name' AS project_name,
    data->>'status' AS status,
    (data->>'start_date')::DATE AS start_date,
    (data->>'end_date')::DATE AS end_date,
    synced_at
FROM raw_projects;

-- Episodes View
CREATE VIEW view_episodes AS
SELECT
    re.sg_id AS episode_id,
    (re.data->>'project_id')::INTEGER AS project_id,
    re.data->>'code' AS episode_code,
    re.data->>'name' AS episode_name,
    re.data->>'status' AS status,
    (re.data->>'cut_order')::INTEGER AS cut_order,
    re.synced_at
FROM raw_episodes re;

-- Shots View (includes bid/actual hours)
CREATE VIEW view_shots AS
SELECT
    rs.sg_id AS shot_id,
    (rs.data->>'episode_id')::INTEGER AS episode_id,
    rs.data->>'code' AS shot_code,
    rs.data->>'name' AS shot_name,
    rs.data->>'status' AS status,
    (rs.data->>'frame_count')::INTEGER AS frame_count,
    (rs.data->>'frame_in')::INTEGER AS frame_in,
    (rs.data->>'frame_out')::INTEGER AS frame_out,
    (rs.data->>'bid_hours')::DECIMAL(10,2) AS bid_hours,
    (rs.data->>'actual_hours')::DECIMAL(10,2) AS actual_hours,
    (rs.data->>'cut_order')::INTEGER AS cut_order,
    rs.synced_at
FROM raw_shots rs;

-- Tasks View (includes bid/actual hours and assignee)
CREATE VIEW view_tasks AS
SELECT
    rt.sg_id AS task_id,
    (rt.data->>'shot_id')::INTEGER AS shot_id,
    rt.data->>'task_type' AS task_type,
    rt.data->>'status' AS status,
    (rt.data->>'assignee_id')::INTEGER AS assignee_id,
    (rt.data->>'bid_hours')::DECIMAL(10,2) AS bid_hours,
    (rt.data->>'actual_hours')::DECIMAL(10,2) AS actual_hours,
    (rt.data->>'start_date')::DATE AS start_date,
    (rt.data->>'due_date')::DATE AS due_date,
    (rt.data->>'completed_date')::DATE AS completed_date,
    rt.synced_at
FROM raw_tasks rt;

-- ===================
-- DENORMALIZED PRODUCTION VIEWS
-- These are the "money views" for dashboards
-- ===================

-- Full Production Tasks View (joins everything)
CREATE VIEW view_production_tasks AS
SELECT
    p.project_code,
    p.project_name,
    e.episode_code,
    e.episode_name,
    s.shot_code,
    s.shot_name,
    s.status AS shot_status,
    s.frame_count,
    s.bid_hours AS shot_bid_hours,
    s.actual_hours AS shot_actual_hours,
    t.task_type,
    t.status AS task_status,
    t.bid_hours AS task_bid_hours,
    t.actual_hours AS task_actual_hours,
    t.start_date,
    t.due_date,
    t.completed_date,
    u.name AS assignee_name,
    u.department AS assignee_department,
    -- Calculated fields
    CASE 
        WHEN t.bid_hours > 0 THEN ROUND((t.actual_hours / t.bid_hours) * 100, 1)
        ELSE NULL 
    END AS task_efficiency_pct,
    CASE
        WHEN t.due_date < CURRENT_DATE AND t.status != 'Complete' THEN TRUE
        ELSE FALSE
    END AS is_overdue
FROM view_tasks t
JOIN view_shots s ON t.shot_id = s.shot_id
JOIN view_episodes e ON s.episode_id = e.episode_id
JOIN view_projects p ON e.project_id = p.project_id
LEFT JOIN view_users u ON t.assignee_id = u.user_id;

-- Shot Status Summary (for executive dashboards)
CREATE VIEW view_shot_status_summary AS
SELECT
    p.project_code,
    e.episode_code,
    s.status,
    COUNT(*) AS shot_count,
    SUM(s.frame_count) AS total_frames,
    SUM(s.bid_hours) AS total_bid_hours,
    SUM(s.actual_hours) AS total_actual_hours,
    ROUND(AVG(
        CASE WHEN s.bid_hours > 0 THEN (s.actual_hours / s.bid_hours) * 100 END
    ), 1) AS avg_efficiency_pct
FROM view_shots s
JOIN view_episodes e ON s.episode_id = e.episode_id
JOIN view_projects p ON e.project_id = p.project_id
GROUP BY p.project_code, e.episode_code, s.status;

-- Task Burndown by Department
CREATE VIEW view_department_burndown AS
SELECT
    p.project_code,
    e.episode_code,
    u.department,
    t.task_type,
    COUNT(*) FILTER (WHERE t.status = 'Complete') AS completed_tasks,
    COUNT(*) FILTER (WHERE t.status != 'Complete') AS remaining_tasks,
    COUNT(*) AS total_tasks,
    SUM(t.bid_hours) AS total_bid_hours,
    SUM(t.actual_hours) AS total_actual_hours,
    SUM(t.bid_hours) FILTER (WHERE t.status != 'Complete') AS remaining_bid_hours
FROM view_tasks t
JOIN view_shots s ON t.shot_id = s.shot_id
JOIN view_episodes e ON s.episode_id = e.episode_id
JOIN view_projects p ON e.project_id = p.project_id
LEFT JOIN view_users u ON t.assignee_id = u.user_id
GROUP BY p.project_code, e.episode_code, u.department, t.task_type;

-- User Workload Summary
CREATE VIEW view_user_workload AS
SELECT
    u.name AS user_name,
    u.department,
    COUNT(*) FILTER (WHERE t.status = 'In Progress') AS active_tasks,
    COUNT(*) FILTER (WHERE t.status = 'Complete') AS completed_tasks,
    SUM(t.bid_hours) AS total_bid_hours,
    SUM(t.actual_hours) AS total_actual_hours,
    COUNT(*) FILTER (WHERE t.due_date < CURRENT_DATE AND t.status != 'Complete') AS overdue_tasks
FROM view_users u
LEFT JOIN view_tasks t ON u.user_id = t.assignee_id
WHERE u.is_active = TRUE
GROUP BY u.user_id, u.name, u.department;

-- ===================
-- READ-ONLY USER FOR BI TOOLS
-- ===================

CREATE USER read_only_user WITH PASSWORD 'readonly123';
GRANT CONNECT ON DATABASE shotgrid_demo TO read_only_user;
GRANT USAGE ON SCHEMA public TO read_only_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_only_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO read_only_user;
