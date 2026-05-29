

INSERT INTO quarantine (row_details, source_table)
SELECT to_jsonb(src_customers), 'src_customers'
FROM src_customers
WHERE customer_id IS NULL;