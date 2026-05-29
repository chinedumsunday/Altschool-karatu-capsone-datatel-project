TRUNCATE stg_customers;

INSERT INTO stg_customers (customer_id, name, email, country, created_at)
SELECT customer_id, name, email, country, created_at
FROM (
    SELECT customer_id,
           INITCAP(name) AS name,
           LOWER(email) AS email,
           COALESCE(country, 'Nigeria') AS country,
           created_at::timestamp,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at DESC) AS rn
    FROM src_customers
) sub
WHERE rn = 1;