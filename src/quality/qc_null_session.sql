INSERT INTO quarantine (row_details, source_table)
SELECT to_jsonb(src_network_sessions), 'src_network_sessions'
FROM src_network_sessions
WHERE session_id IS NULL;