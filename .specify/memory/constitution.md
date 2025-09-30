<!--
Sync Impact Report:
- Version change: INITIAL → 1.0.0 → 1.1.0 → 1.2.0 → 1.3.0
- Initial constitution establishment for NavTool marine navigation application
- Added 9 core principles specific to safety-critical maritime software
- MINOR version bump (1.3.0): Enhanced Principle III with test preservation requirements
- MINOR version bump (1.2.0): Added Principle IX (Authentic Test Data Requirement)
- MINOR version bump (1.1.0): Added Principle VIII (Chart Data Pipeline & Performance Optimization)
- Added Marine Safety Standards section
- Added Development Workflow & Quality Gates section
- Templates alignment: ✅ All templates reviewed and compatible with principles
- Follow-up TODOs: None

Version 1.3.0 Amendment:
- Added mandatory test failure analysis requirements to Principle III
- Prohibits modifying existing tests without conclusive evidence of test defects
- Requires thorough analysis before changing passing tests
- Prevents "simplification" that removes safety-critical test coverage

Version 1.2.0 Amendment:
- Added mandatory requirement to use real NOAA ENC charts for testing
- Prohibits synthetic/self-generated chart data in unit tests
- Ensures test fixtures use authentic S-57 data from test/fixtures/charts/noaa_enc/
- Validates testing against actual marine chart data structures

Version 1.1.0 Amendment:
- Added mandatory chart data processing pipeline requirement
- SENC (System Electronic Navigational Chart) generation from raw S-57 data
- Performance optimization through intermediate format storage
- Separates data acquisition from rendering for optimal marine use

Constitution establishes foundational principles for marine navigation software
emphasizing safety, reliability, offline-first operation, and comprehensive testing.
-->

# NavTool Constitution

## Core Principles

### I. Safety-Critical Accuracy (NON-NEGOTIABLE)

Navigation features MUST prioritize accuracy and reliability above all other concerns.
Maritime navigation is safety-critical; errors can endanger lives and vessels. All
position calculations, chart data processing, and routing algorithms MUST be verified
against known marine navigation standards and validated with comprehensive test coverage.

**Rationale**: Marine navigation software directly impacts vessel and crew safety.
Inaccurate position data, incorrect chart rendering, or faulty routing calculations
can lead to groundings, collisions, or other maritime incidents. This principle
supersedes performance optimization, feature velocity, and code elegance.

### II. Offline-First Architecture

All core navigation functionality MUST operate without network connectivity. Network
operations MUST be treated as enhancement features, not dependencies. Local data
storage, caching strategies, and fallback mechanisms are MANDATORY for all navigation-
critical features. The application MUST gracefully handle intermittent satellite
connectivity scenarios common in marine environments.

**Rationale**: Mariners often operate in areas with limited or no connectivity
(satellite internet, coastal dead zones, international waters). The application must
remain fully functional for navigation when network access is unavailable or unreliable.

### III. Dual Testing Strategy (NON-NEGOTIABLE)

All features MUST implement both mock-based unit tests AND real-world integration tests:

- **Mock-based tests**: Fast execution, comprehensive error scenarios, CI/CD compatible
- **Integration tests**: Real NOAA API calls, actual GPS data, real chart files
- Tests MUST be written first, MUST fail before implementation, then implementation
  makes them pass (TDD mandatory)
- 90%+ code coverage required for safety-critical navigation features
- Performance benchmarks required for maritime calculations (coordinate transformations,
  route optimization, chart rendering)

**Test Preservation & Failure Analysis (NON-NEGOTIABLE):**

When existing tests fail during new feature development, the tests MUST be preserved
and thoroughly analyzed before ANY modification:

1. **Assume tests are correct**: Existing tests exist for a reason; they capture
   requirements, edge cases, or discovered bugs from prior development
2. **Required analysis before modification**:
   - Document WHY the test exists (git history, comments, related issues)
   - Identify WHAT behavior the test validates
   - Determine IF the test reveals a defect in new code vs. test defect
   - Provide conclusive evidence if claiming test is incorrect
3. **Prohibited actions**:
   - "Simplifying" tests to make them pass
   - Removing tests because they're "inconvenient" for new implementation
   - Weakening assertions without justification
   - Changing test data to avoid failures
4. **Required actions when tests fail**:
   - First, fix the implementation to satisfy existing tests
   - Only modify tests when conclusive evidence proves test defect (wrong assertion,
     outdated requirement, incorrect test data)
   - Document test changes with: before/after behavior, evidence of test defect,
     safety impact analysis
   - Obtain review approval for any test modification with safety implications

