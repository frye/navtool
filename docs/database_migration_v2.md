# Database Migration Documentation

## Overview
This document describes the database migration from version 1 to version 2, which adds NOAA-specific chart metadata and storage capabilities to NavTool.

## Migration Summary
- **From Version**: 1
- **To Version**: 2
- **Purpose**: Add NOAA chart metadata storage and caching capabilities
- **Migration Method**: Automated schema upgrade during app initialization

## Schema Changes

### 1. Charts Table Extensions
The existing `charts` table has been extended with NOAA-specific metadata fields:

```sql
-- New columns added to charts table
ALTER TABLE charts ADD COLUMN cell_name TEXT;
ALTER TABLE charts ADD COLUMN usage_band TEXT;
ALTER TABLE charts ADD COLUMN edition_number INTEGER DEFAULT 0;
ALTER TABLE charts ADD COLUMN update_number INTEGER DEFAULT 0;
ALTER TABLE charts ADD COLUMN compilation_scale INTEGER;
ALTER TABLE charts ADD COLUMN region TEXT;
ALTER TABLE charts ADD COLUMN dt_pub TEXT;
ALTER TABLE charts ADD COLUMN issue_date TEXT;
ALTER TABLE charts ADD COLUMN source_date_string TEXT;
ALTER TABLE charts ADD COLUMN edition_date TEXT;
ALTER TABLE charts ADD COLUMN boundary_polygon TEXT;
ALTER TABLE charts ADD COLUMN source TEXT DEFAULT "noaa";
ALTER TABLE charts ADD COLUMN status TEXT DEFAULT "current";
```

**Field Descriptions:**
- `cell_name`: NOAA chart cell identifier (e.g., "US5TX22M")
- `usage_band`: Chart usage classification (Overview, General, Coastal, Approach, Harbor, Berthing)
- `edition_number`: Chart edition number for version tracking
- `update_number`: Chart update number within edition
- `compilation_scale`: Scale used for chart compilation
- `region`: NOAA geographic region designation
- `dt_pub`: Publication date string from NOAA
- `issue_date`: Formal issue date
- `source_date_string`: Source data date information
- `edition_date`: Edition publication date
- `boundary_polygon`: GeoJSON polygon string defining chart boundaries
- `source`: Chart data source (noaa, ukho, ic, other)
- `status`: Chart status (current, superseded, cancelled, preliminary)

### 2. State-Chart Mapping Table Extensions
Extended the existing `state_chart_mapping` table:

```sql
-- New columns added to state_chart_mapping table
ALTER TABLE state_chart_mapping ADD COLUMN coverage_percentage REAL DEFAULT 0.0;
ALTER TABLE state_chart_mapping ADD COLUMN updated_at TEXT;
```

**Field Descriptions:**
- `coverage_percentage`: Percentage of state area covered by the chart
- `updated_at`: Timestamp for tracking mapping updates

### 3. New Chart Catalog Cache Table
Stores cached NOAA chart catalog data for performance optimization:

```sql
CREATE TABLE chart_catalog_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  catalog_type TEXT NOT NULL DEFAULT 'noaa',
  catalog_data TEXT NOT NULL,
  catalog_hash TEXT,
  last_updated TEXT NOT NULL,
  etag TEXT,
  is_valid INTEGER DEFAULT 1,
  expires_at TEXT
);
```

**Field Descriptions:**
- `catalog_type`: Type of catalog (noaa, future extensibility for other sources)
- `catalog_data`: Full GeoJSON catalog data
- `catalog_hash`: SHA-256 hash for change detection
- `last_updated`: When cache entry was created
- `etag`: HTTP ETag header for efficient cache validation
- `is_valid`: Boolean flag for cache validity
- `expires_at`: Expiration timestamp for automatic cleanup

### 4. New Chart Update History Table
Tracks chart version changes for update management:

