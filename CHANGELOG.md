# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [9.10.0] - 2026-08-01

### Added
- Usage distribution columns on both exports: `rowCount`, `usageMin`, `usageMax`, `usageMedian`, `usageP95`.
- `distinctResourceCount` on the detailed export (count of distinct `resource.global_name` per row).
- `-r` and `--use-standard-export` now shown in `-h` output under an Advanced section.

### Changed
- BigQuery Analysis line items are collapsed: `resourceName` and `resourceGlobalName` are set to NULL when `serviceDescription = 'BigQuery'` and `SKUDescription` starts with `Analysis`, reducing row count and output size. `resourceType` is unaffected.
- Anonymization now hashes the derived resource identifier (last path segment, after collapse) instead of the raw `resource.name` / `resource.global_name`.
- Export columns reordered to group related fields; `GROUP BY` order aligned with the `SELECT` list.
- Column count increased from 25 to 31 (detailed export) and 22 to 27 (standard export).

### Fixed
- Billing table accessibility error no longer prints a blank table name; display variables are now set before first use.
- `add_days_to_date` handles negative day offsets on macOS (month-mode partition buffer), which previously produced a malformed `date -v+-1d`.


## [9.9.0] - 2026-05-08

### Added
- Initial public release.

