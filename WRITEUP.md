# DataTel Communications — Pipeline Writeup

This document contains the full written deliverables for the Automated Telecom Data Pipeline capstone: justifications for the design choices made at each pipeline stage, and answers to the seven discussion questions in the instruction.

---

## 1. Quality Check Notes (Stage 1)

Four quality checks run before any data is loaded. Each writes offending rows to a `quarantine` table (JSONB row snapshot + source table + detected_at timestamp) for later inspection.

**qc_null_transaction** — Detects rows in `src_billing_transactions` where `transaction_id` is NULL. A transaction without an identifier cannot be deduplicated, cannot be reconciled with billing system retries, and cannot be tied to a customer's history. If allowed downstream, these rows would silently inflate aggregate counts (`total_transactions`) without any way to trace or correct the inflation later.

**qc_null_session** — Detects rows in `src_network_sessions` where `session_id` is NULL. The same reasoning as transactions: without a session_id, deduplication is impossible, and the row could be double-counted on any retry. It would also corrupt `total_sessions` and the session-duration distribution.

**qc_null_customers** — Detects rows in `src_customers` where `customer_id` is NULL. A customer without an identifier breaks the join key the entire warehouse depends on; orphaned attribute data (name, email, country) would land in stg_customers with no way to attach it to billing or sessions data.

**qc_duplicates** — Detects rows in `src_billing_transactions` and `src_network_sessions` whose primary identifiers appear more than once. Duplicates exist legitimately in source data (the instruction says both billing and network systems retry on failure), but they must be detected so that the staging layer's dedup logic doesn't have to silently absorb genuine data-quality issues. The quarantine snapshot lets operations review whether a duplicate is a benign retry or a sign of a deeper integrity problem.

Note on current findings: the actual generated dataset returned zero null primary identifiers across all three sources. The checks remain in place as defensive guards production telecom systems frequently have null-ID anomalies, and the checks gate downstream loads whether or not today's batch happens to contain them.

---

## 2. stg_billing Deduplication Justification

`src_billing_transactions` contains ~30,000 deliberate duplicate `transaction_id`s simulating real billing-system retries. The staging layer must keep exactly one row per transaction_id, and the instruction specifies *the most recent record where duplicates exist*.

The chosen approach is `ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_date DESC)` followed by `WHERE rn = 1`. Alternatives considered:

- **DISTINCT** — discards information about which duplicate to keep; you get one row but no control over which one, which would violate the "most recent" requirement.
- **GROUP BY transaction_id with MIN/MAX aggregations** — requires aggregating every non-key column, which collapses the row identity and loses the ability to keep a specific record as the "winner."
- **NOT EXISTS subqueries** — readable but performs poorly at scale (~1.5M rows) and is harder to combine with the timestamp ordering.

ROW_NUMBER is the standard SQL idiom for "keep one row per key, by a tie-breaker" and translates the instructions's requirement directly into the WHERE clause. It also composes cleanly with the rest of the staging transformations (currency normalization, type casting, COALESCE on amount), so all of stg_billing's logic stays in a single readable subquery.

---

## 3. stg_customers Deduplication Justification

`src_customers` contains ~1,000 deliberate duplicate customer rows. Initially the customers load was a clean full-refresh (TRUNCATE + INSERT) without dedup, on the assumption that source customers were unique. When the BigQuery MERGE step ran, it failed with `UPDATE/MERGE must match at most one source row for each target row` — duplicate customer_ids in the join source violated MERGE's 1-to-1 requirement.

The fix applied the same ROW_NUMBER pattern as billing: `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at DESC) WHERE rn = 1`. This both resolved the MERGE failure and produced a cleaner stg_customers that any downstream consumer can rely on.

This is also why all dedup logic lives at the staging layer rather than being deferred to downstream JOINs: the moment a duplicate flows into staging, every JOIN downstream becomes ambiguous, and the failure can surface far from the cause.

---

## 4. agg_arpu Division Risk Justification

ARPU is defined as `total_revenue / number_of_distinct_active_months`. Two failure modes had to be guarded against:

