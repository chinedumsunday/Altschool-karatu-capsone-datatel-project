CREATE TABLE IF NOT EXISTS session_buckets (
    session_id TEXT,
    customer_id TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    data_used_mb NUMERIC,
    session_duration_sec NUMERIC,
    duration_bucket TEXT
)