DELETE FROM agg_user_revenue
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
);

INSERT INTO agg_user_revenue (customer_id, total_revenue, total_transactions)
SELECT customer_id, SUM(amount), COUNT(transaction_id)
FROM stg_billing
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
)
GROUP BY customer_id;