**Rationale**: Marine software requires both speed (unit tests for development velocity)
and confidence (integration tests for real-world validation). Mock tests catch logic
errors; integration tests validate marine environment compatibility. Existing tests
represent accumulated knowledge about correct behavior and edge cases. Weakening tests
to accommodate new code risks reintroducing bugs and navigation failures. Test failures
during development are often symptoms of implementation defects, not test defects.

### IV. Maritime Software Conventions

All navigation features MUST follow established maritime software standards:

- IHO S-52 Presentation Library for chart symbology
- IHO S-57 Edition 3.1 for electronic chart data
- NMEA protocols for GPS and marine electronics integration
- WGS84 coordinate system for all geographic calculations
- Nautical units (nautical miles, knots, fathoms/meters) displayed appropriately

**Rationale**: Maritime industry has established international standards. Compliance
ensures interoperability, user familiarity, and reduces navigation errors from
non-standard implementations.

### V. Network Resilience & Graceful Degradation

All network operations MUST implement comprehensive error handling with exponential
backoff retry logic. Rate limiting MUST respect external service constraints (NOAA:
5 requests/second). Network failures MUST NOT prevent application functionality; cached
data MUST always be available. Clear UI indicators MUST distinguish between fresh and
cached data without forcing updates.

**Rationale**: Marine environments have unreliable connectivity (satellite internet,
weather interference). Applications must handle network issues gracefully without
disrupting navigation workflows or creating user frustration.

### VI. Feature Modularity & Service Architecture

New features MUST be implemented as modular services with clear boundaries and minimal
coupling. Each service MUST have well-defined interfaces, comprehensive error handling,
and be independently testable. Riverpod dependency injection MUST be used for service
management to enable testing and maintainability.

**Rationale**: Marine navigation applications are complex systems with many integrated
features (charts, GPS, weather, routing). Modular architecture enables parallel
development, comprehensive testing, and easier maintenance of safety-critical code.

### VII. Performance Constraints for Marine Use

Performance targets MUST account for marine environment usage patterns:

- Chart rendering: <100ms initial display, <16ms for pan/zoom (60fps)
- GPS position update: <500ms latency from device to display
- Route calculations: <2 seconds for typical coastal routes (<100nm)
- Memory usage: <500MB for typical chart set to enable older hardware
- Battery optimization: Minimize GPS and rendering power consumption for extended use

**Rationale**: Marine applications run on diverse hardware (marine chart plotters,
tablets, laptops) in challenging conditions (bright sunlight, cold/wet weather,
limited power). Performance must support long offshore passages where battery life
and reliable operation are critical.

### VIII. Chart Data Pipeline & Performance Optimization (NON-NEGOTIABLE)

Downloaded NOAA S-57 charts MUST be processed into an optimized intermediate format
before rendering. Raw S-57 data MUST NOT be parsed at render time. The chart processing
pipeline MUST be:

1. **Download Phase**: Acquire raw S-57 chart files (.000) from NOAA in original format
2. **Processing Phase**: Parse S-57 data and generate SENC (System Electronic 
   Navigational Chart) format optimized for rendering performance
3. **Storage Phase**: Store processed SENC data with spatial indexing (R-tree) for
   efficient geographic queries
4. **Rendering Phase**: Chart display engine reads ONLY from optimized SENC format,
   never from raw S-57 files

The SENC generation MUST include:
- Pre-computed symbol rendering data per IHO S-52 standards
- Spatial indexing for viewport-based feature queries
- Scale-dependent feature organization for automatic LOD (Level of Detail)
- Validated geometry and attribute data with error detection

**Rationale**: Raw S-57 parsing is computationally expensive and unsuitable for
real-time rendering at sea. Marine chart plotters use optimized intermediate formats
(SENC) to achieve required performance (<100ms initial display, 60fps pan/zoom).
Separating data acquisition from rendering enables offline chart updates, efficient
memory usage, and reliable performance on diverse marine hardware. This architecture
is standard practice in professional marine navigation systems.

### IX. Authentic Test Data Requirement (NON-NEGOTIABLE)

All unit tests and integration tests MUST use authentic NOAA ENC chart data from
`test/fixtures/charts/noaa_enc/` directory. Self-generated, synthetic, or mock chart
data structures MUST NOT be used for testing chart parsing, processing, or rendering
functionality. Test fixtures MUST include:

- Real S-57 .000 chart files downloaded from NOAA
- Original binary data structures and encoding
- Authentic maritime feature types, attributes, and geometries
- Actual coordinate systems and projection data from real charts

Synthetic data MAY ONLY be used for:
- Network mocking (API responses, download simulation)
- GPS coordinate generation within valid marine areas
- User interface interaction testing unrelated to chart data

