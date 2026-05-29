
INSERT INTO quarantine (row_details, source_table)
SELECT to_jsonb(src_billing_transactions), 'src_billing_transactions'
FROM src_billing_transactions
WHERE transaction_id IS NULL;

