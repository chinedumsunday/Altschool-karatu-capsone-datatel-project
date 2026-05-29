DELETE FROM agg_session_distribution
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
);
INSERT INTO agg_session_distribution (customer_id, short_sessions, medium_sessions, long_sessions)
SELECT customer_id, COUNT(*) FILTER (WHERE duration_bucket = 'short') AS short_sessions,
COUNT(*) FILTER (WHERE duration_bucket = 'medium') AS medium_sessions,
COUNT(*) FILTER (WHERE duration_bucket = 'long') AS long_sessions
FROM session_buckets
where customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
)
GROUP BY customer_id;