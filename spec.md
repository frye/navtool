# NavTool - NOAA Vector Chart Downloader

## Project Overview

NavTool is a Flutter application that enables users to download vector nautical charts from NOAA's free Electronic Navigational Chart (ENC) sources, organized by U.S. state. The app provides an intuitive interface for discovering, selecting, and downloading NOAA's S-57 format vector charts for offline use in marine navigation and geographic analysis.

## Current Issue Analysis: Washington State Charts Not Found

### Problem Description
When users run the application and select "Washington" from the state dropdown in the chart browser, they encounter "0 charts found" instead of the expected list of Washington state nautical charts with previews.

### Root Cause Analysis

**Primary Issues Identified:**

1. **Chart Catalog Bootstrap Failure**
   - The `ensureCatalogBootstrapped()` method in `ChartCatalogServiceImpl` is designed to force re-bootstrap even when charts exist
   - This causes the system to repeatedly attempt to fetch from NOAA API, which may be failing
   - Current code comment indicates: "Force re-bootstrap to test new geometry extraction"

2. **NOAA API Network Connectivity Issues**
   - Test logs show intermittent failures: "NoaaApiException: No internet connection available (NETWORK_CONNECTIVITY)"
   - The bootstrap process depends entirely on successful NOAA API calls
   - Failures in API calls result in empty chart catalog

3. **State-to-Chart Mapping Dependencies**
   - Washington state mapping relies on spatial intersection of chart bounds with Washington boundaries
   - The mapping service (`StateRegionMappingServiceImpl`) calls `_computeChartCellsForState()` which queries the database
   - If the database is empty due to bootstrap failures, no charts are found

4. **Cache Invalidation System**
   - Previous issue #129 identified stale cached data with invalid bounds (0,0,0,0)
   - While a cache invalidation system was implemented, the bootstrap process still depends on live API calls

### Technical Flow Analysis

**Expected Flow:**
1. User selects "Washington" from dropdown
2. `ChartBrowserScreen._loadChartsForState()` calls `NoaaChartDiscoveryService.discoverChartsByState()`
3. Discovery service calls `ChartCatalogService.ensureCatalogBootstrapped()`
4. Bootstrap fetches charts from NOAA API and stores them in database
5. `StateRegionMappingService.getChartCellsForState()` queries database for Washington charts
6. Charts are returned and displayed to user

**Actual Flow Issues:**
1. Bootstrap repeatedly attempts API calls (force refresh enabled)
2. API calls fail intermittently due to network issues
3. Database remains empty or partially populated
4. Spatial queries for Washington state return no results
5. User sees "0 charts found"

### Detailed Technical Findings

**From Code Analysis:**

1. **Forced Bootstrap Logic** (`chart_catalog_service.dart:298-308`):
   ```dart
   // Force re-bootstrap to test new geometry extraction
   // TODO: Remove this force refresh after verifying geometry extraction works
   if (chartCount > 0) {
     _logger.info(
       'Force refreshing chart catalog to test geometry extraction (chartCount: $chartCount)',
     );
   }
   ```

2. **Network Failure Pattern** (from test logs):
   - Frequent "No internet connection available" errors
   - Successful calls mixed with failures
   - Bootstrap process fails when API calls fail

3. **State Mapping Logic** (`state_region_mapping_service.dart:145-185`):
   - Uses spatial intersection with predefined Washington bounds: `north: 49.0, south: 45.5, east: -116.9, west: -124.8`
   - Queries database: `await _storageService.getChartsInBounds(stateBounds)`
   - Returns empty list if database has no charts for Washington area

4. **Database Query Logic** (`database_storage_service.dart:669-683`):
   ```sql
   SELECT * FROM charts 
   WHERE bounds_south <= ? AND bounds_north >= ? AND 
         bounds_west <= ? AND bounds_east >= ?
   ```
   - Correct spatial intersection logic
   - Returns empty if no charts in database match Washington bounds

## Background Research

NOAA provides free Electronic Navigational Charts (ENCs) in the international S-57 vector format. These charts are organized by geographic regions rather than states, covering U.S. coastal waters, Great Lakes, and inland waterways. The charts are available through several access methods:

- **Bulk Downloads**: Regional ZIP archives from NOAA's ENC download page
- **Individual Charts**: Single ENC cells via the Chart Locator
- **GIS Services**: ENC Direct to GIS for web mapping and programmatic access

