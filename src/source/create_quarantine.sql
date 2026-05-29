CREATE TABLE IF NOT EXISTS quarantine (
    row_details JSONB,
    source_table TEXT,
    detected_at TIMESTAMPTZ DEFAULT NOW()
);