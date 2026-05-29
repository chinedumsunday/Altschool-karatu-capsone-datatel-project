CREATE TABLE IF NOT EXISTS agg_user_usage (
    customer_id TEXT,
    total_data_used_mb NUMERIC,
    avg_session_duration_sec NUMERIC,
    total_sessions INTEGER
);