-- SELECT transaction_id, count(*) FROM src_billing_transactions
-- GROUP BY transaction_id
-- HAVING COUNT(*) > 1
-- LIMIT 5;

INSERT INTO quarantine (row_details, source_table)
SELECT to_jsonb(src_billing_transactions), 'src_billing_transactions'
FROM src_billing_transactions 
WHERE transaction_id IN (
    SELECT transaction_id
    FROM src_billing_transactions
    GROUP BY transaction_id
    HAVING COUNT(*) > 1
);

-- SELECT session_id, count(*) FROM src_network_sessions
-- GROUP BY session_id
-- HAVING COUNT(*) > 1
-- LIMIT 5;

INSERT  INTO quarantine (row_details, source_table)
SELECT to_jsonb(src_network_sessions), 'src_network_sessions'
FROM src_network_sessions
WHERE session_id IN (
    SELECT session_id
    FROM src_network_sessions
    GROUP BY session_id
    HAVING COUNT(*) > 1
);

-- select * from quarantine
-- where source_table in ('src_billing_transactions', 'src_network_sessions')
-- LIMIT 10;