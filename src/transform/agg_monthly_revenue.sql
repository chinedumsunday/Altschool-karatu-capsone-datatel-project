DELETE FROM agg_monthly_revenue
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
);

INSERT INTO agg_monthly_revenue (customer_id, month, total_revenue)
SELECT customer_id, date_trunc('month', transaction_date) AS month, sum(amount) AS total_revenue 
FROM stg_billing
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}' AND transaction_date < '{{ params.t_end }}'
)
GROUP BY customer_id, month
ORDER BY month DESC, total_revenue DESC;