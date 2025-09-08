/// S-52 Presentation Library Color Tables
/// 
/// Implements IHO S-52 standard color tables for marine chart display
/// Supports day, night, and dusk modes as specified in IHO S-52 Edition 4.0
library;

import 'package:flutter/material.dart';

/// S-52 Color Table implementation for marine chart symbology
class S52ColorTables {
  /// Get color table for specified display mode
  static S52ColorTable getColorTable(S52DisplayMode mode) {
    return switch (mode) {
      S52DisplayMode.day => _dayColorTable,
      S52DisplayMode.night => _nightColorTable,
      S52DisplayMode.dusk => _duskColorTable,
    };
  }

  /// Day mode color table (DAYCOL)
  static const S52ColorTable _dayColorTable = S52ColorTable(
    mode: S52DisplayMode.day,
    colors: {
      // Sea and water areas
      S52ColorToken.depare1: Color(0xFFC5D2D8), // Shallow water
      S52ColorToken.depare2: Color(0xFFFFFFFF), // Safety contour
      S52ColorToken.depare3: Color(0xFFC5D2D8), // Deep water
      S52ColorToken.depdw: Color(0xFFFFFFFF),   // Deep water
      
      // Land and coast
      S52ColorToken.landa: Color(0xFFD9D0C7),   // Land areas
      S52ColorToken.landf: Color(0xFFCDBDB6),   // Land foreshore
      S52ColorToken.cstln: Color(0xFF000000),   // Coastline
      
      // Navigation aids
      S52ColorToken.lights: Color(0xFFFFFF00),  // Lights (yellow)
      S52ColorToken.buoys: Color(0xFF7C4700),   // Buoys (brown)
      S52ColorToken.beacons: Color(0xFF7C4700), // Beacons (brown) 
      
      // Dangers and obstructions
      S52ColorToken.danger: Color(0xFFFF0000),  // Danger red
      S52ColorToken.obstruction: Color(0xFF8B4513), // Obstruction
      S52ColorToken.wrecks: Color(0xFF8B4513),  // Wrecks
      
      // Text and symbols
      S52ColorToken.chblk: Color(0xFF000000),   // Chart black
      S52ColorToken.chgrd: Color(0xFF4D4D4D),   // Chart gray
      S52ColorToken.chgrf: Color(0xFF767676),   // Chart gray fill
      S52ColorToken.chred: Color(0xFFFF0000),   // Chart red
      S52ColorToken.chgrn: Color(0xFF00FF00),   // Chart green
      S52ColorToken.chylw: Color(0xFFFFFF00),   // Chart yellow
      S52ColorToken.chmgd: Color(0xFFFF00FF),   // Chart magenta
      S52ColorToken.chcor: Color(0xFFFFA500),   // Chart coral
      S52ColorToken.chbrn: Color(0xFF8B4513),   // Chart brown
    },
  );

  /// Night mode color table (NIGHTCOL)
  static const S52ColorTable _nightColorTable = S52ColorTable(
    mode: S52DisplayMode.night,
    colors: {
      // Sea and water areas (darker, red-shifted)
      S52ColorToken.depare1: Color(0xFF1A1A2E), // Shallow water
      S52ColorToken.depare2: Color(0xFF16213E), // Safety contour
      S52ColorToken.depare3: Color(0xFF0F0F23), // Deep water
      S52ColorToken.depdw: Color(0xFF0F0F23),   // Deep water
      
      // Land and coast (very dark)
      S52ColorToken.landa: Color(0xFF2D2D2D),   // Land areas
      S52ColorToken.landf: Color(0xFF404040),   // Land foreshore
      S52ColorToken.cstln: Color(0xFFFF6B6B),   // Coastline (red)
      
      // Navigation aids (visible but not harsh)
      S52ColorToken.lights: Color(0xFFFFD700),  // Lights (gold)
      S52ColorToken.buoys: Color(0xFFCD853F),   // Buoys (sandy brown)
      S52ColorToken.beacons: Color(0xFFCD853F), // Beacons (sandy brown)
      
      // Dangers and obstructions (red but muted)
      S52ColorToken.danger: Color(0xFFDC143C),  // Danger crimson
      S52ColorToken.obstruction: Color(0xFFA0522D), // Obstruction
      S52ColorToken.wrecks: Color(0xFFA0522D),  // Wrecks
      
      // Text and symbols (red/amber theme)
      S52ColorToken.chblk: Color(0xFFFF6B6B),   // Chart red
      S52ColorToken.chgrd: Color(0xFFCD5C5C),   // Chart red gray
      S52ColorToken.chgrf: Color(0xFF8B4513),   // Chart red fill
      S52ColorToken.chred: Color(0xFFFF4444),   // Chart bright red
      S52ColorToken.chgrn: Color(0xFFFFB347),   // Chart amber (not green)
      S52ColorToken.chylw: Color(0xFFFFD700),   // Chart gold
      S52ColorToken.chmgd: Color(0xFFDA70D6),   // Chart orchid
      S52ColorToken.chcor: Color(0xFFFF7F50),   // Chart coral
      S52ColorToken.chbrn: Color(0xFFCD853F),   // Chart brown
    },
  );

