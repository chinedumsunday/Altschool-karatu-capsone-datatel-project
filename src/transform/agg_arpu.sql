DELETE FROM agg_arpu
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
);

INSERT INTO agg_arpu (customer_id, arpu)
SELECT customer_id,
       Round(COALESCE(SUM(amount) / NULLIF(COUNT(DISTINCT date_trunc('month', transaction_date)), 0), 0), 2) AS arpu
FROM stg_billing
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
)
GROUP BY customer_id;