```sql
CREATE TABLE chart_update_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cell_name TEXT NOT NULL,
  old_edition INTEGER,
  new_edition INTEGER,
  old_update_number INTEGER,
  new_update_number INTEGER,
  update_detected_at TEXT NOT NULL
);
```

**Field Descriptions:**
- `cell_name`: NOAA chart cell identifier
- `old_edition`: Previous edition number
- `new_edition`: Updated edition number
- `old_update_number`: Previous update number
- `new_update_number`: Updated update number
- `update_detected_at`: When the update was detected

## Index Optimizations

### New Indexes for Performance
```sql
-- Chart table indexes for NOAA operations
CREATE INDEX idx_charts_cell_name ON charts (cell_name);
CREATE INDEX idx_charts_usage_band ON charts (usage_band);
CREATE INDEX idx_charts_region ON charts (region);
CREATE INDEX idx_charts_source ON charts (source);

-- State-chart mapping indexes
CREATE INDEX idx_state_chart_mapping_cell ON state_chart_mapping (cell_name);
CREATE INDEX idx_state_chart_mapping_coverage ON state_chart_mapping (coverage_percentage);

-- Catalog cache indexes
CREATE INDEX idx_catalog_cache_type ON chart_catalog_cache (catalog_type);
CREATE INDEX idx_catalog_cache_valid ON chart_catalog_cache (is_valid);
CREATE INDEX idx_catalog_cache_expires ON chart_catalog_cache (expires_at);

-- Update history indexes
CREATE INDEX idx_chart_history_cell ON chart_update_history (cell_name);
CREATE INDEX idx_chart_history_detected ON chart_update_history (update_detected_at);
```

## Migration Process

### Automatic Migration
The migration is performed automatically when the app detects a database version mismatch:

1. **Detection**: App checks database version during initialization
2. **Backup**: Existing data is preserved during migration
3. **Schema Update**: New columns and tables are added
4. **Index Creation**: Performance indexes are created
5. **Validation**: Migration success is verified

### Error Handling
- All migration operations are wrapped in a database transaction
- If migration fails, the transaction is rolled back
- Detailed error logging for debugging
- Graceful fallback to prevent data loss

### Performance Considerations
- Migration is designed to be fast (typically < 100ms)
- Minimal impact on existing data
- Indexes are created after data migration for efficiency
- Uses efficient ALTER TABLE operations where possible

## Usage Examples

### Storing NOAA Charts
```dart
final chart = Chart(
  id: 'US5TX22M_15_3',
  title: 'Galveston Bay',
  scale: 80000,
  bounds: bounds,
  lastUpdate: DateTime.now(),
  state: 'Texas',
  type: ChartType.coastal,
  source: ChartSource.noaa,
  edition: 15,
  updateNumber: 3,
  metadata: {
    'cell_name': 'US5TX22M',
    'usage_band': 'Coastal',
    'region': 'Region 5',
    'boundary_polygon': '{"type":"Polygon",...}',
  },
);

await storageService.storeChart(chart, chartData);
```

### Using NOAA Extensions
```dart
// Cache catalog data
await storageService.updateChartCatalog(catalogJson, etag: etag);

// Get cached catalog
final cached = await storageService.getCachedCatalog();

// Check for updates
final updateAvailable = await storageService.isChartUpdateAvailable(
  'US5TX22M', 15, 3);

// Record update history
await storageService.recordChartUpdate('US5TX22M', 14, 15, 2, 3);
```

## Backward Compatibility
- All existing chart data remains accessible
- New features are additive, not replacing existing functionality
- Applications can continue using base Chart functionality
- NOAA extensions are optional and gracefully handled

## Testing Coverage
- 22 comprehensive tests for NOAA functionality
- Database migration testing
- Schema validation tests
- Performance benchmark tests
- Error handling validation

## Future Considerations
- Schema designed for extensibility to support additional chart sources
- Catalog cache system can accommodate other data providers
- Update tracking system supports various versioning schemes
- Index structure optimized for marine navigation query patterns