**Rationale**: S-57 chart data has complex binary encoding, geometry relationships,
attribute schemas, and edge cases that cannot be reliably reproduced with synthetic
data. Testing against real NOAA charts ensures the parser handles actual maritime
data structures, catches encoding edge cases, validates coordinate transformations
with real-world data, and provides confidence that the system works with charts
mariners will actually use. Synthetic chart data creates false confidence and misses
real-world parsing challenges that could cause navigation failures at sea.

**Test Chart Inventory**: The repository includes authentic NOAA ENC test data:
- `US5WA50M.000` - Elliott Bay harbor-scale chart (143.9 KB)
- `US3WA01M.000` - Puget Sound coastal-scale chart (625.3 KB)

These charts MUST be used for all S-57 parsing, SENC generation, and chart rendering
test scenarios.

## Marine Safety Standards

### Chart Data Integrity

Electronic chart data MUST be validated for integrity and currency:

- S-57 chart files MUST be parsed according to IHO specification
- Chart update dates MUST be clearly displayed to users
- Corrupted or invalid chart data MUST be rejected with clear error messages
- Users MUST be warned when using outdated chart editions
- Test charts MUST be clearly marked as "NOT FOR NAVIGATION"

### Position Accuracy Requirements

GPS and position tracking features MUST meet marine accuracy standards:

- Position accuracy indicators MUST be displayed (HDOP, satellite count)
- GPS signal loss MUST trigger clear visual and audible warnings
- Dead reckoning fallback MUST be implemented for signal loss scenarios
- Position history/track recording MUST be reliable for safety investigations

### Error Handling & User Warnings

Safety-critical errors MUST be communicated clearly to users:

- Chart loading failures MUST explain impact on navigation safety
- GPS accuracy warnings MUST be prominent and persistent
- Network failures affecting chart updates MUST be clearly indicated
- All error messages MUST provide actionable guidance

## Development Workflow & Quality Gates

### Code Review Requirements

All code changes MUST pass review verification:

- Navigation calculations MUST be reviewed by contributor with marine navigation
  expertise or verified against established marine navigation libraries
- Safety-critical features (GPS, chart rendering, routing) require dual review
- Test coverage MUST NOT decrease; <90% coverage blocks merge
- Constitutional compliance MUST be verified in review comments

### Testing Gates

Code MUST pass all testing gates before merge:

- All unit tests pass (mock-based, <10 minutes execution)
- All integration tests pass (real network, <30 minutes execution)
- Performance benchmarks within acceptable ranges
- No new analyzer warnings (Flutter analyze --fatal-infos)
- Security audit passes (Flutter pub audit)

### Build & Deployment Standards

Builds and deployments MUST follow marine software reliability standards:

- NEVER CANCEL builds; set 90+ minute timeouts for safety-critical software
- NEVER REDUCE test timeouts; marine connectivity requires patience
- All three desktop platforms (Linux, Windows, macOS) MUST build successfully
- Release builds MUST include version metadata for incident investigation
- Test fixtures MUST include real NOAA chart data for validation

### Manual Validation Requirements

Before release, features MUST pass manual validation scenarios:

- Application launch and window management across all platforms
- Marine navigation workflow with test chart data (Elliott Bay charts)
- Offline functionality without network connectivity
- GPS coordinate handling with realistic marine test data
- Error handling for common marine environment issues (network loss, GPS signal loss)

## Governance

This constitution supersedes all other development practices and guidelines. All
feature specifications, implementation plans, and code reviews MUST verify compliance
with these principles. Complexity that violates constitutional principles MUST be
justified with specific maritime safety or user requirements; unjustified complexity
MUST be simplified before implementation proceeds.

### Amendment Procedure

Constitutional amendments require:

1. Documented rationale with maritime safety impact analysis
2. Review of all affected specifications and implementations
3. Update of `.github/copilot-instructions.md` for AI assistant alignment
4. Version bump following semantic versioning (see below)
5. Migration plan for existing code not in compliance

### Versioning Policy

Constitution versions follow semantic versioning:

- **MAJOR**: Backward incompatible principle changes (e.g., removing safety requirement)
- **MINOR**: New principles added or material expansions to existing principles
- **PATCH**: Clarifications, wording improvements, non-semantic refinements

### Compliance Review

All pull requests MUST include constitutional compliance verification. Use
`.github/copilot-instructions.md` for detailed runtime development guidance aligned
with these principles. When specifications or implementations violate principles
without justification, they MUST be revised before proceeding.

**Version**: 1.3.0 | **Ratified**: 2025-09-29 | **Last Amended**: 2025-09-29