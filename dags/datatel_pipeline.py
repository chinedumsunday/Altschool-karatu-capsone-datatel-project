import datetime
from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.standard.operators.bash import BashOperator

with DAG(
    dag_id='datatel_pipeline',
    start_date=datetime.datetime(2026, 5, 1),
    schedule='@daily',
    catchup=False,
    template_searchpath='/opt/airflow/src',
    params={
        "t_start": "2026-01-15",
        "t_end": "2026-01-16",
    }
) as dag:

    create_quarantine = SQLExecuteQueryOperator(
        task_id='create_quarantine',
        conn_id='datatel_postgres',
        sql="source/create_quarantine.sql"
    )

    create_stg_billing = SQLExecuteQueryOperator(
        task_id='create_stg_billing',
        conn_id='datatel_postgres',
        sql="staging/create_stg_billing.sql"
    )

    create_stg_sessions = SQLExecuteQueryOperator(
        task_id='create_stg_sessions',
        conn_id='datatel_postgres',
        sql="staging/create_stg_sessions.sql"
    )

    create_stg_customers = SQLExecuteQueryOperator(
        task_id='create_stg_customers',
        conn_id='datatel_postgres',
        sql="staging/create_stg_customers.sql"
    )

    create_agg_user_revenue = SQLExecuteQueryOperator(
        task_id='create_agg_user_revenue',
        conn_id='datatel_postgres',
        sql="transform/create_agg_user_revenue.sql"
    )

    create_agg_user_usage = SQLExecuteQueryOperator(
        task_id='create_agg_user_usage',
        conn_id='datatel_postgres',
        sql="transform/create_agg_user_usage.sql"
    )

    create_agg_arpu = SQLExecuteQueryOperator(
        task_id='create_agg_arpu',
        conn_id='datatel_postgres',
        sql="transform/create_agg_arpu.sql"
    )

    create_agg_monthly_revenue = SQLExecuteQueryOperator(
        task_id='create_agg_monthly_revenue',
        conn_id='datatel_postgres',
        sql="transform/create_agg_monthly_revenue.sql"
    )

    create_session_buckets = SQLExecuteQueryOperator(
        task_id='create_session_buckets',
        conn_id='datatel_postgres',
        sql="transform/create_session_buckets.sql"
    )

    create_agg_session_distribution = SQLExecuteQueryOperator(
        task_id='create_agg_session_distribution',
        conn_id='datatel_postgres',
        sql="transform/create_agg_session_distribution.sql"
    )

    qc_null_transaction = SQLExecuteQueryOperator(
        task_id='qc_null_transaction',
        conn_id='datatel_postgres',
        sql="quality/qc_null_transaction.sql"
    )

    qc_null_session = SQLExecuteQueryOperator(
        task_id='qc_null_session',
        conn_id='datatel_postgres',
        sql="quality/qc_null_session.sql"
    )

    qc_null_customers = SQLExecuteQueryOperator(
        task_id='qc_null_customers',
        conn_id='datatel_postgres',
        sql="quality/qc_null_customers.sql"
    )

    qc_duplicates = SQLExecuteQueryOperator(
        task_id='qc_duplicates',
        conn_id='datatel_postgres',
        sql="quality/qc_duplicates.sql"
    )

    load_stg_billing = SQLExecuteQueryOperator(
        task_id='load_stg_billing',
        conn_id='datatel_postgres',
        sql="staging/stg_billing.sql"
    )

    load_stg_sessions = SQLExecuteQueryOperator(
        task_id='load_stg_sessions',
        conn_id='datatel_postgres',
        sql="staging/stg_sessions.sql"
    )

    load_stg_customers = SQLExecuteQueryOperator(
        task_id='load_stg_customers',
        conn_id='datatel_postgres',
        sql="staging/stg_customers.sql"
    )

    load_agg_user_revenue = SQLExecuteQueryOperator(
        task_id='load_agg_user_revenue',
        conn_id='datatel_postgres',
        sql="transform/agg_user_revenue.sql"
    )

    load_agg_user_usage = SQLExecuteQueryOperator(
        task_id='load_agg_user_usage',
        conn_id='datatel_postgres',
        sql="transform/agg_user_usage.sql"
    )

    load_agg_arpu = SQLExecuteQueryOperator(
        task_id='load_agg_arpu',
        conn_id='datatel_postgres',
        sql="transform/agg_arpu.sql"
    )

    load_agg_monthly_revenue = SQLExecuteQueryOperator(
        task_id='load_agg_monthly_revenue',
        conn_id='datatel_postgres',
        sql="transform/agg_monthly_revenue.sql"
    )

    load_session_buckets = SQLExecuteQueryOperator(
        task_id='load_session_buckets',
        conn_id='datatel_postgres',
        sql="transform/session_buckets.sql"
    )

    load_agg_session_distribution = SQLExecuteQueryOperator(
        task_id='load_agg_session_distribution',
        conn_id='datatel_postgres',
        sql="transform/agg_session_distribution.sql"
    )
    load_to_bigquery = BashOperator(
        task_id='load_to_bigquery',
        bash_command='python /opt/airflow/bigquery/load_to_bigquery_dag.py'
    )




    # quarantine must exist before quality checks write to it
    create_quarantine >> [qc_null_transaction, qc_null_session, qc_null_customers, qc_duplicates]

    # corrupted records in today's data block that source's staging load
    [qc_null_transaction, qc_duplicates] >> load_stg_billing
    [qc_null_session, qc_duplicates] >> load_stg_sessions
    qc_null_customers >> load_stg_customers

    # Create before loading  for each staging table
    create_stg_billing >> load_stg_billing
    create_stg_sessions >> load_stg_sessions
    create_stg_customers >> load_stg_customers

    # Aggregate tables 
    [create_agg_user_revenue, load_stg_billing] >> load_agg_user_revenue
    [create_agg_arpu, load_stg_billing] >> load_agg_arpu
    [create_agg_monthly_revenue, load_stg_billing] >> load_agg_monthly_revenue
    [create_agg_user_usage, load_stg_sessions] >> load_agg_user_usage
    [create_session_buckets, load_stg_sessions] >> load_session_buckets

    # session_distribution
    [create_agg_session_distribution, load_session_buckets] >> load_agg_session_distribution

    #bigquery
    [load_stg_customers, load_agg_user_revenue, load_agg_user_usage, load_agg_arpu, load_agg_session_distribution] >> load_to_bigquery