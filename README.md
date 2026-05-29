# DataTel Communications — Automated Telecom Data Pipeline

AltSchool of Data Engineering Karatu 2025 — Third Semester Capstone Project.

A 5-stage data pipeline orchestrated in Apache Airflow that ingests telecom data from PostgreSQL source tables, runs quality checks, builds an incremental staging layer with affected-customer aggregate recomputation, and merges into a BigQuery warehouse table.

---

## 📘 The full writeup — including all justifications and the seven discussion question answers — is in [`WRITEUP.md`](./WRITEUP.md) in this directory. **Please read that file for the complete graded deliverables.**

---

## Quick Architecture Summary

| Stage | What it does | Where |
|---|---|---|
| 1. Quality | Detect nulls + duplicates; quarantine offending rows | Postgres |
| 2. Staging | Clean, dedupe, type-cast (incremental for billing/sessions, full-refresh for customers) | Postgres |
| 3. Transformation | Six per-customer aggregate tables (affected-customer recompute pattern) | Postgres |
| 4. Warehouse | Push intermediates to BigQuery; MERGE into `dw_user_analytics` | BigQuery |
| 5. Orchestration | Single Airflow DAG, daily schedule, SQL-first, idempotent, parametrized | Airflow |

## Key Design Decisions (full justifications in WRITEUP.md)

- **Three different staging strategies**, chosen per-table based on the kind of timestamp the source carries: incremental date-window for `stg_billing` and `stg_sessions` (activity timestamps), idempotent full-refresh with dedup for `stg_customers` (only a registration timestamp, see discussion Q3).

- **Affected-customer aggregate recompute** instead of full rebuild. Identify customers active in the window, delete their existing aggregate rows, recompute from full accumulated staging history, insert. This produces correct all-time totals without reprocessing untouched customers. Discussed in detail in WRITEUP.md Q2.

- **BigQuery MERGE** for the final warehouse write, handling new and returning customers in a single statement. Discussion Q4.

- **Idempotency everywhere.** `CREATE IF NOT EXISTS` for table existence, `TRUNCATE + INSERT` or `DELETE-then-INSERT` for data loads, `MERGE` for upsert. Running the same window twice produces identical results.

- **Date window as overridable parameters** (`t_start` / `t_end`) so operators can reprocess specific historical days from the Airflow UI without modifying code.

## Repository Layout

```
.
├── dags/
│   └── datatel_pipeline.py          # the Airflow DAG
├── src/
│   ├── quality/                     # Stage 1 SQL
│   ├── staging/                     # Stage 2 SQL (create + load pairs)
│   ├── transform/                   # Stage 3 SQL (create + load pairs)
│   └── source/                      # quarantine + source setup
├── bigquery/
│   ├── create_dw_user_analytics.sql # warehouse table schema
│   ├── merge_dw_user_analytics.sql  # MERGE for new vs returning customers
│   └── load_to_bigquery_dag.py      # in-container loader: push 5 tables + run MERGE
├── docker-compose.yaml              # Airflow + Postgres stack
├── data_generator.py                # one-time source-data generator
├── WRITEUP.md                       # ← **all written deliverables**
└── README.md                        # this file
```

## How to Run Locally

1. Clone the repository.
2. Place GCP service-account credentials at `credentials/datatel.json` (gitignored).
3. Create `.env` with `FERNET_KEY` and `AIRFLOW_UID` (gitignored).
4. Generate source data once: `python data_generator.py`, then load the CSVs into the `datatel` Postgres database via the `setup_source_tables.sql` script.
5. Bring up the stack: `docker compose up -d`.
6. In Airflow UI (`localhost:8080`), create a connection named `datatel_postgres` pointing at the data-Postgres container (host `datatel_postgres`, port `5432`).
7. Trigger the DAG `datatel_pipeline`. Default params process a window from 2026-01-15 to 2026-01-16; override `t_start` / `t_end` to reprocess any historical day.

## Tech Stack

PostgreSQL · Apache Airflow 3.2.1 · BigQuery · Docker Compose · Python 3.13 · SQL.

---

## 📘 Full required writeup for grading: [`WRITEUP.md`](./WRITEUP.md)

That file contains:

- Four quality-check notes (what each detects + risk)
- `stg_billing` deduplication justification
- `stg_customers` deduplication justification
- `agg_arpu` division-risk justification
- `dw_user_analytics` join strategy justification
- Currency normalization note
- BigQuery MERGE write strategy justification
- **All seven discussion question answers (Q1–Q7)**

---

*Built by Chinedum, May 2026.*
