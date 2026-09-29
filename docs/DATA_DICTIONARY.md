# Data Dictionary

The following table describes the columns extracted by the script. Columns marked "Detailed export only" are omitted from standard exports. Definitions are based on the [GCP Billing Export Schema](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/detailed-usage).

| Column Name | Type | Description |
|-------------|------|-------------|
| **serviceDescription** | String | The Google Cloud service that reported the data. |
| **resourceName** | String | Detailed export only. The last path segment of the resource name (e.g., "instance-20251221-065118", "my-disk"). NULL for BigQuery Analysis rows (serviceDescription 'BigQuery', SKUDescription starting with 'Analysis') and BigQuery Reservation API job rows (serviceDescription 'BigQuery Reservation API', resourceType 'jobs'). For simple names without paths, the value is preserved as-is. When `--anonymize` is used, this is hashed to a 24-character value (e.g., "res_a3f5c8d9e2b14f6a7890"). |
| **resourceGlobalName** | String | Detailed export only. The last path segment of the resource identifier (e.g., "vm-1", "data1", "my-bucket"). NULL for BigQuery Analysis rows (serviceDescription 'BigQuery', SKUDescription starting with 'Analysis') and BigQuery Reservation API job rows (serviceDescription 'BigQuery Reservation API', resourceType 'jobs'). When `--anonymize` is used, this is hashed to a 27-character value (e.g., "global_a3f5c8d9e2b14f6a7890"). |
| **resourceType** | String | Detailed export only. The type of resource extracted from the global name path (e.g., "instances", "disks", "tables", "buckets"). Shows "Unassigned" if the type cannot be determined. This column is always visible, even when anonymized. |
| **projectID** | String | The ID of the Google Cloud project that generated the data. When `--anonymize` is used, this is hashed to a 25-character value (e.g., "proj_a3f5c8d9e2b14f6a7890"). |
| **SKUID** | String | The ID of the resource used by the service. |
| **SKUDescription** | String | A description of the resource type used by the service (e.g., "Standard Storage US"). |
| **Region** | String | Location of usage at the level of a multi-region, country, region, or zone. |
| **transactionType** | String | The transaction type of the seller (GOOGLE, THIRD_PARTY_RESELLER, or THIRD_PARTY_AGENCY). |
| **spec** | String | System-generated labels on the resource with service prefixes removed (e.g., "cores:4;memory:15360;object_state:live"). Original format like "compute.googleapis.com/cores:4" is simplified to "cores:4" for conciseness. |
| **consumptionModelDescription** | String | The description of the consumption model. Note: "default" values are normalized to blank. |
| **environmentTags** | String | Captured tags matching the configured tag keys (semicolon-separated key:value pairs). |
| **environmentLabels** | String | Captured labels matching the configured label keys (semicolon-separated key:value pairs). |
| **usageInPricingUnits** | Float | The quantity of usage in pricing units. |
| **usagePricingUnit** | String | The unit in which resource usage is measured (e.g., "gibibyte month"). |
| **usageWindowMin** | Float | Minimum positive net usage-window total. |
| **usageWindowMax** | Float | Maximum positive net usage-window total. |
| **usageWindowMedian** | Float | Approximate median of positive net usage-window totals. |
| **usageWindowP95** | Float | Approximate 95th percentile of positive net usage-window totals. |
| **usageWindowCount** | Integer | Number of positive net usage windows used by the window statistics. |
| **rowCount** | Integer | Number of raw billing line items aggregated into this row. |
| **distinctResourceCount** | Integer | Detailed export only. Count of distinct original resource identifiers aggregated into this row. |
| **costAtList** | Float | List price in the billing currency (publicly available pricing). |
| **costAtListUSD** | Float | List price in USD (publicly available pricing). |
| **costAtListConsumptionModel** | Float | List price per the applicable consumption model in the billing currency (publicly available pricing). |
| **feeUtilizationOffset** | Float | Credit used to offset fees paid to purchase spend-based CUDs (in billing currency). |
| **committedUsageDiscountDollarBase** | Float | Credit earned for legacy spend-based committed use discounts (in billing currency). |
| **committedUsageDiscount** | Float | Credit for resource-based committed use contracts (Compute Engine) (in billing currency). |
| **freeTier** | Float | Credit applied for free tier usage (in billing currency). |
| **subscriptionBenefit** | Float | Credit earned by purchasing long-term subscriptions (in billing currency). |
| **sustainedUsageDiscount** | Float | Automatic discount for running eligible Compute Engine resources for a significant portion of the billing month (in billing currency). |
| **currency** | String | The currency that the cost is billed in. |

**Usage-window statistics:** Usage is netted across consumption models for each start/end window. Detailed exports calculate statistics per resource when identifiers exist; standard exports calculate them per project/SKU.

**Note:** This extract includes only publicly available list prices and list credits. Negotiated pricing, adjustments, rounding errors, and taxes are not included.

**Anonymization:** The `--anonymize` flag hashes `resourceName`, `resourceGlobalName`, and `projectID` using SHA512 with a local random salt. `resourceType` remains visible. Reusing the same salt produces consistent hashes across runs.

**Salt file security:** Keep `anonymize.salt` private. Anyone with the salt can test known identifiers against the anonymized values.

**IMPORTANT:** When using anonymization, you will NOT be able to link the pricing results back to specific resources in your GCP environment. Use this option only when identifier protection is required and you accept this limitation.
