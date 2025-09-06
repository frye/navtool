/// S-57 Update Processor
/// 
/// Processes sequential S-57 update files (.001, .002, etc.) applying 
/// RUIN (Insert/Delete/Modify) operations to a base ENC dataset

import 'dart:io';
import 'dart:typed_data';
import 'package:meta/meta.dart';

import 's57_models.dart';
import 's57_parser.dart';
import 's57_update_models.dart';
import 's57_spatial_index.dart';
import '../../error/app_error.dart';

/// Processor for sequential S-57 update files
class S57UpdateProcessor {
  final FeatureStore _featureStore = FeatureStore();
  final UpdateSummary _summary = UpdateSummary();

  /// Get current feature store
  FeatureStore get featureStore => _featureStore;

  /// Get current update summary
  UpdateSummary get summary => _summary;

  /// Initialize feature store from base ENC data (.000)
  void initializeFromBase(S57ParsedData baseData) {
    _featureStore.clear();
    _summary.reset();

    // Add all base features to store with initial version
    final baseRver = _extractBaseRver(baseData.metadata);
    for (final feature in baseData.features) {
      final foid = _generateFoidForFeature(feature);
      final versionedFeature = FeatureVersioned(
        feature: feature,
        version: baseRver,
      );
      _featureStore.put(foid, versionedFeature);
    }

    _summary.finalRver = baseRver;
  }

  /// Apply sequential update files to the feature store
  Future<UpdateSummary> applySequentialUpdates(
    String baseCellName,
    List<File> updateFiles,
  ) async {
    // Discover and sort update files
    final sortedUpdates = _discoverAndSortUpdates(updateFiles);

    // Validate sequence integrity
    _validateUpdateSequence(sortedUpdates, baseCellName);

    // Apply each update in sequence
    for (final updateFile in sortedUpdates) {
      try {
        final updateDataset = await _parseUpdateFile(updateFile);
        _applyUpdate(updateDataset);
        _summary.applied.add(updateDataset.name);
        _summary.finalRver = updateDataset.rver;
      } catch (e) {
        _summary.addWarning('Failed to apply update ${updateFile.path}: $e');
        throw AppError(
          message: 'Update sequence failed at ${updateFile.path}',
          type: AppErrorType.parsing,
          originalError: e,
        );
      }
    }

    return _summary;
  }

  /// Apply a single update to the feature store
  void _applyUpdate(UpdateDataset update) {
    for (final record in update.records) {
      try {
        _applyRuinRecord(record, update.rver);
      } catch (e) {
        _summary.addWarning('Failed to apply RUIN record ${record.foid}: $e');
        // Continue processing other records
      }
    }
  }

  /// Apply a single RUIN record
  @visibleForTesting
  void applyRuinRecord(RuinRecord record, int updateRver) => _applyRuinRecord(record, updateRver);
  
  void _applyRuinRecord(RuinRecord record, int updateRver) {
    switch (record.operation) {
      case RuinOperation.insert:
        _handleInsert(record, updateRver);
        break;
      case RuinOperation.delete:
        _handleDelete(record);
        break;
      case RuinOperation.modify:
        _handleModify(record, updateRver);
        break;
    }
  }

  /// Handle Insert operation
  void _handleInsert(RuinRecord record, int updateRver) {
    if (_featureStore.contains(record.foid)) {
      _summary.addWarning('INSERT_EXISTS: Feature ${record.foid} already exists');
      return;
    }

    if (record.feature == null) {
      _summary.addWarning('INSERT_MISSING_FEATURE: No feature data for insert ${record.foid}');
      return;
    }

    final versionedFeature = FeatureVersioned(
      feature: record.feature!,
      version: updateRver,
    );

    if (_featureStore.insert(record.foid, versionedFeature)) {
      _summary.inserted++;
    } else {
      _summary.addWarning('INSERT_FAILED: Could not insert feature ${record.foid}');
    }
  }

  /// Handle Delete operation
  void _handleDelete(RuinRecord record) {
    if (!_featureStore.remove(record.foid)) {
      _summary.addWarning('DELETE_MISSING: Feature ${record.foid} not found for deletion');
    } else {
      _summary.deleted++;
    }
  }

  /// Handle Modify operation
  void _handleModify(RuinRecord record, int updateRver) {
    final existingVersioned = _featureStore.get(record.foid);
    if (existingVersioned == null) {
      _summary.addWarning('MODIFY_MISSING: Feature ${record.foid} not found for modification');
      return;
    }

    if (record.feature == null) {
      _summary.addWarning('MODIFY_MISSING_FEATURE: No feature data for modify ${record.foid}');
      return;
    }

    // Merge attributes (only replace provided keys, keep others intact)
    final mergedAttributes = <String, dynamic>{
      ...existingVersioned.feature.attributes,
      ...record.feature!.attributes,
    };

    // Use new geometry if provided, otherwise keep existing
    final coordinates = record.feature!.coordinates.isNotEmpty 
        ? record.feature!.coordinates 
        : existingVersioned.feature.coordinates;

    // Create updated feature
    final updatedFeature = S57Feature(
      recordId: existingVersioned.feature.recordId,
      featureType: record.feature!.featureType != S57FeatureType.unknown 
          ? record.feature!.featureType 
          : existingVersioned.feature.featureType,
      geometryType: record.feature!.geometryType,
      coordinates: coordinates,
      attributes: mergedAttributes,
      label: record.feature!.label ?? existingVersioned.feature.label,
    );

    final updatedVersioned = FeatureVersioned(
      feature: updatedFeature,
      version: updateRver,
    );

    _featureStore.put(record.foid, updatedVersioned);
    _summary.modified++;
  }

