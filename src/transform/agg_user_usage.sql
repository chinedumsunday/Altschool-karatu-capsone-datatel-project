DELETE FROM agg_user_usage
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
);

INSERT INTO agg_user_usage (customer_id, total_data_consumed, avg_session_duration_sec, total_sessions)
SELECT customer_id, SUM(data_used_mb), AVG(session_duration_sec), COUNT(session_id)
FROM stg_sessions
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
)
GROUP BY customer_id;