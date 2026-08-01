# Permissions

Grant the minimum required permissions for users to run the extraction script.

| Service | Recommended Predefined Role | Permission | Purpose | Scope | Resource Access |
|---------|----------------------------|-----------|---------|-------|-----------------|
| **BigQuery (Data)** | BigQuery Data Viewer | `bigquery.tables.get` | View table metadata | Dataset level | Billing export dataset |
| | | `bigquery.tables.getData` | Read billing table | Dataset level | Billing export dataset |
| | | `bigquery.tables.export` | Export data from tables | Dataset level | Billing export dataset |
| **BigQuery (Execution)** | BigQuery Job User | `bigquery.jobs.create` | Execute queries and export jobs | Project level | Billing project |
| **Cloud Storage** | Storage Object User | `storage.buckets.get` | Verify bucket exists | Bucket level | Output bucket |
| | | `storage.objects.create` | Write export files | Bucket level | Output bucket |
| | | `storage.objects.get` | Read objects (for verification) | Bucket level | Output bucket |
| | | `storage.objects.list` | List objects in bucket | Bucket level | Output bucket |
