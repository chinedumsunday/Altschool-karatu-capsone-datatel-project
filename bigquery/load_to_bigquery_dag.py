from google.cloud import bigquery
import pandas
from sqlalchemy import create_engine
import os

pg_user = os.environ['DATATEL_PG_USER']
pg_pass = os.environ['DATATEL_PG_PASSWORD']
pg_db = os.environ['DATATEL_PG_DB']

tables = ["stg_customers", "agg_user_revenue", "agg_user_usage", "agg_arpu", "agg_session_distribution"]
credentials = "/opt/airflow/credentials/datatel.json"
engine = create_engine(f"postgresql+psycopg2://{pg_user}:{pg_pass}@datatel_postgres:5432/{pg_db}")

client = bigquery.Client.from_service_account_json(credentials)
job_config = bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE")

for table in tables:
    destination = f"{client.project}.datatel_warehouse.{table}"
    df = pandas.read_sql(f"SELECT * FROM {table};", engine)
    print(f"Loaded {len(df)} rows from Postgres for {table}")
    job = client.load_table_from_dataframe(df, destination, job_config=job_config, location="europe-west1")
    job.result()
    print(f"Pushed {len(df)} rows to {destination}")


with open('/opt/airflow/bigquery/create_dw_user_analytics.sql', 'r') as f:
    create_sql = f.read()
print("Ensuring dw_user_analytics exists...")
client.query(create_sql, location="europe-west1").result()

with open('/opt/airflow/bigquery/merge_dw_user_analytics.sql', 'r') as f:
    merge_sql = f.read()
print("Running MERGE into dw_user_analytics...")
client.query(merge_sql, location="europe-west1").result()
print("MERGE complete")