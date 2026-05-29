DELETE FROM stg_sessions
WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}';

INSERT INTO stg_sessions (session_id, customer_id, start_time, end_time, data_used_mb, session_duration_sec)
SELECT 
    session_id, 
    customer_id, 
    start_time::timestamp, 
    end_time::timestamp, 
    COALESCE(data_used_mb::numeric, 0) AS data_used_mb, 
    CASE WHEN end_time::timestamp > start_time::timestamp 
         THEN EXTRACT(EPOCH FROM end_time::timestamp - start_time::timestamp) 
         ELSE 0 END AS session_duration_sec 
FROM src_network_sessions
WHERE start_time >= '{{ params.t_start }}' AND start_time < '{{ params.t_end }}';