**Division by zero** — a customer with no transactions has zero active months. Postgres raises `division by zero` on `x / 0`, which would fail the entire aggregate task. Guarded with `NULLIF(COUNT(DISTINCT date_trunc('month', transaction_date)), 0)` — when the denominator is 0, NULLIF returns NULL, and `x / NULL` evaluates to NULL rather than erroring.

**Spurious NULL in the result** — the instruction requires zero, not NULL, for customers with no transactions. The NULL from the NULLIF path is wrapped in `COALESCE(..., 0)`, converting it to the required 0.

The final expression is `ROUND(COALESCE(SUM(amount) / NULLIF(COUNT(DISTINCT date_trunc('month', transaction_date)), 0), 0), 2)`. Round to 2 decimal places for currency presentation. This NULLIF-then-COALESCE pattern is used identically for `avg_data_per_session_mb` in the warehouse view, for the same reason: a customer with zero sessions cannot have an average per session, so the safe value is 0.

---

## 5. dw_user_analytics Join Strategy Justification

The instruction requires every customer to appear in `dw_user_analytics`, even those with no billing or session records, and metrics with no matching data must default to 0 rather than NULL.

**Base table: stg_customers.** It contains the complete customer roster (101,000 rows). Starting the join from any aggregate (which only contains the subset of customers with that kind of activity — 91k for billing, 97k for sessions) would silently drop the ~10,000 customers with no transactions and ~3,400 with no sessions, violating the "every customer must appear" requirement.

**LEFT JOIN onto each aggregate.** A LEFT JOIN preserves every left-side row (every customer) even when the right side (the aggregate) has no match. INNER JOIN would have produced an intersection — exactly what the instruction forbids.

**COALESCE every metric column to 0.** LEFT JOIN produces NULLs for unmatched aggregate rows; the instruction requires 0. Every metric column is wrapped: `COALESCE(r.total_revenue, 0)`, `COALESCE(u.total_sessions, 0)`, etc. Customer identity columns (customer_id, name, email, country, created_at) are not COALESCE'd because they come from the base table and cannot be NULL.

**Derived `avg_data_per_session_mb` guarded against divide-by-zero.** Computed as `COALESCE(u.total_data_used_mb / NULLIF(u.total_sessions, 0), 0)` — same defensive pattern as ARPU. Customers with no sessions get 0 rather than NULL or an error.

The result: 101,000 rows in `dw_user_analytics`, no NULL metrics, every customer represented, including transaction-less and session-less customers with all-zero metrics — confirmed via row count and a no-NULL diagnostic query.

---

## 6. Currency Normalization Note

`src_billing_transactions.currency` contains three variants of the same currency: `'Naira'`, `'ngn'`, and `'NGN'`. All three refer to the Nigerian Naira; the variation is purely formatting inconsistency from upstream systems.

The staging layer normalizes all three to `'NGN'` (the ISO 4217 code) via a CASE expression. Aggregations downstream (revenue, ARPU) assume a single currency, so leaving the variants in place would produce no immediate bug but would silently break any future use case that wants to group or filter by currency (a multi-currency rollout, FX reporting, settlement reconciliation).

This was treated as a deliberate test of source-data attention, and is handled at the staging layer where all such normalization belongs. The instruction did not flag it explicitly, but it was handled ayway because mirroring production level engineering it should be handled also.

---

## 7. BigQuery Write Strategy Justification (MERGE)

The instruction requires the warehouse write to handle three cases: new customers (first time appearing), returning customers (update their row with fresh metrics), and re-running safety (no duplicates on a second run of the same window). A plain CREATE OR REPLACE would handle the rerun case but tears down and rebuilds the whole table, which (a) doesn't distinguish new from returning, (b) is wasteful as the table grows, and (c) requires read access to all source aggregates even when only a small subset of customers changed.

The chosen strategy is BigQuery's MERGE statement against `dw_user_analytics`, with `customer_id` as the match key:

- `WHEN MATCHED THEN UPDATE` — overwrites every column for returning customers with the freshly computed values. Handles the "returning customer with new transactions/sessions" case.
- `WHEN NOT MATCHED THEN INSERT` — adds new customers whose first activity appears in this run. Handles the "first-time customer" case.

