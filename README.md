# DataTel Communications — Automated Telecom Data Pipeline

AltSchool of Data Engineering Karatu 2025 — Third Semester Capstone Project.

A 5-stage data pipeline orchestrated in Apache Airflow that ingests telecom data from PostgreSQL source tables, runs quality checks, builds an incremental staging layer with affected-customer aggregate recomputation, and merges into a BigQuery warehouse table. The entire local stack runs in Docker — no manual installation of Airflow or Postgres required.

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

All services other than BigQuery run locally in Docker containers via `docker compose`.

## Stack Architecture

```
┌─────────────────────────────────────────────┐
│ Docker Compose Stack (local)                │
│  ├─ airflow-scheduler                       │
│  ├─ airflow-apiserver                       │
│  ├─ airflow-worker      (CeleryExecutor)    │
│  ├─ airflow-dag-processor                   │
│  ├─ airflow-postgres    (Airflow metadata)  │
│  ├─ datatel-postgres    (source + staging)  │
│  └─ redis               (Celery broker)     │
└─────────────────────────────────────────────┘
                  │
                  ▼
           BigQuery (cloud)
        datatel_warehouse dataset
```

## Key Design Decisions (full justifications in WRITEUP.md)

- **Three different staging strategies**, chosen per-table based on the kind of timestamp the source carries: incremental date-window for `stg_billing` and `stg_sessions` (activity timestamps), idempotent full-refresh with dedup for `stg_customers` (only a registration timestamp, see discussion Q3).

- **Affected-customer aggregate recompute** instead of full rebuild. Identify customers active in the window, delete their existing aggregate rows, recompute from full accumulated staging history, insert. This produces correct all-time totals without reprocessing untouched customers. Discussed in detail in WRITEUP.md Q2.

- **BigQuery MERGE** for the final warehouse write, handling new and returning customers in a single statement. Discussion Q4.

- **Idempotency everywhere.** `CREATE IF NOT EXISTS` for table existence, `TRUNCATE + INSERT` or `DELETE-then-INSERT` for data loads, `MERGE` for upsert. Running the same window twice produces identical results.

- **Date window as overridable parameters** (`t_start` / `t_end`) so operators can reprocess specific historical days from the Airflow UI without modifying code.

- **Credentials externalized to `.env`.** Database credentials are loaded from `.env` (gitignored) and referenced in `docker-compose.yaml` via `${VAR}` interpolation. In production this would be backed by a secrets manager (GCP Secret Manager, HashiCorp Vault).

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

**Prerequisites:**

- Docker Desktop (or Docker Engine + Compose plugin)
- A GCP account with billing enabled (the BigQuery MERGE step requires DML, which is blocked on the free tier — see note below)
- Python 3.13 — optional, only needed if regenerating the synthetic source data via `data_generator.py`

**Steps:**

1. Clone the repository.

2. Place a GCP service-account JSON key at `credentials/datatel.json` (path is gitignored). The service account needs BigQuery Data Editor + Job User roles.

3. Create `.env` at the repo root (also gitignored) containing at minimum:
   ```
   AIRFLOW_UID=50000
   FERNET_KEY=<generate via python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())">
   DATATEL_PG_USER=<choose>
   DATATEL_PG_PASSWORD=<choose a strong value>
   DATATEL_PG_DB=datatel
   ```

4. Generate source data once: `python data_generator.py`, then load the CSVs into the `datatel` Postgres database via `src/source/setup_source_tables.sql`.

5. Bring up the entire stack with one command:
   ```bash
   docker compose up -d
   ```
   No manual installation of Airflow, Postgres, Redis, or any worker required — everything runs in containers.

6. In Airflow UI (`localhost:8080`, login `airflow`/`airflow`), create a connection named `datatel_postgres` pointing at the data-Postgres container (host: `datatel_postgres`, port: `5432`, database/login/password matching your `.env`).

7. Unpause and trigger the DAG `datatel_pipeline`. Default params process a window from `2026-01-15` to `2026-01-16`; override `t_start` / `t_end` from the Trigger dialog to reprocess any historical day.

**Note on BigQuery billing:** the warehouse MERGE step is a DML statement, which BigQuery's free tier disallows. The project must have a billing account linked to run the MERGE (cost on this dataset size is negligible — well under a dollar per run). For environments without billing, a `CREATE OR REPLACE TABLE` fallback can be used at the cost of new-vs-returning customer handling (see WRITEUP.md Q4 for tradeoffs).

## Tech Stack

| Layer | Technology |
|---|---|
| Orchestration | Apache Airflow 3.2.1 (CeleryExecutor) |
| Source database | PostgreSQL 13 |
| Warehouse | Google BigQuery (`europe-west1`) |
| Containerization | Docker + Docker Compose |
| Pipeline languages | Python 3.13, SQL |
| Cloud platform | Google Cloud Platform |

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