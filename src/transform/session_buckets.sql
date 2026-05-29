DELETE FROM session_buckets
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
);
INSERT INTO session_buckets (session_id, customer_id, start_time, end_time, data_used_mb, session_duration_sec, duration_bucket)
SELECT session_id, customer_id, start_time, end_time, data_used_mb, session_duration_sec,
         CASE 
              WHEN session_duration_sec < 60 THEN 'short'
              WHEN session_duration_sec < 300 THEN 'medium'
              ELSE 'long'
         END AS duration_bucket
FROM stg_sessions
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_sessions
    WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}'
);
