CREATE TABLE IF NOT EXISTS src_billing_transactions (
    transaction_id TEXT, 
    customer_id TEXT,
    amount TEXT, 
    currency TEXT,
    transaction_date TEXT
);

CREATE TABLE IF NOT EXISTS src_customers (
    customer_id TEXT, 
    name TEXT, 
    email TEXT,
    country TEXT, 
    created_at TEXT
);

CREATE TABLE IF NOT EXISTS src_network_sessions (
    session_id TEXT, 
    customer_id TEXT,
    start_time TEXT,
    end_time TEXT,
    data_used_mb TEXT
);

\copy src_billing_transactions FROM './data/src_billing_transactions.csv' DELIMITER ',' CSV HEADER;
\copy src_customers FROM './data/src_customers.csv' DELIMITER ',' CSV HEADER;  
\copy src_network_sessions FROM './data/src_network_sessions.csv' DELIMITER ',' CSV HEADER;