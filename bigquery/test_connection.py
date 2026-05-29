# import requests
# import json
import os 
# from bigquery import BigQuery
from google.cloud import bigquery
from dotenv import load_dotenv

load_dotenv()
credentials = os.getenv("GOOGLE_CRED")

def test_bigquery_connection():
    try:
        client = bigquery.Client.from_service_account_json(credentials)
        query = "SELECT 1"
        query_job = client.query(query)
        results = query_job.result()
        print("BigQuery connection successful")
        datasets = list(client.list_datasets())
        print("Datasets in project:")
        for dataset in datasets:
            print(" -", dataset.dataset_id)
    except Exception as e:
        print("BigQuery connection failed:", e)


test_bigquery_connection()