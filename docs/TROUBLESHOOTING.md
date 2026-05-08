# Troubleshooting

## Common Errors

| Issue | Cause | Solution |
|-------|-------|----------|
| **"Config file not found"** | Specified config file doesn't exist | Verify the path to your config file |
| **"Missing required parameters"** | Required -b, -s, or -c parameter not provided | Run with `-h` flag to see usage instructions, or use a config file |
| **"Invalid billing table format"** | Table name not in correct format | Use format: `project.dataset.table` (e.g., `myproject.billing.gcp_export`) |
| **"Do not include 'gs://' prefix in bucket name"** | Bucket name includes gs:// prefix | Remove the `gs://` prefix (e.g., use `mybucket` not `gs://mybucket`) |
| **"Bucket name contains invalid characters"** | Bucket name has special characters | Allowed: letters, numbers, hyphens, underscores, dots, forward slashes |
| **"-c value must contain only letters, numbers, underscores, and hyphens"** | Output file prefix has invalid characters | Use only alphanumeric characters, underscores, and hyphens |
| **"Invalid month format"** | Month not in YYYYMM format | Use YYYYMM format (e.g., `202512`) |
| **"-r must be a positive integer"** | Non-numeric or negative value for date range | Use positive integer (e.g., `-r 31`) |
| **"-p value contains invalid characters"** | Project filter has special characters | Allowed: letters, numbers, underscores, commas, dots, hyphens, colons |
| **"-t value contains invalid characters"** | Tags parameter has special characters | Allowed: letters, numbers, underscores, commas, dots, hyphens, forward slashes |
| **"-l value contains invalid characters"** | Labels parameter has special characters | Allowed: letters, numbers, underscores, commas, dots, hyphens, forward slashes |
| **"Cannot use both -m and -r parameters"** | Both month and range specified | Use `-m` OR `-r`, not both |
| **"bq command not found"** | Google Cloud SDK not installed | Use Cloud Shell which has `bq` pre-installed |
| **"gcloud command not found"** | Google Cloud SDK not installed | Use Cloud Shell which has `gcloud` pre-installed |
| **"Billing table does not exist or is not accessible"** | Table doesn't exist or no read permissions | Verify table name and check you have BigQuery Data Viewer permissions |
| **"Could not detect dataset location"** | Cannot determine BigQuery dataset region | Verify dataset exists and you have `bigquery.datasets.get` permission |
| **"Not a detailed export"** | Using standard export instead of detailed | Must enable "Detailed usage cost data" export in GCP, or use `--use-standard-export` flag |
| **"Cloud Storage bucket not accessible"** | Bucket doesn't exist or no access | Verify bucket name and check you have Storage Object User permissions |
| **"Salt file exists but is not readable"** | anonymize.salt has wrong permissions | Check file permissions: `ls -la anonymize.salt` |
| **"Salt file is empty"** | Previous salt generation failed | Delete `anonymize.salt` and re-run |
| **"Salt file contains invalid characters"** | Salt file was corrupted or manually edited | Delete `anonymize.salt` and re-run to generate a new one |
| **"Date range cannot exceed 31 days"** | Requested more than 31 days | Use `-r 31` or less, or use month mode `-m` |
| **"Invalid month value"** | Month number not between 01-12 | Use valid month: 01 (January) through 12 (December) |
| **"Month must be in the past"** | Specified current or future month | Use a past month only (e.g., if today is April 2025, use `202503` or earlier) |
| **"Failed to check data availability"** | BigQuery validation query failed | Check billing table permissions and verify the table has data |
| **"No data found for requested period"** | No usage data exists for the specified time period | Verify billing export is enabled and has data for the requested month |

## Results Packaging Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **"Failed to download files from Cloud Storage"** | Insufficient permissions or files don't exist | Verify files exist: `gcloud storage ls gs://<bucket>/gcp_usage_<customer>_<timestamp>_<format>_<period>-*.csv.gz` and check read permissions |
| **"Failed to copy log file"** | Log file doesn't exist or permission issue | Verify extraction completed successfully and log file exists in `logs/` folder |
| **"Failed to create ZIP archive"** | Insufficient disk space or zip command issue | Check disk space: `df -h` (Cloud Shell has 5GB limit) |

## Configuration Warnings

When using advanced parameters (`-r`, `--use-standard-export`, `--anonymize`), the script displays warnings about non-standard configurations. This is expected behavior and not an error.