### Technical Specifications
- **Format**: S-57 Edition 3.1 (IHO standard)
- **File Extension**: .000 files (compressed in ZIP archives)
- **Organization**: Chart "cells" covering specific geographic areas
- **Scale Bands**: Harbor, Approach, Coastal, General, Overview
- **Update Frequency**: Daily updates during weekdays

## Core Functionality

### 1. State-Based Chart Discovery
- Browse charts by U.S. state selection
- Display chart coverage areas overlaid on state boundaries
- Show available chart scales and types for each region
- Filter charts by chart type (harbor, coastal, etc.)

### 2. Chart Selection and Preview
- Interactive map showing chart boundaries
- Chart metadata display (scale, last update, coverage area)
- Multi-select capability for batch downloads
- Preview chart information before download

### 3. Download Management
- Queue multiple charts for download
- Progress tracking for individual and batch downloads
- Resume interrupted downloads
- Verify chart integrity after download

### 4. Chart Display and Navigation
- Real-time chart rendering from S-57 vector data
- GPS integration for current vessel position display
- Interactive chart navigation (pan, zoom, rotate)
- Chart layering and symbol rendering according to IHO standards
- Automatic chart switching based on scale and location
- Day/night color schemes for marine use

### 5. Vessel Tracking and Navigation
- Real-time GPS position overlay on charts
- Vessel heading and course over ground display
- Track recording with breadcrumb trail
- Speed and navigation data display
- Waypoint creation and navigation
- Anchor watch functionality

### 6. Local Chart Management
- Organize downloaded charts by state/region
- View chart metadata and update status
- Delete outdated or unwanted charts
- Check for chart updates

## User Experience Goals

### Primary User Stories
1. **As a recreational boater**, I want to download all coastal charts for my home state so I can use them offline during trips
2. **As a marine professional**, I want to quickly find and download the latest harbor charts for specific ports
3. **As a GIS analyst**, I want to bulk download regional chart data for spatial analysis projects
4. **As a boat captain**, I want to see my vessel's position on the chart in real-time, just like a commercial chart plotter
5. **As a sailor**, I want to track my route and create waypoints for navigation planning
6. **As a fishing boat operator**, I want to use the app as my primary navigation tool with proper marine chart symbology

### Key UX Principles
- **Simple State Selection**: Start with familiar state boundaries rather than complex regional groupings
- **Visual Chart Coverage**: Show exactly what water areas each chart covers
- **Offline-First**: Assume users will primarily use charts without internet connection
- **User-Controlled Updates**: Let users decide when to refresh chart data based on connectivity
- **Marine-Standard Display**: Follow IHO chart symbology and marine navigation conventions
- **Touch-Optimized**: Design for marine environment with wet hands and gloves
- **Sunlight Readable**: High contrast modes for bright outdoor conditions
- **Connectivity Awareness**: Clear indicators of cached vs. fresh data without forcing updates

### Contributing Factors

**Environmental Issues:**
- Intermittent network connectivity in marine/development environments
- NOAA API rate limiting or temporary service unavailability
- DNS resolution issues for NOAA endpoints

**Data Availability Issues:**
- NOAA test dataset limitations (only 15-18 charts total according to diagnostic tests)
- Limited Washington state coverage in test data
- Production vs. test endpoint configuration issues

**Caching Strategy Issues:**
- Force bootstrap strategy prevents using cached data
- No fallback mechanism when API calls fail
- Cache invalidation may be too aggressive

### Solution Plan

**Phase 1: Immediate Fixes (High Priority)**

1. **Remove Automatic Bootstrap** 
   - Disable forced re-bootstrap logic in `ensureCatalogBootstrapped()`
   - Allow system to use existing cached charts indefinitely
   - Remove automatic API calls that depend on network connectivity

2. **Add Manual Refresh Button**
   - Add "Refresh Chart Catalog" button in chart browser UI
   - User controls when to attempt NOAA API calls
   - Show loading state and progress during manual refresh
   - Graceful error handling with clear user messaging

3. **Add Test Data Seeding with Existing Elliott Bay Charts**
   - Use existing test charts: `US5WA50M_harbor_elliott_bay.zip` and `US3WA01M_coastal_puget_sound.zip`
   - Seed database with actual NOAA ENC test data from `test/fixtures/charts/noaa_enc/`
   - Ensure Elliott Bay charts (US5WA50M and US3WA01M) are available immediately without requiring network
   - Provide offline-first experience for marine environment using real chart data

