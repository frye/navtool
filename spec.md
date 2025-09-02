# NavTool - NOAA Vector Chart Downloader

## Project Overview

NavTool is a Flutter application that enables users to download vector nautical charts from NOAA's free Electronic Navigational Chart (ENC) sources, organized by U.S. state. The app provides an intuitive interface for discovering, selecting, and downloading NOAA's S-57 format vector charts for offline use in marine navigation and geographic analysis.

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
- **Update Awareness**: Clearly indicate when newer chart versions are available
- **Marine-Standard Display**: Follow IHO chart symbology and marine navigation conventions
- **Touch-Optimized**: Design for marine environment with wet hands and gloves
- **Sunlight Readable**: High contrast modes for bright outdoor conditions

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

### Technical Architecture Summary

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

### Success Metrics
- Chart coverage for all US coastal states and Great Lakes
- State-based discovery completes in <2 seconds
- >99% success rate for chart metadata retrieval
- >90% test coverage for reliability
- Seamless integration with existing chart browsing UI

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
