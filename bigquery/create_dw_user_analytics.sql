CREATE TABLE IF NOT EXISTS `datatel-497610.datatel_warehouse.dw_user_analytics` (
    customer_id STRING,
    customer_name STRING,
    email STRING,
    country STRING,
    customer_since TIMESTAMP,
    total_revenue FLOAT64,
    total_transactions INT64,
    total_data_used_mb FLOAT64,
    avg_session_duration_sec FLOAT64,
    total_sessions INT64,
    arpu FLOAT64,
    short_sessions INT64,
    medium_sessions INT64,
    long_sessions INT64,
    avg_data_per_session_mb FLOAT64
);