import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/models/chart.dart';
import '../../core/providers/noaa_providers.dart';
import '../../core/state/providers.dart';
import 'widgets/chart_card.dart';

/// Main screen for browsing and discovering NOAA charts by US state
class ChartBrowserScreen extends ConsumerStatefulWidget {
  const ChartBrowserScreen({super.key});

  @override
  ConsumerState<ChartBrowserScreen> createState() => _ChartBrowserScreenState();
}

class _ChartBrowserScreenState extends ConsumerState<ChartBrowserScreen> {
  String? _selectedState;
  String _searchQuery = '';
  Set<ChartType> _selectedChartTypes = {};
  Set<String> _selectedChartIds = {};
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _searchDebouncer;
  
  // List of US coastal states that have NOAA charts
  static const List<String> _coastalStates = [
    'Alabama',
    'Alaska',
    'California',
    'Connecticut',
    'Delaware',
    'Florida',
    'Georgia',
    'Hawaii',
    'Illinois',
    'Indiana',
    'Louisiana',
    'Maine',
    'Maryland',
    'Massachusetts',
    'Michigan',
    'Minnesota',
    'Mississippi',
    'Nevada',
    'New Hampshire',
    'New Jersey',
    'New York',
    'North Carolina',
    'Ohio',
    'Oregon',
    'Pennsylvania',
    'Rhode Island',
    'South Carolina',
    'Texas',
    'Vermont',
    'Virginia',
    'Washington',
    'Wisconsin',
  ];

  List<Chart> _charts = [];
  List<Chart> _filteredCharts = [];

