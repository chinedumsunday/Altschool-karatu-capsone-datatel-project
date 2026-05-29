DELETE FROM stg_billing
WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}';

INSERT INTO stg_billing (transaction_id, customer_id, amount, currency, transaction_date)
SELECT transaction_id, customer_id, amount, currency, transaction_date
FROM (
    SELECT transaction_id, customer_id,
           ROUND(COALESCE(amount::numeric, 0), 2) AS amount,
           CASE WHEN currency = 'Naira' THEN 'NGN'
                WHEN currency = 'ngn' THEN 'NGN'
                ELSE 'NGN' END AS currency,
           transaction_date::timestamp,
           ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_date DESC) AS rn
    FROM src_billing_transactions
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
) sub
WHERE rn = 1;