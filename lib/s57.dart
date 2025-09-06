/// S-57 Electronic Navigational Chart (ENC) Parser
/// 
/// Provides parsing and analysis capabilities for S-57 format Electronic 
/// Navigational Charts as specified in IHO S-57 Edition 3.1.
///
/// Key features:
/// - Parse S-57 binary files (.000 base files and .001+ updates)
/// - Extract navigation features (soundings, depth areas, aids to navigation)
/// - Spatial querying with R-tree indexing
/// - GeoJSON export capabilities
/// - Comprehensive warning and error handling
library s57;

// Core parsing functionality
export 'core/services/s57/s57_parser.dart';
export 'core/services/s57/s57_models.dart';

// Parse configuration and warnings
export 'core/services/s57/s57_parse_warnings.dart';
export 'core/services/s57/s57_warning_collector.dart';

// Spatial indexing
export 'core/services/s57/s57_spatial_index.dart';

// Object catalog and backward compatibility
export 'core/services/s57/s57_object_catalog.dart';
export 'core/services/s57/s57_backward_compatibility.dart';

// Update processing
export 'core/services/s57/s57_update_processor.dart';
export 'core/services/s57/s57_update_models.dart';