  @override
  void initState() {
    super.initState();
    // Automatically discover charts based on location when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _discoverChartsBasedOnLocation();
    });
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart Browser'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_selectedChartIds.isNotEmpty)
            TextButton.icon(
              onPressed: _downloadSelectedCharts,
              icon: const Icon(Icons.download),
              label: Text('Download Selected'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Controls section
          _buildControlsSection(),
          
          // Selected count
          if (_selectedChartIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                '${_selectedChartIds.length} selected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          
          // Content section
          Expanded(
            child: _buildContentSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // State selection dropdown
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Select a US state to browse charts',
                  child: DropdownButtonFormField<String>(
                    value: _selectedState,
                    decoration: const InputDecoration(
                      labelText: 'Select State',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map),
                    ),
                    items: _coastalStates.map((state) {
                      return DropdownMenuItem(
                        value: state,
                        child: Text(state),
                      );
                    }).toList(),
                    onChanged: _onStateSelected,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Search field
          Semantics(
            label: 'Search charts by name or description',
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search charts...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Chart type filter chips
          Semantics(
            label: 'Filter charts by type',
            child: Wrap(
              spacing: 8,
              children: ChartType.values.map((type) {
                final isSelected = _selectedChartTypes.contains(type);
                return FilterChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  onSelected: (selected) => _onChartTypeFilterChanged(type, selected),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection() {
    if (_selectedState == null) {
      return _buildEmptyState(
        icon: Icons.map_outlined,
        title: 'Select a State',
        message: 'Choose a US state from the dropdown above to browse available charts.',
      );
    }

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading charts...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_filteredCharts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.map_outlined,
        title: 'No charts found',
        message: 'No charts are available for the selected state and filters.',
      );
    }

    return ListView.builder(
      itemCount: _filteredCharts.length,
      itemBuilder: (context, index) {
        final chart = _filteredCharts[index];
        return ChartCard(
          chart: chart,
          isSelected: _selectedChartIds.contains(chart.id),
          onSelectionChanged: (selected) => _onChartSelectionChanged(chart.id, selected ?? false),
          onTap: () => _onChartTapped(chart),
          onInfoTap: () => _showChartDetails(chart),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load charts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryLoadCharts,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _onStateSelected(String? state) {
    if (state != null && state != _selectedState) {
      setState(() {
        _selectedState = state;
        _selectedChartIds.clear();
        _charts.clear();
        _filteredCharts.clear();
        _errorMessage = null;
      });
      _loadChartsForState(state);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    
    // Debounce search
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  void _onChartTypeFilterChanged(ChartType type, bool selected) {
    setState(() {
      if (selected) {
        _selectedChartTypes.add(type);
      } else {
        _selectedChartTypes.remove(type);
      }
    });
    _filterCharts();
  }

  void _onChartSelectionChanged(String chartId, bool selected) {
    setState(() {
      if (selected) {
        _selectedChartIds.add(chartId);
      } else {
        _selectedChartIds.remove(chartId);
      }
    });
  }

  void _onChartTapped(Chart chart) {
    // Navigate to chart display
    Navigator.pushNamed(
      context,
      '/chart',
      arguments: {
        'chartTitle': chart.title,
        'chartId': chart.id,
      },
    );
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
    });
    _filterCharts();
  }

  /// Automatically discovers charts based on current GPS location with Seattle fallback
  Future<void> _discoverChartsBasedOnLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get GPS service and discovery service
      final gpsService = ref.read(gpsServiceProvider);
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);
      
      // Get current position with Seattle fallback
      final position = await gpsService.getCurrentPositionWithFallback();
      
      if (position != null) {
        // Discover charts based on location
        final charts = await discoveryService.discoverChartsByLocation(position);
        
        if (mounted) {
          setState(() {
            _charts = charts;
            _isLoading = false;
          });
          _filterCharts();
        }
      } else {
        // Fallback to manual state selection if location discovery fails
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Unable to determine location. Please select a state manually.';
          });
        }
      }
    } catch (error) {
      // Fallback to manual state selection on error
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location discovery failed. Please select a state manually.';
        });
      }
    }
  }

  Future<void> _loadChartsForState(String state) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);
      final charts = await discoveryService.discoverChartsByState(state);
      
      if (mounted) {
        setState(() {
          _charts = charts;
          _isLoading = false;
        });
        _filterCharts();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.toString();
        });
      }
    }
  }

  void _performSearch() {
    if (_searchQuery.isEmpty) {
      _filterCharts();
      return;
    }

    try {
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);
      discoveryService.searchCharts(
        _searchQuery,
        filters: _selectedState != null ? {'state': _selectedState!} : null,
      ).then((searchResults) {
        if (mounted) {
          setState(() {
            _charts = searchResults;
          });
          _filterCharts();
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _errorMessage = error.toString();
          });
        }
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    }
  }

  void _filterCharts() {
    setState(() {
      _filteredCharts = _charts.where((chart) {
        // Filter by chart type
        if (_selectedChartTypes.isNotEmpty && !_selectedChartTypes.contains(chart.type)) {
          return false;
        }
        
        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          return chart.title.toLowerCase().contains(query) ||
                 chart.id.toLowerCase().contains(query) ||
                 (chart.description?.toLowerCase().contains(query) ?? false);
        }
        
        return true;
      }).toList();
    });
  }

  void _retryLoadCharts() {
    if (_selectedState != null) {
      _loadChartsForState(_selectedState!);
    }
  }

  void _downloadSelectedCharts() async {
    if (_selectedChartIds.isEmpty) return;

    try {
      final downloadService = ref.read(downloadServiceProvider);
      final selectedCharts = _charts.where((chart) => _selectedChartIds.contains(chart.id)).toList();
      
      // Show initial feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting download of ${selectedCharts.length} charts...'),
          duration: const Duration(seconds: 2),
        ),
      );

      // Start downloading each selected chart
      for (final chart in selectedCharts) {
        final downloadUrl = 'https://charts.noaa.gov/ENCs/${chart.id}.zip';
        await downloadService.downloadChart(chart.id, downloadUrl);
      }

      // Clear selection after successful downloads
      setState(() {
        _selectedChartIds.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully started download of ${selectedCharts.length} charts'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start downloads: $error'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showChartDetails(Chart chart) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chart.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text('Chart ID: ${chart.id}'),
              Text('Scale: 1:${chart.scale.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (Match m) => '${m[1]},',
              )}'),
              Text('Type: ${chart.type.displayName}'),
              Text('State: ${chart.state}'),
              const SizedBox(height: 8),
              Text('Coverage Area:'),
              Text('  North: ${chart.bounds.north.toStringAsFixed(4)}°'),
              Text('  South: ${chart.bounds.south.toStringAsFixed(4)}°'),
              Text('  East: ${chart.bounds.east.toStringAsFixed(4)}°'),
              Text('  West: ${chart.bounds.west.toStringAsFixed(4)}°'),
              if (chart.description != null) ...[
                const SizedBox(height: 8),
                Text('Description:'),
                Text(chart.description!),
              ],
              const SizedBox(height: 8),
              Text('Last Updated: ${chart.lastUpdate.toString().split(' ')[0]}'),
              if (chart.fileSize != null)
                Text('File Size: ${_formatFileSize(chart.fileSize!)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!chart.isDownloaded)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                
                try {
                  final downloadService = ref.read(downloadServiceProvider);
                  final downloadUrl = 'https://charts.noaa.gov/ENCs/${chart.id}.zip';
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Starting download of ${chart.title}...'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  
                  await downloadService.downloadChart(chart.id, downloadUrl);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Successfully started download of ${chart.title}'),
                        duration: const Duration(seconds: 3),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to download ${chart.title}: $error'),
                        duration: const Duration(seconds: 5),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}