**Phase 2: Network Resilience (Medium Priority)**

1. **Enhanced Error Handling**
   - Better network failure detection and reporting
   - User-friendly error messages when charts unavailable
   - Network status monitoring and retry mechanisms

2. **Progressive Loading Strategy**
   - Load charts incrementally as network allows
   - Show partial results while loading continues
   - Cache successful API responses aggressively

3. **Offline-First Architecture**
   - Pre-populate with essential chart data
   - Background sync when network available
   - Local database as primary source of truth

**Phase 3: Data Quality & Coverage (Lower Priority)**

1. **Production API Integration**
   - Verify production NOAA endpoints provide full coverage
   - Implement proper API authentication if required
   - Add data validation and quality checks

2. **Enhanced State Mapping**
   - Improve spatial intersection algorithms
   - Add support for chart overlaps and boundaries
   - Better handling of edge cases and chart gaps

### Immediate Action Items

1. **Remove Automatic Bootstrap** - Disable forced API refresh
2. **Add Manual Refresh Button** - User-controlled chart updates
3. **Seed Elliott Bay Test Data** - Use existing US5WA50M and US3WA01M charts from test fixtures
4. **Update UI/UX** - Clear refresh status and offline indicators showing Elliott Bay chart availability

## Implementation Progress

### Completed Research and Architecture (August 2025)

**Phase 2.1 - NOAA Chart Integration Research and Design**
- ✅ **Issue #83**: NOAA ENC Data Sources and API Research - Comprehensive analysis of NOAA's distribution methods, API endpoints, and metadata formats
- ✅ **Issue #84**: NOAA Integration Architecture Design - Complete service architecture design for Flutter integration with Riverpod dependency injection

**Key Research Findings:**
- NOAA provides free Electronic Navigational Charts via GeoJSON catalog API
- No authentication required for public domain chart data
- Rate limiting recommended: 5 requests/second to prevent server overload
- Charts organized by geographic cells with Usage bands (Harbor/Approach/Coastal/General/Overview)
- State-to-region mapping requires spatial intersection between US state boundaries and chart coverage polygons

## Research Updates (August 27, 2025)

### Chart Service Discovery Research

**Comprehensive Analysis Completed:**
- **OpenCPN Integration Patterns**: Analyzed the Chart Downloader plugin architecture and NOAA catalog format usage
- **NOAA Vector Chart APIs**: Researched official ENC distribution methods, catalog APIs, and coordinate-based discovery
- **Spatial Query Algorithms**: Identified proven approaches for chart boundary intersection and selection

**Key Research Findings:**

1. **NOAA ENC Catalog API Structure**:
   - GeoJSON format with polygon coverage areas for each chart
   - Daily updates with edition dates and metadata
   - Public domain access with no authentication required
   - Rate limiting recommended at 5 requests/second

2. **Chart Selection Algorithm**:
   - Point-in-polygon spatial intersection for coordinate-based discovery
   - Priority ranking by usage band (Harbor > Approach > Coastal > General > Overview)
   - Distance-based relevance scoring for chart recommendations
   - Multi-scale chart availability for comprehensive coverage

3. **Download Management Strategy**:
   - S-57 ENC files distributed in ZIP archives from official NOAA endpoints
   - Queue-based download system with progress tracking and error recovery
   - Integrity verification using checksums and format validation
   - Incremental updates with delta download capability

**Technical Implementation Plan:**
- Spatial query engine using R-tree indexing for performance
- Multi-level caching (memory, SQLite, filesystem) for offline reliability
- Riverpod-based service architecture for dependency injection
- Comprehensive error handling with exponential backoff retry logic

*Detailed specifications documented in `chartservice-spec.md`*

---

**Phase 2.1.3 - Implementation Sub-Issues (In Progress)**
- **Issue #85**: NOAA Chart Discovery and Metadata Implementation (Parent Issue)
  - **Issue #86**: Core NOAA Service Implementation (3-4 days)
  - **Issue #87**: NOAA API Client and Network Integration (2-3 days) 
  - **Issue #88**: NOAA Metadata Parsing Pipeline (2-3 days)
  - **Issue #89**: State-Region Geographic Mapping Service (4-5 days)
  - **Issue #90**: Database Schema and Storage Implementation (2-3 days)
  - **Issue #91**: Comprehensive Testing and Validation (3-4 days)

