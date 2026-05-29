CREATE TABLE IF NOT EXISTS stg_sessions (
    session_id TEXT, 
    customer_id TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    data_used_mb NUMERIC,
    session_duration_sec NUMERIC
);