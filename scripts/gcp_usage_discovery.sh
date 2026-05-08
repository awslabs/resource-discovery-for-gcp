#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# =============================================================================
# GCP Usage Discovery Script
#
# Version: See Version.json
# Repository: https://github.com/awslabs/resource-discovery-for-gcp
#
# Extracts detailed GCP usage data from BigQuery and exports to Cloud Storage
# for pricing analysis and resource discovery.
#
# Usage: $0 -f config.env
#        $0 -b project.dataset.table -s mybucket -c acme [-m YYYYMM] [-t tags] [-l labels] [-p projects]
#
# Run from Cloud Shell for best performance. Requires bq and gcloud CLI tools.
# See README.md for full documentation.
# =============================================================================

# Global settings
set -e

# =============================================================================
# FUNCTION DEFINITIONS
# =============================================================================

# log_message: Prints a message with timestamp
# Usage: log_message "message"
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# failure_handler: Handles script failures and uploads logs to Cloud Storage
# Usage: Called automatically via trap on error
failure_handler() {
  echo ""
  echo "============================================="
  echo "ERROR: Script Failure"
  echo "============================================="
  echo "The script failed at line $1."
  echo "Review the error messages above for details."
  echo "============================================="

  # Show local log file location in box format
  if [ -n "$LOG_FILE_LOCAL" ] && [ -f "$LOG_FILE_LOCAL" ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│  ⚠️  SHARE ERROR LOG WITH YOUR AWS REPRESENTATIVE          │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Error log file (in Cloud Shell): $LOG_FILE_LOCAL"
    echo ""
    echo "⚠️  This log file is saved locally in Cloud Shell, NOT in GCS."
    echo "   Download it from Cloud Shell and share with your AWS representative."
    echo ""
    echo "============================================="
  fi
  
  # Clean up packaging folder if it exists (prevents disk space issues on Cloud Shell)
  if [ -n "$RESULTS_FOLDER_NAME" ] && [ -d "$RESULTS_FOLDER_NAME" ]; then
    rm -rf "$RESULTS_FOLDER_NAME"
  fi
  
  exit 1
}

# validation_error: Handles validation errors (called explicitly)
# Usage: validation_error (no line number needed)
validation_error() {
  echo ""
  echo "============================================="
  echo "ERROR: Validation Failed"
  echo "============================================="
  echo "Review the error messages above for details."
  echo "============================================="

  # Show local log file location in box format
  if [ -n "$LOG_FILE_LOCAL" ] && [ -f "$LOG_FILE_LOCAL" ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│  ⚠️  SHARE ERROR LOG WITH YOUR AWS REPRESENTATIVE          │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Error log file (in Cloud Shell): $LOG_FILE_LOCAL"
    echo ""
    echo "⚠️  This log file is saved locally in Cloud Shell, NOT in GCS."
    echo "   Download it from Cloud Shell and share with your AWS representative."
    echo ""
    echo "============================================="
  fi
  
  exit 1
}

# usage: Displays script usage information with parameters and examples
# Usage: Called when -h flag is used or parameters are invalid
usage() {
  echo "Usage: $0 -f <config_file> | -b <billing_table> -s <cloud_storage_bucket> -c <customer_or_workload_name> [-m <month>] [-t <tags>] [-l <labels>] [-p <projects>]"
  echo ""
  echo "Config File (recommended):"
  echo "  -f  Path to config file (see config.example.env)"
  echo ""
  echo "Required (if not using config file):"
  echo "  -b  BigQuery Detailed Billing table: https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/detailed-usage. Format: project.dataset.table"
  echo "  -s  Cloud Storage bucket name to store usage discovery data (without gs:// prefix). Format: mybucket or mybucket/myfolder"
  echo "  -c  Output file prefix (e.g., customer or workload name, no spaces) - used for naming output files only, does NOT filter data"
  echo ""
  echo "Optional:"
  echo "  -m  Capture month (YYYYMM format, defaults to prior month)"
  echo "  -t  Tags to capture (comma-separated without spaces, default: none)"
  echo "  -l  Labels to capture (comma-separated without spaces, default: none)"
  echo "  -p  Project IDs to filter (comma-separated without spaces) - extracts only specified projects"
  echo "  -y  Skip confirmation prompt (for automation)"
  echo "  --dry-run  Validate query and show data size without executing (no data extracted)"
  echo "  --anonymize  Hash sensitive identifiers (resourceName, resourceGlobalName, projectID)"
  echo "  -h  Show help message"
  echo ""
  exit 1
}

# format_array: Converts comma-separated string to BigQuery array format
# Usage: format_array "environment,env" returns ['environment', 'env']
# Strips spaces around commas for user convenience
format_array() {
  echo "['$(echo "$1" | sed 's/[[:space:]]*,[[:space:]]*/,/g' | sed "s/,/', '/g")']"
}

# add_days_to_date: Adds days to a date (handles macOS/Linux differences)
# Usage: add_days_to_date "2025-01-01" 5 returns "2025-01-06"
add_days_to_date() {
  local input_date=$1
  local days=$2
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    date -j -v+"${days}"d -f "%Y-%m-%d" "$input_date" +%Y-%m-%d
  else
    date -d "$input_date + $days days" +%Y-%m-%d
  fi
}



# =============================================================================
# MAIN SCRIPT
# =============================================================================

# Set error trap
trap 'failure_handler $LINENO' ERR

# Default variables (set early so we can create log file)
CURRENT_TS=$(date +'%Y%m%d%H%M%S')
SCRIPT_START_TS=$(date +'%Y-%m-%d %H:%M:%S %Z')

# Read version from Version.json (single source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/../Version.json"
if [ -f "$VERSION_FILE" ]; then
  MAJOR_VERSION=$(grep -o '"MajorVersion"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_FILE" | cut -d'"' -f4)
  MINOR_VERSION=$(grep -o '"MinorVersion"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_FILE" | cut -d'"' -f4)
  PATCH_VERSION=$(grep -o '"PatchVersion"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSION_FILE" | cut -d'"' -f4)
  # Pad to 2 digits: 9.6.0 becomes v090600
  MAJOR_PADDED=$(printf "%02d" "$MAJOR_VERSION")
  MINOR_PADDED=$(printf "%02d" "$MINOR_VERSION")
  PATCH_PADDED=$(printf "%02d" "$PATCH_VERSION")
  BASE_VERSION="v${MAJOR_PADDED}${MINOR_PADDED}${PATCH_PADDED}"
else
  echo "Warning: Version.json not found. Using default version."
  BASE_VERSION="v000000"
fi

# Linux vs macOS date
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS (BSD date)
  DEFAULT_CAPTURE_MONTH=$(date -v-1m +%Y%m) # Prior month
else
  # Linux / Cloud Shell (GNU date)
  DEFAULT_CAPTURE_MONTH=$(date -d "last month" +%Y%m) # Prior month
fi

CAPTURE_TAGS=""
CAPTURE_LABELS=""
SKIP_CONFIRM="false"
DRY_RUN="false"
ANONYMIZE="false"
USE_STANDARD_EXPORT="false"
USE_DATE_RANGE="false"
DATE_RANGE=""
CAPTURE_MONTH=""
PROJECT_FILTER=""
CONFIG_FILE=""
PARTITION_BUFFER_DAYS=5     # Buffer days after period end for late-arriving data

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -b)
      BILLING_TABLE="$2"
      CLI_PROVIDED_BILLING_TABLE=true
      shift 2
      ;;
    -s)
      GCS_BUCKET="$2"
      CLI_PROVIDED_GCS_BUCKET=true
      shift 2
      ;;
    -c)
      CUSTOMER_NAME="$2"
      CLI_PROVIDED_CUSTOMER_NAME=true
      shift 2
      ;;
    -f)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -m)
      CAPTURE_MONTH="$2"
      CLI_PROVIDED_CAPTURE_MONTH=true
      shift 2
      ;;
    -r)
      DATE_RANGE="$2"
      CLI_PROVIDED_DATE_RANGE=true
      shift 2
      ;;
    -t)
      CAPTURE_TAGS="$2"
      CLI_PROVIDED_CAPTURE_TAGS=true
      shift 2
      ;;
    -l)
      CAPTURE_LABELS="$2"
      CLI_PROVIDED_CAPTURE_LABELS=true
      shift 2
      ;;
    -p)
      PROJECT_FILTER="$2"
      CLI_PROVIDED_PROJECT_FILTER=true
      shift 2
      ;;
    -y)
      SKIP_CONFIRM="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --anonymize)
      ANONYMIZE="true"
      shift
      ;;
    -h)
      usage
      ;;
    --use-standard-export)
      USE_STANDARD_EXPORT="true"
      shift
      ;;
    *)
      echo "Error: Unknown option $1"
      usage
      ;;
  esac