  /// Dusk mode color table (intermediate between day and night)
  static const S52ColorTable _duskColorTable = S52ColorTable(
    mode: S52DisplayMode.dusk,
    colors: {
      // Sea and water areas (transitional)
      S52ColorToken.depare1: Color(0xFF8A9BA8), // Shallow water
      S52ColorToken.depare2: Color(0xFFCCCCCC), // Safety contour
      S52ColorToken.depare3: Color(0xFF6B7B88), // Deep water
      S52ColorToken.depdw: Color(0xFF6B7B88),   // Deep water
      
      // Land and coast (muted)
      S52ColorToken.landa: Color(0xFFB8ADA4),   // Land areas
      S52ColorToken.landf: Color(0xFFA49C95),   // Land foreshore
      S52ColorToken.cstln: Color(0xFF4D4D4D),   // Coastline (dark gray)
      
      // Navigation aids (enhanced visibility)
      S52ColorToken.lights: Color(0xFFFFE135),  // Lights (bright yellow)
      S52ColorToken.buoys: Color(0xFF8B6914),   // Buoys (dark goldenrod)
      S52ColorToken.beacons: Color(0xFF8B6914), // Beacons (dark goldenrod)
      
      // Dangers and obstructions (prominent but not harsh)
      S52ColorToken.danger: Color(0xFFCC0000),  // Danger red
      S52ColorToken.obstruction: Color(0xFF8B4513), // Obstruction
      S52ColorToken.wrecks: Color(0xFF8B4513),  // Wrecks
      
      // Text and symbols (enhanced contrast)
      S52ColorToken.chblk: Color(0xFF2F2F2F),   // Chart dark gray
      S52ColorToken.chgrd: Color(0xFF5A5A5A),   // Chart gray
      S52ColorToken.chgrf: Color(0xFF6E6E6E),   // Chart gray fill
      S52ColorToken.chred: Color(0xFFCC0000),   // Chart red
      S52ColorToken.chgrn: Color(0xFF00CC00),   // Chart green
      S52ColorToken.chylw: Color(0xFFFFE135),   // Chart yellow
      S52ColorToken.chmgd: Color(0xFFCC00CC),   // Chart magenta
      S52ColorToken.chcor: Color(0xFFFF6347),   // Chart coral
      S52ColorToken.chbrn: Color(0xFF8B4513),   // Chart brown
    },
  );
}

/// S-52 Display modes for marine chart presentation
enum S52DisplayMode {
  /// Day mode - full color, high contrast
  day,
  
  /// Night mode - red/amber colors for night vision preservation
  night,
  
  /// Dusk mode - intermediate colors for twilight conditions
  dusk,
}

/// S-52 Color tokens as defined in IHO S-52 specifications
enum S52ColorToken {
  // Water depth areas
  depare1,  // Shallow water
  depare2,  // Safety contour
  depare3,  // Deep water  
  depdw,    // Deep water (alternative)
  
  // Land and coastline
  landa,    // Land areas
  landf,    // Land foreshore
  cstln,    // Coastline
  
  // Navigation aids
  lights,   // Lights
  buoys,    // Buoys
  beacons,  // Beacons
  
  // Dangers and obstructions
  danger,      // General danger
  obstruction, // Obstructions
  wrecks,      // Wrecks
  
  // Chart colors (basic palette)
  chblk,    // Chart black
  chgrd,    // Chart gray
  chgrf,    // Chart gray fill
  chred,    // Chart red
  chgrn,    // Chart green
  chylw,    // Chart yellow
  chmgd,    // Chart magenta
  chcor,    // Chart coral
  chbrn,    // Chart brown
}

/// S-52 Color table containing colors for a specific display mode
class S52ColorTable {
  final S52DisplayMode mode;
  final Map<S52ColorToken, Color> colors;

  const S52ColorTable({
    required this.mode,
    required this.colors,
  });

  /// Get color for specific token
  Color getColor(S52ColorToken token) {
    return colors[token] ?? const Color(0xFF000000); // Default to black
  }

  /// Get color with transparency
  Color getColorWithAlpha(S52ColorToken token, int alpha) {
    final color = getColor(token);
    return color.withAlpha(alpha);
  }

  /// Check if color token exists in this table
  bool hasColor(S52ColorToken token) {
    return colors.containsKey(token);
  }
}