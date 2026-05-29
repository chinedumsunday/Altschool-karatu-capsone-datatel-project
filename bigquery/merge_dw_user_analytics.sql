MERGE `datatel-497610.datatel_warehouse.dw_user_analytics` AS target
USING (
    SELECT
        c.customer_id,
        c.name AS customer_name,
        c.email,
        c.country,
        TIMESTAMP(c.created_at) AS customer_since,
        COALESCE(r.total_revenue, 0) AS total_revenue,
        COALESCE(r.total_transactions, 0) AS total_transactions,
        COALESCE(u.total_data_consumed, 0) AS total_data_used_mb,
        COALESCE(u.avg_session_duration_sec, 0) AS avg_session_duration_sec,
        COALESCE(u.total_sessions, 0) AS total_sessions,
        COALESCE(a.arpu, 0) AS arpu,
        COALESCE(d.short_sessions, 0) AS short_sessions,
        COALESCE(d.medium_sessions, 0) AS medium_sessions,
        COALESCE(d.long_sessions, 0) AS long_sessions,
        COALESCE(u.total_data_consumed / NULLIF(u.total_sessions, 0), 0) AS avg_data_per_session_mb
    FROM `datatel-497610.datatel_warehouse.stg_customers` c
    LEFT JOIN `datatel-497610.datatel_warehouse.agg_user_revenue` r USING (customer_id)
    LEFT JOIN `datatel-497610.datatel_warehouse.agg_user_usage` u USING (customer_id)
    LEFT JOIN `datatel-497610.datatel_warehouse.agg_arpu` a USING (customer_id)
    LEFT JOIN `datatel-497610.datatel_warehouse.agg_session_distribution` d USING (customer_id)
) AS source
ON target.customer_id = source.customer_id
WHEN MATCHED THEN
    UPDATE SET
        customer_name = source.customer_name,
        email = source.email,
        country = source.country,
        customer_since = source.customer_since,
        total_revenue = source.total_revenue,
        total_transactions = source.total_transactions,
        total_data_used_mb = source.total_data_used_mb,
        avg_session_duration_sec = source.avg_session_duration_sec,
        total_sessions = source.total_sessions,
        arpu = source.arpu,
        short_sessions = source.short_sessions,
        medium_sessions = source.medium_sessions,
        long_sessions = source.long_sessions,
        avg_data_per_session_mb = source.avg_data_per_session_mb
WHEN NOT MATCHED THEN
    INSERT (customer_id, customer_name, email, country, customer_since,
            total_revenue, total_transactions, total_data_used_mb,
            avg_session_duration_sec, total_sessions, arpu,
            short_sessions, medium_sessions, long_sessions, avg_data_per_session_mb)
    VALUES (source.customer_id, source.customer_name, source.email, source.country, source.customer_since,
            source.total_revenue, source.total_transactions, source.total_data_used_mb,
            source.avg_session_duration_sec, source.total_sessions, source.arpu,
            source.short_sessions, source.medium_sessions, source.long_sessions, source.avg_data_per_session_mb);