done

# Load config file if specified (CLI flags override config values)
if [ -n "$CONFIG_FILE" ]; then
  if [ -f "$CONFIG_FILE" ]; then
    # Save CLI values before loading config
    CLI_BILLING_TABLE="$BILLING_TABLE"
    CLI_GCS_BUCKET="$GCS_BUCKET"
    CLI_CUSTOMER_NAME="$CUSTOMER_NAME"
    CLI_CAPTURE_MONTH="$CAPTURE_MONTH"
    CLI_DATE_RANGE="$DATE_RANGE"
    CLI_CAPTURE_TAGS="$CAPTURE_TAGS"
    CLI_CAPTURE_LABELS="$CAPTURE_LABELS"
    CLI_PROJECT_FILTER="$PROJECT_FILTER"
    CLI_SKIP_CONFIRM="$SKIP_CONFIRM"
    CLI_DRY_RUN="$DRY_RUN"
    CLI_ANONYMIZE="$ANONYMIZE"
    
    # Parse config file (strict key=value only, no shell execution)
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$line" ]] && continue
      # Skip lines without = sign
      [[ "$line" != *=* ]] && continue
      # Split on first = sign
      key="${line%%=*}"
      value="${line#*=}"
      # Strip whitespace, inline comments, and surrounding quotes
      key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      value=$(printf '%s' "$value" | sed 's/[[:space:]][[:space:]]*#.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")
      # Only accept allowlisted variables
      case "$key" in
        BILLING_TABLE) BILLING_TABLE="$value" ;;
        GCS_BUCKET) GCS_BUCKET="$value" ;;
        CUSTOMER_NAME) CUSTOMER_NAME="$value" ;;
        CAPTURE_MONTH) CAPTURE_MONTH="$value" ;;
        DATE_RANGE) DATE_RANGE="$value" ;;
        CAPTURE_TAGS) CAPTURE_TAGS="$value" ;;
        CAPTURE_LABELS) CAPTURE_LABELS="$value" ;;
        PROJECT_FILTER) PROJECT_FILTER="$value" ;;
        SKIP_CONFIRM) SKIP_CONFIRM="$value" ;;
        DRY_RUN) DRY_RUN="$value" ;;
        ANONYMIZE) ANONYMIZE="$value" ;;
        USE_STANDARD_EXPORT) USE_STANDARD_EXPORT="$value" ;;
        *) ;;
      esac
    done < "$CONFIG_FILE"
    
    # CLI flags override config file values (if explicitly provided)
    [ "$CLI_PROVIDED_BILLING_TABLE" = "true" ] && BILLING_TABLE="$CLI_BILLING_TABLE"
    [ "$CLI_PROVIDED_GCS_BUCKET" = "true" ] && GCS_BUCKET="$CLI_GCS_BUCKET"
    [ "$CLI_PROVIDED_CUSTOMER_NAME" = "true" ] && CUSTOMER_NAME="$CLI_CUSTOMER_NAME"
    [ "$CLI_PROVIDED_CAPTURE_MONTH" = "true" ] && CAPTURE_MONTH="$CLI_CAPTURE_MONTH"
    [ "$CLI_PROVIDED_DATE_RANGE" = "true" ] && DATE_RANGE="$CLI_DATE_RANGE"
    [ "$CLI_PROVIDED_CAPTURE_TAGS" = "true" ] && CAPTURE_TAGS="$CLI_CAPTURE_TAGS"
    [ "$CLI_PROVIDED_CAPTURE_LABELS" = "true" ] && CAPTURE_LABELS="$CLI_CAPTURE_LABELS"
    [ "$CLI_PROVIDED_PROJECT_FILTER" = "true" ] && PROJECT_FILTER="$CLI_PROJECT_FILTER"
    [ "$CLI_SKIP_CONFIRM" = "true" ] && SKIP_CONFIRM="true"
    [ "$CLI_DRY_RUN" = "true" ] && DRY_RUN="true"
    [ "$CLI_ANONYMIZE" = "true" ] && ANONYMIZE="true"
  else
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
  fi
fi

# Interactive prompts for missing required parameters
if [ -z "$BILLING_TABLE" ]; then
  read -rp "Enter BigQuery billing table (project.dataset.table): " BILLING_TABLE