The MERGE source is the same LEFT-JOIN query that produced the table originally, so the row shape and COALESCE/NULLIF guards remain identical. Re-running the same window is safe: matched rows simply get re-updated with the same values, unmatched rows aren't re-inserted (they're already there).

DDL note: `dw_user_analytics` must exist before the MERGE runs. A separate `create_dw_user_analytics.sql` (CREATE TABLE IF NOT EXISTS) runs first, idempotently — it builds the table on a fresh deployment, and is a no-op when it already exists. This mirrors the create/load split used throughout the Postgres-side staging and aggregate layers.

Billing note: BigQuery's free tier does not allow DML (INSERT, UPDATE, DELETE, MERGE). The project has billing enabled to allow the MERGE to run.

---

# Discussion Questions

## Q1. Staging incremental boundary — how is "already loaded" distinguished from "new," and what happens to late-arriving records?

The boundary is a date window on the source's natural activity timestamp, supplied by Airflow parameters with sensible defaults:

```sql
WHERE transaction_date >= '{{ params.t_start }}'
  AND transaction_date < '{{ params.t_end }}'
```

For a daily run, `t_start` and `t_end` default to the run's logical date and the day after (a 24-hour window). The window is **bounded** (`>= start AND < end`) rather than open-ended (`>= start`) so that re-running a single specific day reprocesses exactly that day and nothing else.

Each staging load does **DELETE-then-INSERT** of the window: delete from staging where the date column falls in the window, then insert the freshly cleaned-and-deduplicated rows from source for the same window. This makes the load both incremental (only one day's slice processed per run) and idempotent (re-running a day deletes that day's rows and re-inserts them identically — same end state every time).

**Late records (record arrives two days after its real event date):** the record carries its true `transaction_date` in the past. A normal scheduled run for *today* would not pick it up because today's window doesn't include the past date. The pipeline handles this via the same parameter mechanism: an operator reprocesses the affected past day by triggering the DAG with `t_start` and `t_end` set to that day's bounds. The DELETE-then-INSERT pattern means the reprocess is safe  that day's existing rows are wiped and rebuilt from the now-complete source, including the late arrival. The bounded window makes this surgical: only the target day is touched; surrounding days are unaffected.

In a production deployment, a freshness monitor on the source tables would alert when a day's row count drops below expected, prompting the reprocess.

---

## Q2. How do aggregation tables stay correct with incremental loading, without rebuilding from scratch?

This is the core design problem of the pipeline. Aggregates like `agg_user_revenue` summarize a customer's *all-time* history (`SUM(amount)` across every transaction the customer has ever made). A naive incremental approach — filter the aggregate to only today's window — would compute *today's* revenue per customer instead of all-time, breaking the definition.

The strategy used is **affected-customer recompute from full staging history**. Three observations make it work:

1. Staging tables (`stg_billing`, `stg_sessions`) accumulate over time. Each day's run adds that day's cleaned rows to the existing staging contents. After N days of running, staging holds the full history of every transaction across those days.

2. On any given day, only a small subset of customers actually had activity. Those customers' totals may have changed; everyone else's totals are unchanged from yesterday.

3. For the customers whose totals have changed, their *complete history* is in staging — so recomputing their totals from full staging produces the correct all-time value.

Concretely, each aggregate load runs:

```sql
-- Step 1: identify customers active in today's window
-- Step 2: DELETE their existing aggregate rows
DELETE FROM agg_user_revenue
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}'
      AND transaction_date < '{{ params.t_end }}'
);

-- Step 3: recompute and INSERT those customers' fresh totals from FULL staging history
INSERT INTO agg_user_revenue (customer_id, total_revenue, total_transactions)
SELECT customer_id, SUM(amount), COUNT(transaction_id)
FROM stg_billing
WHERE customer_id IN (
    SELECT DISTINCT customer_id
    FROM stg_billing
    WHERE transaction_date >= '{{ params.t_start }}'
      AND transaction_date < '{{ params.t_end }}'
)
GROUP BY customer_id;
```

