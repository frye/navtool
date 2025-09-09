# Chart Storage Architecture Documentation

## Overview

NavTool's Local Chart Storage system provides efficient storage, indexing, and retrieval of Electronic Navigational Charts (ENCs) in S-57 format. The system is optimized for marine navigation requirements, supporting real-time chart access with sub-100ms lookup performance for harbor-scale charts.

## Architecture Components

### 1. Storage Service Interface

**Location**: `lib/core/services/storage_service.dart`

The `StorageService` abstract interface defines all chart storage operations:

```dart
abstract class StorageService {
  // Core chart operations
  Future<void> storeChart(Chart chart, List<int> data);
  Future<List<int>?> loadChart(String chartId);
  Future<void> deleteChart(String chartId);
  
  // Storage management
  Future<Map<String, dynamic>> getStorageInfo();
  Future<void> cleanupOldData();
  Future<int> getStorageUsage();
  
  // Spatial operations
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds);
}
```

### 2. Database Storage Implementation

**Location**: `lib/core/services/database_storage_service.dart`

SQLite-based implementation providing:

#### Database Schema

```sql
-- Core chart metadata
CREATE TABLE charts (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  scale INTEGER NOT NULL,
  bounds_north REAL NOT NULL,
  bounds_south REAL NOT NULL,
  bounds_east REAL NOT NULL,
  bounds_west REAL NOT NULL,
  last_update INTEGER NOT NULL,
  state TEXT,
  type TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  file_size INTEGER DEFAULT 0,
  -- NOAA-specific extensions
  cell_name TEXT,
  usage_band TEXT,
  edition_number INTEGER DEFAULT 0,
  update_number INTEGER DEFAULT 0,
  compilation_scale INTEGER,
  region TEXT,
  source TEXT DEFAULT 'noaa',
  status TEXT DEFAULT 'current'
);

-- Binary chart data with compression
CREATE TABLE chart_data (
  chart_id TEXT PRIMARY KEY,
  data BLOB NOT NULL,
  compressed INTEGER DEFAULT 1,
  original_size INTEGER NOT NULL,
  stored_at INTEGER NOT NULL,
  FOREIGN KEY (chart_id) REFERENCES charts (id)
);
```

#### Performance Indexes

```sql
-- Spatial query optimization
CREATE INDEX idx_charts_bounds ON charts (bounds_north, bounds_south, bounds_east, bounds_west);

-- Chart lookup optimization
CREATE INDEX idx_charts_cell_name ON charts (cell_name);
CREATE INDEX idx_charts_usage_band ON charts (usage_band);
CREATE INDEX idx_charts_scale ON charts (scale);
```

### 3. S-57 Parser Integration

**Location**: `lib/core/services/s57/s57_parser.dart`

The S-57 parser extracts chart features and metadata:

- **Feature Extraction**: Navigation aids, bathymetry, coastlines
- **Spatial Data**: Coordinates and geometry
- **Metadata**: Chart bounds, scale, edition information

### 4. Spatial Indexing System

**Locations**: 
- `lib/core/services/s57/s57_spatial_index.dart` (Linear index)
- `lib/core/services/s57/s57_spatial_tree.dart` (R-tree index)

#### Adaptive Indexing Strategy

```dart
class SpatialIndexFactory {
  static SpatialIndex create(List<S57Feature> features, {RTreeConfig? config}) {
    if (features.length < 200 || config?.forceLinear == true) {
      // Linear index for small datasets
      final index = S57SpatialIndex();
      index.addFeatures(features);
      return index;
    } else {
      // R-tree for large datasets
      return S57SpatialTree.bulkLoad(features, config: config);
    }
  }
}
```

### 5. Compression and Optimization

**Location**: `lib/core/services/compression_service.dart`

Chart data compression reduces storage footprint:

- **Compression Levels**: Fast, Balanced, Maximum
- **Algorithms**: GZIP with configurable parameters
- **Optimization**: Automatic compression level selection

## Performance Specifications

### Storage Performance Targets

Based on issue requirements and marine navigation needs:

| Chart Type | File Size | Lookup Target | Storage Target |
|------------|-----------|---------------|----------------|
| Harbor (US5WA50M) | ~144 KB | < 100ms | < 50ms |
| Coastal (US3WA01M) | ~625 KB | < 200ms | < 100ms |
| Overview | > 1MB | < 500ms | < 200ms |

### Spatial Query Performance

- **Point queries**: < 10ms
- **Bounds queries**: < 50ms
- **Complex spatial operations**: < 100ms

## Real-World Test Data

### Available Test Charts

Located in `test/fixtures/charts/noaa_enc/`:

#### US5WA50M - Harbor Elliott Bay
- **Size**: 143.9 KB (147,361 bytes)
- **Scale**: ~1:20,000 (harbor detail)
- **Coverage**: Elliott Bay, Seattle Harbor
- **Usage**: Primary performance validation
- **SHA256**: `B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE`

#### US3WA01M - Coastal Puget Sound
- **Size**: 625.3 KB (640,268 bytes)
- **Scale**: ~1:90,000 (coastal overview)
- **Coverage**: Puget Sound region
- **Usage**: Large dataset performance testing

### Test Data Characteristics

- **Coordinate Density**: Real marine navigation complexity
- **Feature Variety**: Mix of navigation aids, bathymetry, coastlines
- **Update Files**: Includes `.001` update corrections
- **Geographic Bounds**: Real Pacific Northwest coordinates

## Storage Workflow

### Chart Storage Process