**Estimated Timeline**: 16-22 days (3-4 weeks) for complete NOAA integration

### Washington Charts Issue - Comprehensive Analysis

### Debug Evidence Summary

**From Codebase Analysis:**

1. **Bootstrap Process Issues:**
   - `ChartCatalogServiceImpl.ensureCatalogBootstrapped()` forces re-bootstrap even with existing charts
   - Comment indicates this is temporary for "geometry extraction testing"
   - Process depends entirely on successful NOAA API calls

2. **Network Failure Patterns:**
   - Test logs show: "NoaaApiException: No internet connection available (NETWORK_CONNECTIVITY)"
   - Mixed success/failure pattern suggests intermittent connectivity
   - No fallback strategy when API calls fail

3. **Data Flow Dependencies:**
   ```
   User selects Washington
   ↓
   NoaaChartDiscoveryService.discoverChartsByState("Washington")
   ↓
   ChartCatalogService.ensureCatalogBootstrapped() [FAILS HERE]
   ↓
   StateRegionMappingService.getChartCellsForState("Washington")
   ↓
   StorageService.getChartsInBounds(washingtonBounds) [RETURNS EMPTY]
   ↓
   User sees "0 charts found"
   ```

4. **Database State:**
   - Spatial query logic is correct (verified in Issue #129 solution)
   - Washington bounds are accurate: `north: 49.0, south: 45.5, east: -116.9, west: -124.8`
   - Problem is empty/incomplete database due to bootstrap failures

**Evidence from Issue #129 Solution:**
- Cache invalidation system was implemented and tested
- Spatial intersection queries work correctly when database has data
- Test with synthetic Washington charts returned expected results
- Issue is data availability, not technical implementation

### Root Cause Conclusion

The "0 charts found for Washington" issue is **NOT** a spatial query bug or coordinate system problem. It is a **data availability issue** caused by:

1. **Primary Cause:** Forced bootstrap process failing due to network issues
2. **Secondary Cause:** No fallback mechanism when NOAA API unavailable
3. **Tertiary Cause:** Potentially limited Washington chart coverage in NOAA test dataset

### Solution Implementation Priority

**CRITICAL (Fix Immediately):**
- [ ] Disable forced bootstrap in `ChartCatalogServiceImpl.ensureCatalogBootstrapped()`
- [ ] Add network failure fallback in bootstrap process
- [ ] Seed database with Washington test chart data

**HIGH (Next Release):**
- [ ] Implement progressive chart loading with retry logic
- [ ] Add user-friendly error messaging for network issues
- [ ] Create offline-first chart discovery strategy

**MEDIUM (Future Enhancement):**
- [ ] Verify production NOAA API provides full Washington coverage
- [ ] Add background sync for chart catalog updates
- [ ] Implement chart coverage monitoring and alerts

## Technical Architecture Summary

**Service Layer Design:**
```dart
NoaaChartDiscoveryService -> ChartCatalogService + StateRegionMappingService
NoaaApiClient -> HTTP client with rate limiting and retry logic
NoaaMetadataParser -> GeoJSON to Chart model transformation
```

**Key Features:**
- Riverpod dependency injection for service management
- Multi-level caching for performance optimization
- Spatial intersection for state-based chart discovery
- Rate limiting to respect NOAA server constraints
- Offline-first design for marine environment reliability
- Comprehensive error handling for network and parsing failures

**Current Architecture Issues:**
- Bootstrap process too dependent on live API calls
- No graceful degradation when network unavailable
- Cache invalidation may be too aggressive for marine environments
- User experience degrades completely when API fails

### Success Metrics
- Chart coverage for all US coastal states and Great Lakes
- State-based discovery completes in <2 seconds
- >99% success rate for chart metadata retrieval
- >90% test coverage for reliability
- Seamless integration with existing chart browsing UI

### Washington Charts Issue - Action Plan

**Immediate Actions Required:**

1. **Remove Automatic Bootstrap** (`lib/core/services/noaa/chart_catalog_service.dart:298-308`)
   ```dart
   // REMOVE this forced refresh logic entirely:
   // if (chartCount > 0) {
   //   _logger.info('Force refreshing chart catalog...');
   // }
   
   // REPLACE with simple cache check:
   if (chartCount > 0) {
     _logger.info('Using cached chart catalog with ${chartCount} charts');
     return; // Always use existing cache
   }
   ```

2. **Add Manual Refresh Button** (`lib/features/charts/chart_browser_screen.dart`)
   ```dart
   // Add refresh button to app bar
   AppBar(
     title: Text('Chart Browser'),
     actions: [
       IconButton(
         icon: Icon(Icons.refresh),
         onPressed: _refreshChartCatalog,
         tooltip: 'Refresh Chart Catalog',
       ),
     ],
   )
   
   // User-controlled refresh method
   Future<void> _refreshChartCatalog() async {
     setState(() => _isRefreshing = true);
     try {
       await ref.read(chartCatalogServiceProvider).refreshCatalog(force: true);
       // Show success message
     } catch (e) {
       // Show network error, continue using cached data
     }
     setState(() => _isRefreshing = false);
   }
   ```

3. **Seed Test Data for Offline Use**
   - Create `lib/core/fixtures/washington_charts.dart` with realistic test data
   - Populate database on first app launch with representative charts
   - Ensure Washington state shows charts immediately without network

4. **Update User Experience with Elliott Bay Charts Toggle**
   - Add UI toggle to always include Elliott Bay test charts (US5WA50M, US3WA01M)
   - Toggle works independently - even when live NOAA data is available
   - Combine live and test charts with deduplication (live charts take precedence)
   - Show visual indicator when test charts are included
   - Display last refresh timestamp
   - Clear messaging about manual refresh capability
   - Loading states only during user-initiated refresh

**Testing Strategy:**
- Test with network disconnected to verify fallback
- Verify Washington state shows charts in offline mode  
- Test bootstrap recovery after network restoration
- Validate spatial queries with seeded test data

**Expected Outcome:**
Users selecting Washington state will have a toggle option to include Elliott Bay test charts (US5WA50M harbor-scale and US3WA01M coastal-scale) alongside any live NOAA data. The toggle is enabled by default and works independently of network connectivity. When enabled, users see both test charts and live charts combined (with live charts taking precedence for duplicate IDs). Users can manually refresh the chart catalog when they have good connectivity, and the app remains fully functional offline with the existing Elliott Bay test data. This provides a reliable marine navigation experience that works in all connectivity conditions, using real NOAA ENC chart files from the test fixtures, while also allowing access to the most current live data when available.

## Current Chart Rendering Issue Analysis (December 2024)

### Problem Description
After successfully implementing Issue #183 (Elliott Bay test charts integration), users report that selected Elliott Bay charts (US5WA50M and US3WA01M) display only "weird symbol" in the center instead of proper maritime features like contours, depth areas, and navigation aids.

### Technical Root Cause Analysis

**Chart Data Pipeline Investigation:**

1. **S-57 Parser Status**: ✅ **WORKING CORRECTLY**
   - Elliott Bay test charts (US5WA50M.000, US3WA01M.000) parse successfully
   - Extracts proper maritime features: DEPARE (depth areas), SOUNDG (soundings), COALNE (coastlines)
   - Synthetic test features are properly generated with correct geometries and attributes
   - Feature types correctly identified: `S57FeatureType.depthArea`, `S57FeatureType.sounding`, etc.

2. **Feature Data Conversion**: ❓ **POTENTIAL GAP**
   - S57Features contain proper attributes (DRVAL1/DRVAL2 for depths, VALSOU for soundings)
   - Coordinates are correctly transformed using COMF/SOMF scaling factors
   - Features have valid `S57GeometryType` (point, line, area) and geographic bounds

3. **Chart Rendering Service**: ❌ **RENDERING DISCONNECT**
   - `ChartRenderingService` expects `MaritimeFeature` objects (PointFeature, LineFeature, AreaFeature)
   - S57Parser produces `S57Feature` objects with different data structure
   - **MISSING ADAPTER**: No conversion layer between S57Feature → MaritimeFeature
   - CustomPainter receives wrong feature types and displays fallback symbols

4. **Visual Rendering Pipeline**: ✅ **ARCHITECTURE EXISTS**
   - `ChartWidget` → `_ChartPainter` → `ChartRenderingService.render()` pipeline is complete
   - S-52 symbology system exists with `S52SymbolManager` and color tables
   - Canvas rendering for maritime features (depths, contours, aids) is implemented
   - Fallback symbol rendering explains "weird symbol" - it's the generic point symbol

### Specific Technical Findings

**Data Structure Mismatch:**
```dart
// S57Parser produces:
S57Feature {
  recordId: 12345,
  featureType: S57FeatureType.depthArea,
  geometryType: S57GeometryType.area,
  coordinates: [S57Coordinate(lat: 47.65, lng: -122.35), ...],
  attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
  label: 'Depth Area 10-20m'
}

// ChartRenderingService expects:
AreaFeature {
  id: 'depth_area_123',
  type: MaritimeFeatureType.depthArea,
  position: LatLng(47.65, -122.35),
  coordinates: [[LatLng(...), LatLng(...)]],
  fillColor: Colors.blue,
  attributes: {'depth_min': 10.0, 'depth_max': 20.0}
}
```

**Chart Display Pipeline Gaps:**
1. **Missing Feature Adapter**: No `S57Feature` → `MaritimeFeature` conversion
2. **Missing Chart Data Provider**: Charts load as `S57ParsedData` but rendering expects `List<MaritimeFeature>`
3. **Missing S-52 Integration**: S57Features don't connect to S52SymbolManager
4. **Missing Chart Loading**: Elliott Bay charts are cataloged but not loaded into chart viewer

### Solution Implementation Plan

**CRITICAL FIX - Chart Rendering Pipeline Integration**

**Phase 1: Feature Adapter Implementation**
```dart
// Create: lib/core/adapters/s57_to_maritime_adapter.dart
class S57ToMaritimeAdapter {
  static List<MaritimeFeature> convertFeatures(List<S57Feature> s57Features) {
    return s57Features.map((s57) => _convertFeature(s57)).whereType<MaritimeFeature>().toList();
  }
  
  static MaritimeFeature? _convertFeature(S57Feature s57) {
    switch (s57.featureType) {
      case S57FeatureType.depthArea:
        return _convertDepthArea(s57);
      case S57FeatureType.sounding:
        return _convertSounding(s57);
      case S57FeatureType.coastline:
        return _convertCoastline(s57);
      // ... handle all maritime feature types
    }
  }
}
```

**Phase 2: Chart Data Integration**
```dart
// Update: lib/features/charts/chart_screen.dart
class ChartScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(selectedChartProvider).when(
      data: (chartData) {
        // Parse S-57 chart data
        final s57Data = S57Parser.parse(chartData.rawBytes);
        
        // Convert to maritime features
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
        
        // Display with chart widget
        return ChartWidget(
          features: maritimeFeatures,
          bounds: _convertBounds(s57Data.bounds),
        );
      },
    );
  }
}
```

**Phase 3: Elliott Bay Chart Loading**
```dart
// Update: Chart selection to load actual chart files
Future<void> loadChart(ChartMetadata chart) async {
  if (chart.id == 'US5WA50M' || chart.id == 'US3WA01M') {
    // Load from test fixtures
    final chartFile = File('test/fixtures/charts/noaa_enc/${chart.id}.000');
    final chartData = await chartFile.readAsBytes();
    
    // Set as current chart for rendering
    ref.read(selectedChartProvider.notifier).loadChart(chartData);
  }
}
```

**Phase 4: S-52 Symbology Integration**
```dart
// Enhance: ChartRenderingService with S-52 compliance
class ChartRenderingService {
  void _renderDepthArea(Canvas canvas, AreaFeature depthArea) {
    // Use S-52 colors and patterns for depth areas
    final s52Color = _s52SymbolManager.getDepthAreaColor(
      minDepth: depthArea.attributes['depth_min'],
      maxDepth: depthArea.attributes['depth_max'],
    );
    
    // Render with proper marine symbology
    final paint = Paint()..color = s52Color;
    canvas.drawPath(_createAreaPath(depthArea.coordinates), paint);
  }
}
```

### Implementation Priority

**IMMEDIATE (Fix Chart Display)**
1. **Feature Adapter** - Convert S57Features to MaritimeFeatures 
2. **Chart Loading** - Load Elliott Bay chart files into chart viewer
3. **Basic Rendering** - Display depth areas, soundings, coastlines correctly

**HIGH (Complete Maritime Features)**  
1. **Full Feature Support** - All S-57 feature types (DEPARE, SOUNDG, COALNE, BOYLAT, etc.)
2. **S-52 Colors** - Proper maritime color schemes for depth areas and symbols
3. **Chart Bounds** - Correct viewport and coordinate transformation

**MEDIUM (Enhanced Experience)**
1. **Symbol Rendering** - Navigation aids, buoys, beacons with proper symbols  
2. **Chart Labels** - Depth values, feature names, navigation info
3. **Layer Management** - Toggle depth contours, navigation aids, etc.

### Expected Resolution
After implementing the feature adapter and chart loading pipeline, Elliott Bay charts will display:
- **Depth Areas (DEPARE)**: Blue-shaded polygons with proper depth ranges (10-20m, etc.)
- **Soundings (SOUNDG)**: Individual depth measurements as numbers on chart
- **Coastlines (COALNE)**: Shore boundaries and land areas
- **Navigation Aids**: Any buoys or beacons in Elliott Bay area
- **Proper Chart Bounds**: Centered on Elliott Bay coordinates (47.6062°N, 122.3321°W)

The "weird symbol" will be replaced with full maritime chart display showing Elliott Bay's harbor features, depth contours, and navigation information exactly as they appear in professional chart plotters.

## Technical Architecture

### Data Sources
- **NOAA ENC Catalog API** (GeoJSON format) for chart discovery
- **NOAA Chart Display Service** (Esri REST/OGC WMS) for preview
- **Official NOAA ENC Downloads** (S-57 format in ZIP archives)
- State boundary data for geographic mapping

### Core Components
- **Coordinate-based chart discovery service** using spatial intersection algorithms
- **NOAA API client** with rate limiting and retry logic
- **Chart selection engine** with intelligent recommendations
- **Download queue manager** with progress tracking and error recovery
- **S-57 chart rendering engine** with S-52 symbology compliance
- **GPS integration** and real-time position tracking
- **Interactive chart viewer** with navigation controls
- **Local storage and metadata caching** (SQLite + file system)
- **Automatic update checking** service with daily NOAA catalog refresh

### Chart Service Architecture
*Based on research findings documented in `chartservice-spec.md`*

```
GPS Location → Chart Discovery Service → NOAA Catalog API
                     ↓
Spatial Query Engine → Chart Selection Algorithm → User Recommendations
                     ↓
Download Queue Service → NOAA Download API → Local Chart Storage
```

**Key Technical Decisions:**
- **OpenCPN Pattern Adoption**: Leveraging proven chart catalog format and spatial algorithms
- **NOAA Official APIs**: Using public domain ENC data with no authentication required
- **Intelligent Selection**: Automatic chart prioritization based on scale, distance, and usage band
- **Offline-First Design**: Complete functionality without internet after initial download

### Platform Considerations
- Flutter for cross-platform mobile/desktop support
- Local SQLite database for chart metadata and spatial indexing
- **HTTP client with rate limiting** (5 requests/second recommended for NOAA APIs)
- **Spatial algorithms for coordinate-based chart discovery**
- File system access for chart storage with integrity verification
- Background download capabilities with queue management
- **High-performance graphics rendering** (OpenGL/Metal integration)
- **GPS and location services integration**
- **IHO S-52 Presentation Library** for standard chart symbology
- **Multi-level caching strategy** (memory, database, filesystem)

## Chart Rendering Technical Requirements

### S-57 Data Processing
- **S-57 Parser**: Parse NOAA ENC files according to IHO S-57 Edition 3.1 standard
- **SENC Generation**: Convert S-57 data to System Electronic Navigational Chart format for optimized rendering
- **Feature Extraction**: Parse geometric and attribute data for maritime features (depths, buoys, obstacles, etc.)
- **Spatial Indexing**: Implement efficient spatial queries for real-time chart display

### Chart Display Standards
- **IHO S-52 Compliance**: Implement standardized symbology according to S-52 Presentation Library
- **Symbol Rendering**: Display maritime symbols, colors, and patterns per international standards
- **Scale-Dependent Display**: Automatically show/hide features based on zoom level and chart scale
- **Color Schemes**: Support day/night color palettes optimized for marine conditions

### Navigation Features
- **Real-Time Position**: GPS integration with vessel position overlay
- **Course and Heading**: Display vessel track, heading, and course over ground
- **Chart Interaction**: Touch-based pan, zoom, and rotation controls
- **Automatic Chart Selection**: Switch between chart scales based on zoom level and location
- **Waypoint Management**: Create, edit, and navigate to waypoints
- **Track Recording**: Record and display vessel tracks over time

### Performance Considerations
- **Offline Rendering**: All chart display must work without internet connection
- **Memory Management**: Efficient loading/unloading of chart data based on viewport
- **Battery Optimization**: Minimize GPS and rendering power consumption
- **Touch Response**: Maintain smooth interaction even with complex chart data