Key detail: the outer SUM/COUNT reads from `stg_billing` with **no date filter** — it sees the customer's complete history. Only the *which customers to touch* subquery is filtered to the window.

This pattern produces correct all-time aggregates while only touching the affected customers — neither a full rebuild nor a stale incremental sum. It is also idempotent: the DELETE removes the affected customers' rows, the INSERT puts back the same recomputed values, re-running produces identical results.

The same pattern is applied uniformly across all six aggregate tables; for session-based aggregates (`agg_user_usage`, `session_buckets`, `agg_session_distribution`), the "affected customers" subquery filters `stg_sessions.start_time` instead of `stg_billing.transaction_date`.

---

## Q3. stg_customers has no reliable activity timestamp — how is it loaded, and why?

The other two source tables have activity timestamps that make incremental filtering natural: `transaction_date` for billing, `start_time` for sessions. Each tells you "this record happened on day X."

`src_customers` only has `created_at` — the date the customer *registered*, not the date they were active. Filtering customers by `created_at` would incrementally pick up only new signups, which would miss the much larger and more important population: existing customers who transact or session today (the great majority of activity on any given day comes from customers who registered months or years ago). Filtering customers by their `created_at` therefore breaks the warehouse's "every active customer must appear" requirement.

The chosen strategy is **idempotent full refresh with deduplication**:

```sql
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
```

Justifications:

- **Full refresh is cheap here.** `src_customers` is small (~101,000 rows) compared to the millions in billing and sessions. Rebuilding it every run takes seconds.
- **TRUNCATE + INSERT is idempotent.** Re-running produces the identical result.
- **Dedup at the staging layer.** Source contains duplicate customer_ids. Without dedup, downstream JOINs and the BigQuery MERGE produce row-explosion or fail outright. The same ROW_NUMBER-keep-latest pattern as billing is applied for consistency.

The tradeoff acknowledged: this strategy means changes to customer attributes (name correction, email update) are picked up the next day rather than incrementally tracked. For slowly-changing dimension data like customer profile, this is acceptable; if tracking every change with effective dates were required, the strategy would need to be different.

---

## Q4. BigQuery write strategy — how are new and returning customers handled, and what would break with a simple overwrite?

The final write to `dw_user_analytics` uses a BigQuery MERGE:

```sql
MERGE `dw_user_analytics` AS target
USING ( <full LEFT JOIN of stg_customers + 4 aggregates> ) AS source
ON target.customer_id = source.customer_id
WHEN MATCHED THEN UPDATE SET ...  -- returning customers: overwrite metrics
WHEN NOT MATCHED THEN INSERT ...   -- new customers: append
```

Customer matching is by `customer_id`. The two cases:

- **Returning customer** — matched. Their existing row in `dw_user_analytics` has every metric column overwritten with the freshly computed values. Identity columns (name, email, country, customer_since) also refresh, so corrections propagate.
- **New customer** — not matched. A new row is inserted with all metrics. If they had no activity yet, the COALESCE-to-zero in the source query ensures their metric columns hold 0, not NULL.

**What breaks with a simple overwrite (CREATE OR REPLACE TABLE):**

1. **No new-vs-returning distinction.** The whole table is rebuilt every run. There's no way to know which customers are first-time appearances vs updates. Any downstream consumer that wanted to alert on new customer signups, or audit who changed, has nothing to work with.

2. **Wastes compute as the table grows.** A telecom with millions of customers would rebuild the entire warehouse table daily even though most rows haven't changed. MERGE only writes the changed rows.