1. **Input Validation**: Verify chart data integrity
2. **S-57 Parsing**: Extract features and metadata
3. **Compression**: Apply optimal compression algorithm
4. **Database Storage**: Store metadata and binary data
5. **Index Update**: Update spatial and text indexes
6. **Verification**: Confirm storage integrity

```dart
// Example storage workflow
Future<void> storeChart(Chart chart, List<int> data) async {
  // 1. Validate input
  if (data.isEmpty) throw ArgumentError('Chart data cannot be empty');
  
  // 2. Parse for validation (optional)
  final parsedData = S57Parser.parse(data);
  
  // 3. Store in transaction
  await db.transaction((txn) async {
    // Store metadata
    await txn.insert('charts', chart.toMap());
    
    // Store compressed binary data
    final compressedData = await compressionService.compress(data);
    await txn.insert('chart_data', {
      'chart_id': chart.id,
      'data': compressedData.compressedData,
      'compressed': 1,
      'original_size': data.length,
      'stored_at': DateTime.now().millisecondsSinceEpoch,
    });
  });
}
```

### Chart Retrieval Process

1. **Metadata Lookup**: Find chart in database
2. **Binary Retrieval**: Load compressed data
3. **Decompression**: Restore original format
4. **Integrity Check**: Verify data consistency
5. **Return**: Provide chart data to caller

## Version Management

### Chart Updates

The system supports ENC update workflow:

- **Base Charts**: `.000` files (complete chart data)
- **Updates**: `.001`, `.002`, etc. (incremental changes)
- **Version Tracking**: Edition and update numbers
- **Update History**: Track all chart modifications

### Update Processing

```dart
// Chart update workflow
Future<void> updateChart(String chartId, List<int> updateData, int updateNumber) async {
  final existingChart = await loadChart(chartId);
  if (existingChart == null) throw StateError('Base chart not found');
  
  // Apply update and increment version
  final updatedChart = existingChart.copyWith(
    updateNumber: updateNumber,
    lastUpdate: DateTime.now(),
  );
  
  await storeChart(updatedChart, updateData);
}
```

## Storage Optimization

### Compression Strategy

1. **Size-Based Selection**: Larger charts use higher compression
2. **Type-Based Optimization**: Different algorithms for different data types
3. **Performance Balance**: Optimize for lookup speed vs. storage space

### Cache Management

- **Memory Cache**: Frequently accessed charts
- **LRU Eviction**: Remove least recently used charts
- **Preloading**: Cache charts in navigation area
- **Background Cleanup**: Remove expired cache entries

### Database Maintenance

- **Vacuum Operations**: Reclaim unused space
- **Index Optimization**: Rebuild indexes periodically
- **Cleanup Policies**: Remove outdated chart versions

## Testing and Validation

### Performance Test Suite

**Location**: `test/core/services/storage/chart_storage_performance_test.dart`

Tests include:
- Sub-100ms lookup validation with US5WA50M
- Large dataset handling with US3WA01M
- Spatial query performance
- Storage efficiency analysis
- Update workflow validation

### Integration Tests

**Location**: `test/integration/chart_storage_integration_test.dart`

End-to-end testing:
- S-57 parsing integration
- Real coordinate spatial indexing
- Batch processing validation
- Storage cleanup verification

### Storage Analysis Tools

**Location**: `lib/core/services/storage/chart_storage_analyzer.dart`

Provides:
- Storage efficiency analysis
- Performance benchmarking
- Optimization recommendations
- Batch processing reports

## Error Handling and Recovery

### Storage Errors

- **Disk Space**: Monitor available storage
- **Corruption**: Detect and recover from data corruption
- **Concurrency**: Handle concurrent access safely
- **Network Issues**: Graceful handling of download failures

### Recovery Strategies

```dart
// Example error recovery
try {
  final chartData = await storageService.loadChart(chartId);
  return chartData;
} catch (e) {
  logger.warning('Chart load failed, attempting recovery: $e');
  
  // Try alternative approaches
  if (await storageService.chartExists(chartId)) {
    // Attempt database repair
    await storageService.repairChart(chartId);
    return await storageService.loadChart(chartId);
  }
  
  // Fallback to re-download
  return await downloadService.redownloadChart(chartId);
}
```

## Security Considerations

### Data Integrity

- **Checksums**: Verify chart data integrity
- **Validation**: S-57 format validation
- **Encryption**: Optional chart data encryption
- **Access Control**: Restricted chart access

### Safe Operations

- **Transaction Safety**: All updates in database transactions
- **Backup Procedures**: Regular backup of critical chart data
- **Version Control**: Track all chart modifications
- **Audit Logging**: Log all storage operations

## Future Enhancements

### Planned Improvements

1. **Cloud Synchronization**: Backup charts to cloud storage
2. **Differential Updates**: More efficient update mechanisms  
3. **Predictive Caching**: Cache charts based on navigation patterns
4. **Advanced Compression**: Research better compression algorithms
5. **Distributed Storage**: Support for chart distribution across devices

### Research Areas

- **Tile-Based Storage**: Break charts into tiles for partial loading
- **Vector Optimization**: Optimize vector data storage
- **Real-Time Updates**: Live chart update notifications
- **Machine Learning**: Intelligent chart prefetching

## Conclusion

NavTool's chart storage system provides a comprehensive solution for marine navigation chart management. The architecture balances performance, storage efficiency, and reliability while meeting the demanding requirements of real-time marine navigation.

The system's design supports:
- ✅ **Sub-100ms lookups** for harbor-scale charts
- ✅ **Efficient storage** with compression
- ✅ **Spatial indexing** for quick geographic queries
- ✅ **Version management** for chart updates
- ✅ **Real-world validation** with NOAA ENC test data

For implementation details, see the source code and test files referenced throughout this document.