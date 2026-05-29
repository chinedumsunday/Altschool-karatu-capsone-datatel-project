CREATE TABLE IF NOT EXISTS stg_billing (
    transaction_id TEXT, 
    customer_id TEXT,
    amount NUMERIC(12, 2),
    currency TEXT,
    transaction_date TIMESTAMP
)