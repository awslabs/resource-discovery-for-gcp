# Data Dictionary

The following table describes each column extracted by the script (25 columns for detailed export, 22 for standard export). Definitions are based on the [GCP Billing Export Schema](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/detailed-usage).

| Column Name | Type | Description |
|-------------|------|-------------|
| **serviceDescription** | String | The Google Cloud service that reported the data. |
| **resourceName** | String | The last path segment of the resource name (e.g., "instance-20251221-065118", "my-disk"). For simple names without paths, the value is preserved as-is. When `--anonymize` is used, this is hashed to a 24-character value (e.g., "res_a3f5c8d9e2b14f6a7890"). |
| **resourceGlobalName** | String | The last path segment of the resource identifier (e.g., "vm-1", "data1", "my-bucket"). When `--anonymize` is used, this is hashed to a 27-character value (e.g., "global_a3f5c8d9e2b14f6a7890"). |
| **resourceType** | String | The type of resource extracted from the global name path (e.g., "instances", "disks", "tables", "buckets"). Shows "Unassigned" if the type cannot be determined. This column is always visible, even when anonymized. |
| **SKUID** | String | The ID of the resource used by the service. |
| **SKUDescription** | String | A description of the resource type used by the service (e.g., "Standard Storage US"). |
| **Region** | String | Location of usage at the level of a multi-region, country, region, or zone. |
| **transactionType** | String | The transaction type of the seller (GOOGLE, THIRD_PARTY_RESELLER, or THIRD_PARTY_AGENCY). |
| **spec** | String | System-generated labels on the resource with service prefixes removed (e.g., "cores:4;memory:15360;object_state:live"). Original format like "compute.googleapis.com/cores:4" is simplified to "cores:4" for conciseness. |
| **consumptionModelDescription** | String | The description of the consumption model. Note: "default" values are normalized to blank. |
| **usageInPricingUnits** | Float | The quantity of usage in pricing units. |
| **usagePricingUnit** | String | The unit in which resource usage is measured (e.g., "gibibyte month"). |
| **projectID** | String | The ID of the Google Cloud project that generated the data. When `--anonymize` is used, this is hashed to a 25-character value (e.g., "proj_a3f5c8d9e2b14f6a7890"). |
| **environmentTags** | String | Captured tags matching the configured tag keys (semicolon-separated key:value pairs). |
| **environmentLabels** | String | Captured labels matching the configured label keys (semicolon-separated key:value pairs). |
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

**Note:** This extract includes only publicly available list prices and list credits. Negotiated pricing, adjustments, rounding errors, and taxes are not included.

**Anonymization:** When the `--anonymize` flag is used, sensitive identifiers are hashed using SHA512 with a random salt and 20-character hex output plus prefix:
- **resourceName**: Last path segment is extracted first, then hashed (e.g., "res_a3f5c8d9e2b14f6a7890")
- **resourceGlobalName**: Last path segment is extracted first, then hashed (e.g., "global_a3f5c8d9e2b14f6a7890")
- **resourceType**: Always visible (e.g., "instances", "disks", "tables") - extracted from the path for analysis
- **projectID**: Fully hashed (e.g., "proj_a3f5c8d9e2b14f6a7890")

This approach maintains the ability to link multiple line items to the same resource while protecting sensitive identifiers. The same identifier always produces the same hash as long as the same salt file is used, maintaining data relationships across extraction runs. The resourceType column provides resource classification for analysis without exposing sensitive information. Blank or null resource names are preserved as blank (not hashed).

**Salt file security:** The salt file (`anonymize.salt`) is security-sensitive. Anyone who obtains both the salt and the anonymized output can recover resource and project identifiers by hashing known values against the salt. Do not share the salt file.

**⚠️ IMPORTANT:** When using anonymization, you will NOT be able to link the pricing results back to specific resources in your GCP environment. The anonymized results may be difficult to relate to your actual infrastructure. Use this option only when identifier protection is required and you understand this limitation.