fi

if [ -z "$GCS_BUCKET" ]; then
  read -rp "Enter Cloud Storage bucket (without gs:// prefix): " GCS_BUCKET
fi

if [ -z "$CUSTOMER_NAME" ]; then
  read -rp "Enter customer/workload name (no spaces): " CUSTOMER_NAME
fi

# =============================================================================
# PARAMETER VALIDATION (fail early before logging starts)
# =============================================================================

# --- Required Parameters ---
if [ -z "$BILLING_TABLE" ]; then
  echo "Error: -b (billing table) is required"
  usage
fi
if [ -z "$GCS_BUCKET" ]; then
  echo "Error: -s (Cloud Storage bucket) is required"
  usage
fi
if [ -z "$CUSTOMER_NAME" ]; then
  echo "Error: -c (output file prefix) is required"
  usage
fi

# --- Parameter Format Validation ---
# Billing table format: project.dataset.table
if ! [[ "$BILLING_TABLE" =~ ^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid billing table format. Expected 'project.dataset.table', got: $BILLING_TABLE"
  echo "Example: myproject.billing.gcp_export"
  usage
fi

# Cloud Storage bucket: no gs:// prefix
if [[ "$GCS_BUCKET" == gs://* ]]; then
  echo "Error: Do not include 'gs://' prefix in bucket name. Got: $GCS_BUCKET"
  usage
fi

# Cloud Storage bucket: valid characters only
if [[ ! "$GCS_BUCKET" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
  echo "Error: Bucket name contains invalid characters. Got: $GCS_BUCKET"
  echo "Allowed: letters, numbers, hyphens, underscores, dots, forward slashes"
  usage
fi

# Customer name: alphanumeric, underscore, hyphen only
if [[ ! "$CUSTOMER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: -c value must contain only letters, numbers, underscores, and hyphens. Got: $CUSTOMER_NAME"
  usage
fi

# Month format: YYYYMM (6 digits)
if [ -n "$CAPTURE_MONTH" ] && ! [[ "$CAPTURE_MONTH" =~ ^[0-9]{6}$ ]]; then
  echo "Error: Invalid month format. Expected YYYYMM (e.g., 202512), got: $CAPTURE_MONTH"
  usage
fi

# Date range: positive integer
if [ -n "$DATE_RANGE" ]; then
  if ! [[ "$DATE_RANGE" =~ ^[0-9]+$ ]] || [ "$DATE_RANGE" -lt 1 ]; then
    echo "Error: -r must be a positive integer, got: $DATE_RANGE"
    usage
  fi
fi

# Project filter: valid characters only (if provided)
if [ -n "$PROJECT_FILTER" ] && [[ ! "$PROJECT_FILTER" =~ ^[a-zA-Z0-9_,.:-]+$ ]]; then
  echo "Error: -p value contains invalid characters. Got: $PROJECT_FILTER"
  echo "Allowed: letters, numbers, underscores, commas, dots, hyphens, colons"
  usage
fi

# Tags: valid characters only (if provided)
if [ -n "$CAPTURE_TAGS" ] && [[ ! "$CAPTURE_TAGS" =~ ^[a-zA-Z0-9_,./-]+$ ]]; then
  echo "Error: -t value contains invalid characters. Got: $CAPTURE_TAGS"
  echo "Allowed: letters, numbers, underscores, commas, dots, hyphens, forward slashes"
  usage
fi

# Labels: valid characters only (if provided)
if [ -n "$CAPTURE_LABELS" ] && [[ ! "$CAPTURE_LABELS" =~ ^[a-zA-Z0-9_,./-]+$ ]]; then
  echo "Error: -l value contains invalid characters. Got: $CAPTURE_LABELS"
  echo "Allowed: letters, numbers, underscores, commas, dots, hyphens, forward slashes"
  usage
fi

# --- Parameter Relationship Validation ---
# Mutual exclusivity of -m and -r
if [ -n "$DATE_RANGE" ] && [ -n "$CAPTURE_MONTH" ]; then
  echo "Error: Cannot use both -m (month) and -r (range) parameters"
  echo "Use -m for a specific month OR -r for a date range, not both"
  usage
fi

# =============================================================================
# SET DEFAULTS AND DERIVED VALUES
# =============================================================================

# Set defaults if neither -m nor -r provided
if [ -z "$DATE_RANGE" ] && [ -z "$CAPTURE_MONTH" ]; then
  CAPTURE_MONTH="$DEFAULT_CAPTURE_MONTH"
fi

# Set mode indicator for local log filename
if [ -n "$DATE_RANGE" ]; then
  MODE_INDICATOR="r"
else
  MODE_INDICATOR="m"
fi

# Set CAPTURE_PERIOD early (before logging starts)
if [ -n "$DATE_RANGE" ]; then
  CAPTURE_PERIOD="r$(printf "%02d" "$DATE_RANGE")"
else
  CAPTURE_PERIOD="${CAPTURE_MONTH}"
fi

# Set query format based on export type
if [ "$USE_STANDARD_EXPORT" = "true" ]; then
  QUERY_FORMAT="${BASE_VERSION}_std"
else
  QUERY_FORMAT="${BASE_VERSION}_dtl"
fi

# Process customer name (replace spaces with underscores)
CUSTOMER_NAME="${CUSTOMER_NAME// /_}"

# =============================================================================
# START LOGGING
# =============================================================================

mkdir -p logs
LOG_FILE_LOCAL="logs/gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${MODE_INDICATOR}.log"
RESULTS_FOLDER_NAME="gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${CAPTURE_PERIOD}"
RESULTS_ZIP_NAME="${RESULTS_FOLDER_NAME}.zip"
exec > >(tee -i "$LOG_FILE_LOCAL") 2>&1

# =============================================================================
# REQUIRED TOOLS CHECK
# =============================================================================

log_message "Checking required tools..."
if ! command -v bq &> /dev/null; then
  echo "Error: 'bq' command not found. Please install Google Cloud SDK."
  echo "Installation: https://cloud.google.com/sdk/docs/install"
  validation_error
fi

if ! command -v gcloud &> /dev/null; then
  echo "Error: 'gcloud' command not found. Please install Google Cloud SDK."
  echo "Installation: https://cloud.google.com/sdk/docs/install"
  validation_error
fi
log_message "✓ Required tools verified"

# =============================================================================
# API VALIDATIONS (require network calls)
# =============================================================================

# Validate billing table exists and is queryable
log_message "Checking billing table accessibility..."
# Convert format from project.dataset.table to project:dataset.table for bq command
# Replace only the first dot with a colon
BQ_TABLE_FORMAT="${BILLING_TABLE/./:}"
if ! bq show "$BQ_TABLE_FORMAT" &> /dev/null; then
  echo "Error: Billing table '${DISPLAY_BILLING_TABLE}' does not exist or is not accessible."
  echo "Please verify:"
  echo "  1. The table name is correct"
  echo "  2. The table exists in BigQuery"
  echo "  3. You have permissions to query the table"
  echo "  4. You have enabled detailed billing export (not just standard export)"
  validation_error
fi
log_message "✓ Billing table accessible"

# Extract project ID and dataset name from billing table
BILLING_PROJECT_ID="${BILLING_TABLE%%.*}"
DATASET_NAME="${BILLING_TABLE#*.}"  # Remove project prefix
DATASET_NAME="${DATASET_NAME%%.*}"   # Remove table suffix

# Extract dataset location for BigQuery query
log_message "Detecting dataset location..."
DATASET_LOCATION=$(bq show --format=json "${BILLING_PROJECT_ID}:${DATASET_NAME}" | grep -o '"location":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
if [ -z "$DATASET_LOCATION" ]; then
  echo "Error: Could not detect dataset location."
  echo "Please verify the dataset exists and you have permissions to access it."
  validation_error
fi
log_message "✓ Dataset location detected: $DATASET_LOCATION"

# Verify this is a detailed billing export (not standard)
if [ "$USE_STANDARD_EXPORT" = "true" ]; then
  log_message "⚠️  Using standard export mode (advanced configuration)"
else
  log_message "Verifying detailed billing export..."
  if ! bq show --schema "$BQ_TABLE_FORMAT" | grep -q '"name":"resource"'; then
    echo "❌ ERROR: The billing table does not appear to be a detailed export."
    echo ""
    echo "This script requires detailed billing export with resource-level data."
    echo "The table schema is missing the 'resource' field."
    echo ""
    echo "Please verify:"
    echo "  1. You have enabled 'Detailed usage cost data' export (not 'Standard usage cost data')"
    echo "  2. You are pointing to the correct BigQuery table (should contain '_resource_' in name)"
    echo ""
    echo "Documentation: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/detailed-usage"
    echo ""
    echo "If you intentionally want to use a standard export table, use the --use-standard-export flag."
    validation_error
  fi
  log_message "✓ Detailed billing export verified (resource field found)"
fi

# Validate Cloud Storage bucket exists
log_message "Checking Cloud Storage bucket accessibility..."
BUCKET_NAME="${GCS_BUCKET%%/*}"
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
  echo "Error: Cloud Storage bucket 'gs://${BUCKET_NAME}' does not exist or is not accessible."
  echo "Please verify the bucket name and ensure it exists in your GCP project."
  validation_error
fi
log_message "✓ Cloud Storage bucket accessible"

# =============================================================================
# ANONYMIZATION SALT SETUP (if --anonymize is enabled)
# =============================================================================

ANON_SALT=""
SALT_STATUS=""
if [ "$ANONYMIZE" = "true" ]; then
  SALT_FILE="anonymize.salt"
  if [ -f "$SALT_FILE" ]; then
    if [ ! -r "$SALT_FILE" ]; then
      echo "Error: Salt file '$SALT_FILE' exists but is not readable."
      echo "Please check file permissions."
      validation_error
    fi
    ANON_SALT=$(cat "$SALT_FILE")
    SALT_STATUS="existing"
    log_message "✓ Salt file loaded: $SALT_FILE (existing)"
  else
    log_message "Generating salt file: $SALT_FILE"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' > "$SALT_FILE"
    else
      cat /proc/sys/kernel/random/uuid | tr -d '-' > "$SALT_FILE"
    fi
    chmod 600 "$SALT_FILE"
    ANON_SALT=$(cat "$SALT_FILE")
    SALT_STATUS="new"
    log_message "✓ Salt file generated: $SALT_FILE (new)"
    log_message "⚠️  Salt file is security-sensitive. Do not share it."
  fi

  # Validate salt is non-empty and contains only hex characters
  if [ -z "$ANON_SALT" ]; then
    echo "Error: Salt file '$SALT_FILE' is empty. Delete it and re-run to generate a new salt."
    validation_error
  fi
  if [[ ! "$ANON_SALT" =~ ^[a-f0-9]+$ ]]; then
    echo "Error: Salt file '$SALT_FILE' contains invalid characters. Expected lowercase hex string."
    validation_error
  fi
fi

# Set display versions of sensitive variables (redacted when anonymizing)
if [ "$ANONYMIZE" = "true" ]; then
  DISPLAY_BILLING_TABLE="[REDACTED]"
  DISPLAY_GCS_BUCKET="[REDACTED]"
  DISPLAY_PROJECT_FILTER="[REDACTED]"
else
  DISPLAY_BILLING_TABLE="$BILLING_TABLE"
  DISPLAY_GCS_BUCKET="$GCS_BUCKET"
  DISPLAY_PROJECT_FILTER="$PROJECT_FILTER"
fi

# =============================================================================
# DATE/MONTH CALCULATIONS
# =============================================================================

# Handle date range or month mode
if [ -n "$DATE_RANGE" ]; then
  USE_DATE_RANGE="true"
  
  # Validate date range does not exceed maximum
  if [ "$DATE_RANGE" -gt 31 ]; then
    echo "Error: Date range cannot exceed 31 days. Requested: $DATE_RANGE days"
    echo "For data spanning more than 31 days, use month mode (-m) instead."
    validation_error
  fi
  
  log_message "Calculating date range..."
  # Calculate dates ending 1 day ago (exclude only today for complete data)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    END_DATE=$(date -v-1d +%Y-%m-%d)
    START_DATE=$(date -v-1d -v-$((DATE_RANGE - 1))d +%Y-%m-%d)
  else
    END_DATE=$(date -d "yesterday" +%Y-%m-%d)
    START_DATE=$(date -d "yesterday - $((DATE_RANGE - 1)) days" +%Y-%m-%d)
  fi
  
  log_message "✓ Date range calculated: ${START_DATE} to ${END_DATE}"
else
  # Month mode validations
  # Extract and validate month component (01-12)
  log_message "Validating month value..."
  MONTH_PART="${CAPTURE_MONTH:4:2}"
  if [ "$MONTH_PART" -lt 1 ] || [ "$MONTH_PART" -gt 12 ]; then
    echo "Error: Invalid month value. Month must be between 01-12, got: $MONTH_PART"
    validation_error
  fi
  
  # Validate month is in the past (not current or future)
  CURRENT_MONTH=$(date +%Y%m)
  if [ "$CAPTURE_MONTH" -ge "$CURRENT_MONTH" ]; then
    echo "Error: Month must be in the past. Cannot extract data for current or future months."
    echo "Requested month: $CAPTURE_MONTH"
    echo "Current month: $CURRENT_MONTH"
    echo "Please specify a month before $CURRENT_MONTH"
    validation_error
  fi
  
  log_message "✓ Month value validated"
  
  # Calculate month boundaries directly into START_DATE and END_DATE
  log_message "Calculating month boundaries..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    START_DATE=$(date -j -f "%Y%m%d" "${CAPTURE_MONTH}01" +%Y-%m-%d)
    END_DATE=$(date -j -v+1m -v-1d -f "%Y%m%d" "${CAPTURE_MONTH}01" +%Y-%m-%d)
  else
    START_DATE=$(date -d "${CAPTURE_MONTH}01" +%Y-%m-%d)
    END_DATE=$(date -d "${CAPTURE_MONTH}01 + 1 month - 1 day" +%Y-%m-%d)
  fi
  log_message "✓ Month boundaries calculated: ${START_DATE} to ${END_DATE}"
fi

# Build WHERE clause based on mode
if [ "$USE_DATE_RANGE" = "true" ]; then
  # Date range mode - filter by exact partition dates
  WHERE_FILTER="DATE(_PARTITIONTIME) BETWEEN '${START_DATE}' AND '${END_DATE}' AND cost_type = 'regular'"
else
  # Month mode - filter by invoice month with partition buffer for late-arriving data
  PARTITION_BUFFER_START=$(add_days_to_date "$START_DATE" -1)
  PARTITION_BUFFER_END=$(add_days_to_date "$END_DATE" "$PARTITION_BUFFER_DAYS")
  WHERE_FILTER="DATE(_PARTITIONTIME) BETWEEN '${PARTITION_BUFFER_START}' AND '${PARTITION_BUFFER_END}' AND invoice.month = '${CAPTURE_MONTH}' AND cost_type = 'regular'"
fi

# Add project filter if specified
if [ -n "$PROJECT_FILTER" ]; then
  # Convert comma-separated to SQL IN clause: 'proj1','proj2'
  PROJECT_IN_CLAUSE=$(echo "$PROJECT_FILTER" | sed "s/[[:space:]]*,[[:space:]]*/,/g" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/")
  WHERE_FILTER="${WHERE_FILTER} AND project.id IN (${PROJECT_IN_CLAUSE})"
fi

if [ "$ANONYMIZE" = "true" ] && [ -n "$PROJECT_IN_CLAUSE" ]; then
  DISPLAY_WHERE="${WHERE_FILTER//$PROJECT_IN_CLAUSE/[REDACTED]}"
else
  DISPLAY_WHERE="$WHERE_FILTER"
fi
log_message "✓ WHERE filter built: ${DISPLAY_WHERE}"

# Format tags and labels for BigQuery
BQ_TAGS=$(format_array "$CAPTURE_TAGS")
BQ_LABELS=$(format_array "$CAPTURE_LABELS")

# =============================================================================
# DISPLAY CONFIGURATION
# =============================================================================

echo ""
echo "============================================="
echo "GCP Usage Discovery Configuration"
echo "============================================="
echo "  Billing Table:   ${DISPLAY_BILLING_TABLE}"
echo "  Output Bucket:   gs://${DISPLAY_GCS_BUCKET}"
echo "  Customer Name:   ${CUSTOMER_NAME}"

# Show either Invoice Month or Date Range (mutually exclusive)
if [ "$USE_DATE_RANGE" = "true" ]; then
  echo "  Date Range:      ${DATE_RANGE} days by partition date"
  echo "  Period:          ${START_DATE} to ${END_DATE}"
else
  echo "  Invoice Month:   ${CAPTURE_MONTH}"
fi

if [ -n "$PROJECT_FILTER" ]; then
  DISPLAY_PROJECT_IN_CLAUSE=$(if [ "$ANONYMIZE" = "true" ]; then echo "[REDACTED]"; else echo "${PROJECT_IN_CLAUSE}"; fi)
  echo "  Project Filter:  (${DISPLAY_PROJECT_IN_CLAUSE})"
fi

# Show Export Type only if using standard export
if [ "$USE_STANDARD_EXPORT" = "true" ]; then
  echo "  Export Type:     Standard (advanced)"
fi

# Show Anonymize flag if enabled
if [ "$ANONYMIZE" = "true" ]; then
  echo "  Anonymize:       Enabled (SHA512 with salt, 20-char output)"
  echo "  Salt File:       anonymize.salt ($SALT_STATUS)"
fi

echo "  Tags:            ${BQ_TAGS}"
echo "  Labels:          ${BQ_LABELS}"

# Inline warnings
if [ "$USE_STANDARD_EXPORT" = "true" ] || [ "$USE_DATE_RANGE" = "true" ]; then
  echo ""
  echo "  ⚠️  Advanced options are not supported by all downstream analysis tools"
fi
if [ "$ANONYMIZE" = "true" ]; then
  echo "  ⚠️  You will NOT be able to link results back to specific resources"
fi

echo "============================================="

# Confirmation prompt after displaying parameters
if [ "$SKIP_CONFIRM" != "true" ]; then
  echo ""
  read -rp "Proceed with these parameters to build and validate the query? (y/n): " PARAM_CONFIRM
  if [[ ! "$PARAM_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
  fi
fi

# Data availability check
echo ""
log_message "Checking data availability in billing table..."
echo "============================================="
echo "Data Availability Check"
echo "============================================="

# Build validation query
VALIDATION_QUERY="
SELECT 
  MIN(DATE(_PARTITIONTIME)) AS available_min_partition_date,
  MAX(DATE(_PARTITIONTIME)) AS available_max_partition_date
FROM \`${BILLING_TABLE}\`
WHERE
  ${WHERE_FILTER}
"

# Run validation query
if ! VALIDATION_CSV=$(bq query --project_id="$BILLING_PROJECT_ID" --location="$DATASET_LOCATION" --use_legacy_sql=false --format=csv --nouse_cache "$VALIDATION_QUERY" 2>&1); then
  echo "Error: Failed to check data availability"
  echo "$VALIDATION_CSV"
  validation_error
fi

# Parse results (skip header, get data row)
VALIDATION_ROW=$(echo "$VALIDATION_CSV" | tail -n 1)
AVAILABLE_MIN_PARTITION_DATE=$(echo "$VALIDATION_ROW" | cut -d',' -f1)
AVAILABLE_MAX_PARTITION_DATE=$(echo "$VALIDATION_ROW" | cut -d',' -f2)

# Check if data exists
if [ -z "$AVAILABLE_MIN_PARTITION_DATE" ] || [ "$AVAILABLE_MIN_PARTITION_DATE" = "null" ]; then
  echo "❌ ERROR: No data found for requested period"
  if [ "$USE_DATE_RANGE" = "true" ]; then
    echo "  Requested Range:  ${START_DATE} to ${END_DATE}"
  else
    echo "  Requested Month:  ${CAPTURE_MONTH}"
  fi
  echo ""
  echo "Please verify:"
  echo "  1. Billing export is enabled and has data"
  echo "  2. The requested time period has usage data"
  echo "  3. You have permissions to query the billing table"
  validation_error
fi

# Display availability
if [ "$USE_DATE_RANGE" = "true" ]; then
  echo "  Requested Range:        ${START_DATE} to ${END_DATE}"
else
  echo "  Requested Month:        ${CAPTURE_MONTH}"
  echo "  Expected Minimum Range: ${START_DATE} to ${END_DATE}"
fi

echo "  Available Range:        ${AVAILABLE_MIN_PARTITION_DATE} to ${AVAILABLE_MAX_PARTITION_DATE}"

# Check if available range covers requested range (same logic for both modes)
DATA_SUFFICIENT="true"
if [[ "$AVAILABLE_MIN_PARTITION_DATE" > "$START_DATE" ]] || [[ "$AVAILABLE_MAX_PARTITION_DATE" < "$END_DATE" ]]; then
  DATA_SUFFICIENT="false"
fi

if [ "$DATA_SUFFICIENT" = "true" ]; then
  echo "  Status:                 ✓ Data available for requested period"
  echo "============================================="
  log_message "✓ Data availability check passed"
else
  echo "  Status:                 ⚠️  WARNING: Available data is less than requested"
  echo "============================================="
  log_message "⚠️  Data availability check: partial data warning"
  echo ""
  echo "⚠️  DATA AVAILABILITY WARNING"
  echo "The billing table does not contain complete data for the requested period."
  echo ""
  
  # Force confirmation only if -y flag not used
  if [ "$SKIP_CONFIRM" != "true" ]; then
    read -rp "Available data is incomplete. Do you want to proceed with partial data? (y/n): " PARTIAL_CONFIRM
    if [[ ! "$PARTIAL_CONFIRM" =~ ^[Yy]$ ]]; then
      echo "Operation cancelled."
      exit 0
    fi
    echo ""
  fi
fi

# Set invoice month value based on mode (used in both query types)
if [ "$USE_DATE_RANGE" = "true" ]; then
  RUN_DATE=$(date +%Y%m%d)
  RANGE_PADDED=$(printf "%02d" "$DATE_RANGE")
  INVOICE_MONTH_VALUE="'${RUN_DATE}-${RANGE_PADDED}'"  # Script run date + range
else
  INVOICE_MONTH_VALUE="invoice.month"  # Use actual invoice month
fi

# Build query based on export type (detailed vs standard)
if [ "$USE_STANDARD_EXPORT" = "true" ]; then
  # Standard Export Query (no resource.name, resource.global_name, or resourceType)
  # Set projectID field based on anonymization
  if [ "$ANONYMIZE" = "true" ]; then
    PROJECT_ID_FIELD="IF(project.id IS NULL OR project.id = '', project.id, CONCAT('proj_', SUBSTR(TO_HEX(SHA512(CONCAT(project.id, '${ANON_SALT}'))), 1, 20)))"
  else
    PROJECT_ID_FIELD="project.id"
  fi
  
  BILLING_QUERY="
BEGIN
CREATE OR REPLACE TEMP TABLE gcp_usage_discovery_month AS
SELECT
    service.description AS serviceDescription,
    sku.id AS SKUID,
    sku.description AS SKUDescription,
    location.location AS Region,
    (CASE WHEN transaction_type = 'GOOGLE' THEN NULL ELSE transaction_type END) AS transactionType,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG(CONCAT(REGEXP_REPLACE(system_labels.key, r'^[^/]+/', ''), ':', system_labels.value) IGNORE NULLS ORDER BY system_labels.key), ';') 
     FROM UNNEST(system_labels) AS system_labels) AS spec,
    (CASE WHEN consumption_model.description = 'Default' THEN '' ELSE consumption_model.description END) AS consumptionModelDescription,
    SUM(CAST(usage.amount_in_pricing_units AS NUMERIC)) AS usageInPricingUnits,
    usage.pricing_unit AS usagePricingUnit,
    ${PROJECT_ID_FIELD} AS projectID,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG((CASE WHEN tags.key IN UNNEST(${BQ_TAGS}) THEN CONCAT(tags.key, ':', tags.value) ELSE NULL END) IGNORE NULLS ORDER BY tags.key), ';') 
     FROM UNNEST(tags) AS tags) AS environmentTags,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG((CASE WHEN labels.key IN UNNEST(${BQ_LABELS}) THEN CONCAT(labels.key, ':', labels.value) ELSE NULL END) IGNORE NULLS ORDER BY labels.key), ';') 
     FROM UNNEST(labels) AS labels) AS environmentLabels,
    SUM(CAST(cost_at_list AS NUMERIC)) AS costAtList,
    SUM(CAST((cost_at_list / currency_conversion_rate) AS NUMERIC)) AS costAtListUSD,
    SUM(CAST(cost_at_list_consumption_model AS NUMERIC)) AS costAtListConsumptionModel,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'FEE_UTILIZATION_OFFSET')) AS feeUtilizationOffset,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'COMMITTED_USAGE_DISCOUNT_DOLLAR_BASE')) AS committedUsageDiscountDollarBase,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'COMMITTED_USAGE_DISCOUNT')) AS committedUsageDiscount,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'FREE_TIER')) AS freeTier,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'SUBSCRIPTION_BENEFIT')) AS subscriptionBenefit,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'SUSTAINED_USAGE_DISCOUNT')) AS sustainedUsageDiscount,
    currency AS currency
FROM
    \`${BILLING_TABLE}\`
WHERE
    ${WHERE_FILTER}
GROUP BY
    serviceDescription,
    SKUID,
    SKUDescription,
    Region,
    transactionType,
    spec,
    consumptionModelDescription,
    usagePricingUnit,
    projectID,
    environmentTags,
    environmentLabels,
    currency
ORDER BY
    serviceDescription,
    spec,
    SKUDescription,
    Region,
    projectID;

EXPORT DATA
OPTIONS (
    uri = 'gs://${GCS_BUCKET}/gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${CAPTURE_PERIOD}-*.csv.gz',
    format = 'CSV',
    compression = 'GZIP',
    overwrite = true,
    header = true
) AS
SELECT * FROM gcp_usage_discovery_month;

END;
"
else
  # Detailed Export Query (includes resource.name, resource.global_name, and resourceType)
  # Set resource and project fields based on anonymization
  if [ "$ANONYMIZE" = "true" ]; then
    # Fully anonymize sensitive identifiers (SHA512 + salt, 20-char output, null/empty guard)
    # Extract last path segment first (consistent with non-anonymized output and Python anonymizer)
    RESOURCE_NAME_FIELD="IF(resource.name IS NULL OR resource.name = '', resource.name, CONCAT('res_', SUBSTR(TO_HEX(SHA512(CONCAT(COALESCE(REGEXP_EXTRACT(resource.name, r'/([^/]+)$'), resource.name), '${ANON_SALT}'))), 1, 20)))"
    RESOURCE_GLOBAL_NAME_FIELD="IF(resource.global_name IS NULL OR resource.global_name = '', resource.global_name, CONCAT('global_', SUBSTR(TO_HEX(SHA512(CONCAT(COALESCE(REGEXP_EXTRACT(resource.global_name, r'/([^/]+)$'), resource.global_name), '${ANON_SALT}'))), 1, 20)))"
    PROJECT_ID_FIELD="IF(project.id IS NULL OR project.id = '', project.id, CONCAT('proj_', SUBSTR(TO_HEX(SHA512(CONCAT(project.id, '${ANON_SALT}'))), 1, 20)))"
  else
    RESOURCE_NAME_FIELD="COALESCE(REGEXP_EXTRACT(resource.name, r'/([^/]+)$'), resource.name)"
    RESOURCE_GLOBAL_NAME_FIELD="COALESCE(REGEXP_EXTRACT(resource.global_name, r'/([^/]+)$'), resource.global_name)"
    PROJECT_ID_FIELD="project.id"
  fi
  
  BILLING_QUERY="
BEGIN
CREATE OR REPLACE TEMP TABLE gcp_usage_discovery_month AS
SELECT
    service.description AS serviceDescription,
    ${RESOURCE_NAME_FIELD} AS resourceName,
    ${RESOURCE_GLOBAL_NAME_FIELD} AS resourceGlobalName,
    COALESCE(REGEXP_EXTRACT(resource.global_name, r'/([^/]+)/[^/]+$'), 'Unassigned') AS resourceType,
    sku.id AS SKUID,
    sku.description AS SKUDescription,
    location.location AS Region,
    (CASE WHEN transaction_type = 'GOOGLE' THEN NULL ELSE transaction_type END) AS transactionType,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG(CONCAT(REGEXP_REPLACE(system_labels.key, r'^[^/]+/', ''), ':', system_labels.value) IGNORE NULLS ORDER BY system_labels.key), ';') 
     FROM UNNEST(system_labels) AS system_labels) AS spec,
    (CASE WHEN consumption_model.description = 'Default' THEN '' ELSE consumption_model.description END) AS consumptionModelDescription,
    SUM(CAST(usage.amount_in_pricing_units AS NUMERIC)) AS usageInPricingUnits,
    usage.pricing_unit AS usagePricingUnit,
    ${PROJECT_ID_FIELD} AS projectID,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG((CASE WHEN tags.key IN UNNEST(${BQ_TAGS}) THEN CONCAT(tags.key, ':', tags.value) ELSE NULL END) IGNORE NULLS ORDER BY tags.key), ';') 
     FROM UNNEST(tags) AS tags) AS environmentTags,
    (SELECT ARRAY_TO_STRING(ARRAY_AGG((CASE WHEN labels.key IN UNNEST(${BQ_LABELS}) THEN CONCAT(labels.key, ':', labels.value) ELSE NULL END) IGNORE NULLS ORDER BY labels.key), ';') 
     FROM UNNEST(labels) AS labels) AS environmentLabels,
    SUM(CAST(cost_at_list AS NUMERIC)) AS costAtList,
    SUM(CAST((cost_at_list / currency_conversion_rate) AS NUMERIC)) AS costAtListUSD,
    SUM(CAST(cost_at_list_consumption_model AS NUMERIC)) AS costAtListConsumptionModel,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'FEE_UTILIZATION_OFFSET')) AS feeUtilizationOffset,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'COMMITTED_USAGE_DISCOUNT_DOLLAR_BASE')) AS committedUsageDiscountDollarBase,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'COMMITTED_USAGE_DISCOUNT')) AS committedUsageDiscount,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'FREE_TIER')) AS freeTier,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'SUBSCRIPTION_BENEFIT')) AS subscriptionBenefit,
    SUM((SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) c WHERE c.type = 'SUSTAINED_USAGE_DISCOUNT')) AS sustainedUsageDiscount,
    currency AS currency
FROM
    \`${BILLING_TABLE}\`
WHERE
    ${WHERE_FILTER}
GROUP BY
    serviceDescription,
    resourceName,
    resourceGlobalName,
    resourceType,
    SKUID,
    SKUDescription,
    Region,
    transactionType,
    spec,
    consumptionModelDescription,
    usagePricingUnit,
    projectID,
    environmentTags,
    environmentLabels,
    currency
ORDER BY
    serviceDescription,
    resourceGlobalName,
    resourceName,
    SKUDescription,
    Region,
    projectID;

EXPORT DATA
OPTIONS (
    uri = 'gs://${GCS_BUCKET}/gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${CAPTURE_PERIOD}-*.csv.gz',
    format = 'CSV',
    compression = 'GZIP',
    overwrite = true,
    header = true
) AS
SELECT * FROM gcp_usage_discovery_month;

END;
"
fi

echo ""
echo "============================================="
echo "BigQuery Query & Validation"
echo "============================================="
# Redact sensitive values from displayed query for log safety
if [ -n "$ANON_SALT" ]; then
  DISPLAY_QUERY="${BILLING_QUERY//$ANON_SALT/[REDACTED]}"
  DISPLAY_QUERY="${DISPLAY_QUERY//$BILLING_TABLE/[REDACTED]}"
  DISPLAY_QUERY="${DISPLAY_QUERY//$GCS_BUCKET/[REDACTED]}"
  if [ -n "$PROJECT_IN_CLAUSE" ]; then
    DISPLAY_QUERY="${DISPLAY_QUERY//$PROJECT_IN_CLAUSE/[REDACTED]}"
  fi
  echo "$DISPLAY_QUERY"
else
  echo "$BILLING_QUERY"
fi
echo ""

# Validate query
log_message "Validating query..."
if ! VALIDATION_OUTPUT=$(bq query --project_id="$BILLING_PROJECT_ID" --location="$DATASET_LOCATION" --dry_run --use_legacy_sql=false "$BILLING_QUERY" 2>&1); then
  echo "Error: Query validation failed"
  echo "$VALIDATION_OUTPUT"
  validation_error
fi
log_message "✓ Query validated"

# Exit if dry-run mode
if [ "$DRY_RUN" = "true" ]; then
  echo ""
  log_message "DRY RUN MODE - Query validation complete, no data extracted"
  echo ""
  echo "To execute this query, remove --dry-run flag"
  exit 0
fi

echo ""
echo "Permissions: Write access to Cloud Storage will be verified during export"
echo "Cost: BigQuery query costs are typically minimal and vary based on data volume"
echo ""
echo "Next Steps:"
echo "  - Review the query displayed above"
echo "  - Confirm below to proceed with execution"
echo "============================================="

# Confirmation prompt
if [ "$SKIP_CONFIRM" != "true" ]; then
  echo ""
  read -rp "Do you want to proceed with the query execution and export? (y/n): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
  fi
fi

echo ""
log_message "Running BigQuery export..."
QUERY_START_TS=$(date +'%Y-%m-%d %H:%M:%S %Z')
QUERY_START_EPOCH=$(date +%s)
bq query --project_id="$BILLING_PROJECT_ID" --location="$DATASET_LOCATION" --use_legacy_sql=false --nouse_cache "$BILLING_QUERY" > /dev/null
QUERY_END_TS=$(date +'%Y-%m-%d %H:%M:%S %Z')
QUERY_END_EPOCH=$(date +%s)
QUERY_DURATION=$((QUERY_END_EPOCH - QUERY_START_EPOCH))
log_message "BigQuery export completed successfully."
echo ""

# Output execution metadata as JSON
echo ""
echo "=== EXECUTION METADATA START ==="
cat << EOF
{
  "customer_name": "${CUSTOMER_NAME}",
  "script_version": "${BASE_VERSION}",
  "dataset_location": "${DATASET_LOCATION}",
  "query_format": "${QUERY_FORMAT}",
  "capture_period": "${CAPTURE_PERIOD}",
  "date_range_days": ${DATE_RANGE:-null},
  "start_date": "${START_DATE}",
  "end_date": "${END_DATE}",
  "available_min_date": "${AVAILABLE_MIN_PARTITION_DATE}",
  "available_max_date": "${AVAILABLE_MAX_PARTITION_DATE}",
  "data_sufficient": ${DATA_SUFFICIENT},
  "tags": "${CAPTURE_TAGS}",
  "labels": "${CAPTURE_LABELS}",
  "project_filter": "${DISPLAY_PROJECT_FILTER}",
  "anonymize": ${ANONYMIZE},
  "script_start_timestamp": "${SCRIPT_START_TS}",
  "query_start_timestamp": "${QUERY_START_TS}",
  "query_end_timestamp": "${QUERY_END_TS}",
  "query_duration_seconds": ${QUERY_DURATION},
  "expected_results_zip_file": "${RESULTS_ZIP_NAME}"
}
EOF
echo "=== EXECUTION METADATA END ==="
echo ""

echo ""
echo "============================================="
echo "Packaging results"
echo "============================================="
log_message "Starting results packaging..."

# Create folder (name already set at top of script)
log_message "Creating results folder..."
mkdir -p "$RESULTS_FOLDER_NAME"
log_message "✓ Results folder created"

# Download CSV.GZ files from Cloud Storage directly into folder
log_message "Downloading CSV.GZ files from Cloud Storage..."
log_message "Note: Large extractions may take several minutes to download"
if [ "$ANONYMIZE" = "true" ]; then
  gcloud storage cp "gs://${GCS_BUCKET}/gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${CAPTURE_PERIOD}-*.csv.gz" "$RESULTS_FOLDER_NAME/" > /dev/null 2>&1
else
  gcloud storage cp "gs://${GCS_BUCKET}/gcp_usage_${CUSTOMER_NAME}_${CURRENT_TS}_${QUERY_FORMAT}_${CAPTURE_PERIOD}-*.csv.gz" "$RESULTS_FOLDER_NAME/"
fi
log_message "✓ Download complete"

# Copy log file to folder
log_message "Copying log file..."
log_message "✓ Extraction complete. Creating ZIP archive next."
cp "$LOG_FILE_LOCAL" "$RESULTS_FOLDER_NAME/"
log_message "✓ Log file copied"

# Create ZIP archive
log_message "Creating ZIP archive: $RESULTS_ZIP_NAME..."
zip -r -0 "$RESULTS_ZIP_NAME" "$RESULTS_FOLDER_NAME"
log_message "✓ ZIP archive created"

# Get ZIP size
RESULTS_ZIP_SIZE=$(du -sh "$RESULTS_ZIP_NAME" | cut -f1)

# Clean up folder
log_message "Cleaning up temporary files..."
rm -rf "$RESULTS_FOLDER_NAME"
log_message "✓ Packaging succeeded"

echo ""
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│  ⚠️  SHARE/UPLOAD RESULTS ZIP                                │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "Results ZIP File: $RESULTS_ZIP_NAME"
echo "Results ZIP File Size: $RESULTS_ZIP_SIZE"
echo ""
echo "Next Steps:"
echo "1. Download the Results ZIP file from Cloud Shell"
echo "2. Share with your AWS representative or upload to analysis tool"
echo ""
echo "Note: When you share the output from resource-discovery-for-gcp with AWS or an AWS partner, it will be processed on AWS infrastructure. The AWS Region used for processing depends on the service used for analysis."
echo "Note: Original files remain in Cloud Storage Bucket: gs://${DISPLAY_GCS_BUCKET}"
echo ""
echo "============================================="
echo ""

exit 0