3. **Lock-in to a single source query shape.** CREATE OR REPLACE requires the full SELECT to compute every row. MERGE lets you swap to a partial-write strategy later (only push affected customers' rows) without changing the target table's contract.

4. **Loses any downstream dependencies on row stability.** Anything reading `dw_user_analytics` mid-rebuild sees an inconsistent state (CREATE OR REPLACE is not transactional in the same way MERGE-into-existing is). MERGE updates rows atomically per-customer.

5. **No idempotency story for partial reprocessing.** With MERGE, reprocessing one window's affected customers only changes those rows. With overwrite, you'd rebuild every customer's row from whatever is currently in the aggregates — which might be wrong if you're mid-reprocess.

A note on environment: BigQuery's free tier disallows DML (including MERGE). For this project, billing was enabled to support the MERGE.

---

## Q5. Billing source arrives six hours late — how does the pipeline behave, and what would you add to detect and alert?

**Pipeline behavior with the current setup:**

The DAG runs on `@daily` schedule. If billing data for a given day is loaded into `src_billing_transactions` six hours late, two scenarios apply:

- If the late arrival lands *before* the next day's DAG run, no special action is needed. The run for that calendar day sees the full data and processes it correctly. (The schedule is on logical date, which can include the full 24 hours of source data even if some of it arrived late within that window.)

- If the late arrival lands *after* the day's scheduled run completed, the day's run processed an incomplete window. `stg_billing` would be missing those late rows; `agg_user_revenue` and related aggregates for those customers would be understated. Downstream `dw_user_analytics` would carry the understated numbers until the affected day is reprocessed.

**Recovery is straightforward.** The bounded-window incremental design supports this directly: an operator triggers the DAG with `t_start` and `t_end` set to the affected day. The staging DELETE-then-INSERT picks up the now-complete source data; the aggregates' affected-customer recompute pulls each affected customer's correct all-time total from the now-complete staging; the BigQuery MERGE upserts those customers' rows. No data corruption persists once the reprocess completes.

**What would be added to detect and alert:**

1. **Row count delta monitoring.** After every staging load, compare the day's row count to a rolling-7-day median. If today's count is below (say) 50% of the median, raise an alert: "billing data may be incomplete for {date}."

2. **Source freshness check.** Before the staging load runs, check the max(transaction_date) in src_billing_transactions against the expected window. If it's older than `t_end`, the source hasn't caught up yet — either delay the run, or fire an alert.

3. **A separate Airflow sensor task** for high-volume sources that polls the source table's max timestamp and only allows the load to proceed once a threshold is met. This is the right shape for production telecom where source-system lag is a known operational reality.

4. **Reconciliation queries** that compare staging row counts to source-system reports (e.g., the billing system's daily volume summary). Discrepancies flag investigation.

The shape of an alert would be a Slack or PagerDuty notification on task failure or threshold breach, with the affected date in the message so an operator knows immediately which window to reprocess.

---

## Q6. A customer appears in src_billing_transactions but has no record in src_customers — trace the data through the pipeline. Is the outcome acceptable?

The orphan customer's `customer_id` appears in billing but never appears in `src_customers`. Let me trace each stage:

**Stage 1 — Quality.** `qc_null_customers` checks for NULL customer_id, not for orphans. The orphan has a valid customer_id (it's just unmatched), so quality checks pass. `qc_null_transaction` and `qc_duplicates` check the billing table itself, which is fine — the orphan's billing rows are well-formed transactions. Quarantine does not capture this case.

**Stage 2 — Staging.** Each staging table loads only from its own source:
- `stg_billing` includes the orphan's transactions (they exist in src_billing_transactions, pass dedup, get cleaned, land in staging).
- `stg_customers` does *not* include the orphan (they don't exist in src_customers, can't appear in staging).

**Stage 3 — Aggregates.** Aggregates GROUP BY customer_id from their source staging:
- `agg_user_revenue` produces a row for the orphan (because they have billing rows in `stg_billing`).
- `agg_user_usage` may or may not have the orphan depending on whether they had sessions.
- `agg_arpu` produces a row for the orphan.

**Stage 4 — Warehouse.** The warehouse JOIN starts from `stg_customers` and LEFT JOINs the aggregates. The orphan does *not* appear in stg_customers, so the LEFT JOIN cannot produce a row for them. The orphan's billing revenue (which *is* present in agg_user_revenue) is computed but **never reaches dw_user_analytics**. It's stranded.
**Is the outcome acceptable?**

For the immediate purpose of customer analytics, yes — the warehouse is queried "tell me about my customers," and a customer the CRM doesn't know about isn't a customer in that sense. Including them with NULL profile fields would be misleading.

For revenue operations (the instruction's third use case surfacing mismatches between billing and customers), no — the orphan represents real revenue that's not attributable to any known customer, which is exactly the mismatch revenue ops needs to see. Currently this mismatch is silent.

The right enhancement: add a quality check `qc_orphan_billing` that flags billing rows whose customer_id is absent from `src_customers`, quarantining them for investigation. This makes the data-integrity issue visible at the quality stage rather than being silently dropped at the JOIN. The same logic should apply to orphan sessions. In production, this kind of cross-source referential check belongs in Stage 1 alongside the null and duplicate checks.

---

## Q7. The churn rule flags customers with fewer than 5 sessions and less than ₦1,000 in revenue. A customer who registered yesterday would always be flagged. What's available in the pipeline to fix this, and what change would you make?

The pipeline already carries `customer_since` in `dw_user_analytics` — the customer's registration date, sourced from `stg_customers.created_at`. The churn rule has no tenure component, so it cannot distinguish "low activity because they're new and haven't ramped" from "low activity because they're disengaging." A customer who registered yesterday has had no real opportunity to accumulate sessions or revenue and is mechanically guaranteed to fall below both thresholds.

The fix is to add a tenure floor to the churn rule, using `customer_since`:

```sql
SELECT customer_id, customer_name, total_sessions, total_revenue
FROM dw_user_analytics
WHERE total_sessions < 5
  AND total_revenue < 1000
  AND customer_since < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
```

The added clause says "only flag customers who have been registered for at least 30 days." A new customer is given a 30-day grace period before the churn rule applies — they have time to take their first sessions and transactions before being labeled at-risk.

The 30-day threshold is a starting point; the right value depends on the business's onboarding cycle. For DataTel, where customers buy data bundles, a 14-day or even 7-day floor might be more appropriate (first session expected within the first week). The threshold should ideally be derived from data — look at the distribution of "days from registration to first session" across the whole customer base and pick a percentile beyond which non-engagement does start to predict churn.

No pipeline change is required to support this — `customer_since` is already in the warehouse table. The change is at the *analytics rule* level, which is the right place: churn definitions are business rules that evolve faster than data pipelines should.

A further refinement would be to compute a `tenure_days` column in `dw_user_analytics` directly (`DATE_DIFF(CURRENT_DATE(), DATE(customer_since), DAY) AS tenure_days`), so analysts and dashboard consumers don't have to repeat the date arithmetic. This is a small SELECT-list addition to the dw_user_analytics MERGE source query — a one-line change in `merge_dw_user_analytics.sql`.

---

# Architecture Summary

**Source layer (PostgreSQL):** three operational tables (`src_billing_transactions`, `src_network_sessions`, `src_customers`) loaded once from CSV. Treated as the upstream system; not regenerated by the pipeline.

**Stage 1 — Quality:** four SQL files write offending rows to a quarantine table. Gate downstream staging loads on failure.

**Stage 2 — Staging:** three tables (`stg_billing`, `stg_sessions`, `stg_customers`). Each split into a create-empty-table file (idempotent CREATE IF NOT EXISTS, runs once) and a load file. Billing and sessions use incremental delete-window-then-insert-window with bounded date params. Customers uses idempotent full refresh with deduplication.

**Stage 3 — Transformation:** six aggregate tables (`agg_user_revenue`, `agg_user_usage`, `agg_monthly_revenue`, `agg_arpu`, `session_buckets`, `agg_session_distribution`). Each uses the affected-customer recompute pattern: identify customers active in today's window, delete their existing rows, recompute and insert from full staging history.

**Stage 4 — Warehouse (BigQuery):** five intermediate tables pushed from Postgres to BigQuery with WRITE_TRUNCATE. The final `dw_user_analytics` is built with CREATE TABLE IF NOT EXISTS for first deployment and refreshed with MERGE for new-vs-returning upserts.

**Stage 5 — Orchestration (Airflow):** single DAG, daily schedule, all logic in SQL files (no inline SQL in Python), date window as overridable parameters (`t_start`, `t_end`), quality checks gate staging loads, idempotent at every step. Tasks parallelize where data dependencies allow.