  /// Discover and sort update files by sequence number
  List<File> _discoverAndSortUpdates(List<File> updateFiles) {
    // Filter for update files (pattern: *.001, *.002, etc.)
    final updates = updateFiles.where((file) {
      final name = file.path.split('/').last;
      final parts = name.split('.');
      if (parts.length >= 2) {
        final extension = parts.last;
        try {
          final seqNum = int.parse(extension);
          return seqNum > 0 && seqNum < 1000; // Reasonable range for update sequences
        } catch (e) {
          return false;
        }
      }
      return false;
    }).toList();

    // Sort by sequence number
    updates.sort((a, b) {
      final aSeq = _getSequenceNumber(a);
      final bSeq = _getSequenceNumber(b);
      return aSeq.compareTo(bSeq);
    });

    return updates;
  }

  /// Get sequence number from update file
  int _getSequenceNumber(File file) {
    final name = file.path.split('/').last;
    final parts = name.split('.');
    if (parts.length >= 2) {
      try {
        return int.parse(parts.last);
      } catch (e) {
        return 0;
      }
    }
    return 0;
  }

  /// Validate update sequence for gaps and base cell match
  void _validateUpdateSequence(List<File> sortedUpdates, String expectedBaseCellName) {
    if (sortedUpdates.isEmpty) return;

    // Check for gaps in sequence
    int expectedSeq = 1;
    for (final file in sortedUpdates) {
      final actualSeq = _getSequenceNumber(file);
      if (actualSeq != expectedSeq) {
        throw AppError(
          message: 'Gap in update sequence: expected .${expectedSeq.toString().padLeft(3, '0')} but found .${actualSeq.toString().padLeft(3, '0')}',
          type: AppErrorType.validation,
        );
      }
      expectedSeq++;
    }

    // TODO: Validate base cell name match (requires parsing DSID from each update)
    // This would require reading each file to check DSID field matches expectedBaseCellName
  }

  /// Parse update file to extract RUIN records
  Future<UpdateDataset> _parseUpdateFile(File updateFile) async {
    final data = await updateFile.readAsBytes();
    final filename = updateFile.path.split('/').last;

    try {
      // Parse using existing S57Parser
      final parsedData = S57Parser.parse(data);
      
      // Extract RUIN records from parsed data
      final ruinRecords = <RuinRecord>[];
      int fileRver = 1; // Default RVER
      String? baseCellName;

      // TODO: Extract RUIN records from parsed records
      // This is a simplified implementation - in reality would need to parse 
      // ISO 8211 records with FRID containing RUIN field
      for (final feature in parsedData.features) {
        // For now, create synthetic RUIN records for testing
        final foid = _generateFoidForFeature(feature);
        final record = RuinRecord(
          foid: foid,
          operation: RuinOperation.insert, // Default to insert for parsed features
          feature: feature,
          rawData: feature.attributes,
        );
        ruinRecords.add(record);
      }

      return UpdateDataset(
        name: filename,
        rver: fileRver,
        baseCellName: baseCellName,
        records: ruinRecords,
      );
    } catch (e) {
      throw AppError(
        message: 'Failed to parse update file $filename',
        type: AppErrorType.parsing,
        originalError: e,
      );
    }
  }

  /// Extract base RVER from metadata
  int _extractBaseRver(S57ChartMetadata metadata) {
    // For now, return default base version
    // In real implementation, would extract from DSID record
    return 0;
  }

  /// Generate FOID for a feature
  String _generateFoidForFeature(S57Feature feature) {
    // Use record ID as simple FOID for now
    // In real implementation, would use proper AGEN_FIDN_FIDS format
    return feature.recordId.toString();
  }

  /// Get all current features as S57ParsedData
  S57ParsedData getCurrentState() {
    final features = _featureStore.allFeatures.map((vf) => vf.feature).toList();
    
    if (features.isEmpty) {
      return S57ParsedData(
        metadata: S57ChartMetadata(producer: 'NavTool', version: '1.0'),
        features: [],
        bounds: const S57Bounds(north: 0, south: 0, east: 0, west: 0),
        spatialIndex: S57SpatialIndex(),
      );
    }

    // Calculate bounds from features
    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;

    for (final feature in features) {
      for (final coord in feature.coordinates) {
        minLat = minLat < coord.latitude ? minLat : coord.latitude;
        maxLat = maxLat > coord.latitude ? maxLat : coord.latitude;
        minLon = minLon < coord.longitude ? minLon : coord.longitude;
        maxLon = maxLon > coord.longitude ? maxLon : coord.longitude;
      }
    }

    final bounds = S57Bounds(
      north: maxLat,
      south: minLat,
      east: maxLon,
      west: minLon,
    );

    final spatialIndex = S57SpatialIndex();
    spatialIndex.addFeatures(features);

    return S57ParsedData(
      metadata: S57ChartMetadata(
        producer: 'NavTool',
        version: '1.0',
        updateDate: DateTime.now(),
      ),
      features: features,
      bounds: bounds,
      spatialIndex: spatialIndex,
    );
  }
}