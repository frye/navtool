
# Implementation Plan: Fix Stuck Tests and Mock Generation Failures

**Branch**: `002-fix-stuck-tests` | **Date**: September 29, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/Users/frye/Devel/repos/navtool/specs/002-fix-stuck-tests/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code or `AGENTS.md` for opencode).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Fix chart browser screen tests that hang during execution and resolve mock generation failures in CI. Tests get stuck after "should show date filtering controls when enabled" and never complete "should filter charts by scale range", requiring manual Ctrl+C interruption. Additionally, GitHub Actions workflows fail during build_runner mock generation, blocking CI/CD pipeline. The solution involves identifying root causes of test hangs (likely infinite pumpAndSettle loops or missing UI state changes), adjusting test timeouts and wait strategies, and resolving build_runner configuration issues preventing mock file generation in CI environments.

## Technical Context
**Language/Version**: Dart 3.8.1+, Flutter 3.8.1+  
**Primary Dependencies**: flutter_test, mockito ^5.4.4, build_runner ^2.4.12, flutter_riverpod ^2.5.1  
**Storage**: N/A (bug fix)  
**Testing**: flutter_test (widget tests), mockito (mock generation), build_runner (code generation)  
**Target Platform**: macOS, Linux, Windows (desktop platforms)  
**Project Type**: single (Flutter desktop application)  
**Performance Goals**: Test suite must complete within 15 minutes, mock generation within 5 minutes  
**Constraints**: Tests must complete without manual interruption, mock generation must succeed in CI and local environments, no reduction of test coverage or quality  
**Scale/Scope**: ~150 test files with @GenerateMocks annotations, chart browser screen tests (~2100 tests in file)

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Safety-Critical Accuracy ✅
- **Status**: PASS - Bug fix improves reliability of navigation software testing
- **Verification**: Fixing test execution ensures safety-critical code is properly validated

### Principle II: Offline-First Architecture ✅
- **Status**: PASS - No impact on offline functionality (test infrastructure only)
- **Verification**: N/A for test infrastructure changes

### Principle III: Dual Testing Strategy ✅
- **Status**: PASS - Preserves all existing tests, ensures they can execute to completion
- **Test Preservation**: NO tests will be modified to "pass" - only test execution infrastructure
- **Rationale**: Fixing test hangs enables proper TDD workflow and validates 90%+ coverage requirement
- **Verification**: All existing tests must still validate the same behaviors after fixes

### Principle IV: Maritime Software Conventions ✅
- **Status**: PASS - No impact on maritime standards (test infrastructure only)
- **Verification**: N/A for test infrastructure changes

### Principle V: Network Resilience & Graceful Degradation ✅
- **Status**: PASS - No impact on network handling (test infrastructure only)
- **Verification**: N/A for test infrastructure changes

### Principle VI: Feature Modularity & Service Architecture ✅
- **Status**: PASS - Test fixes maintain modular service testing patterns
- **Verification**: Mock generation ensures services remain independently testable

### Principle VII: Performance Constraints for Marine Use ✅
- **Status**: PASS - Test performance does not impact runtime application performance
- **Verification**: Tests complete within 15 minutes ensuring fast development feedback

### Principle VIII: Chart Data Pipeline & Performance Optimization ✅
- **Status**: PASS - No impact on SENC pipeline (test infrastructure only)
- **Verification**: N/A for test infrastructure changes

### Principle IX: Authentic Test Data Requirement ✅
- **Status**: PASS - Bug fix preserves existing test data approach
- **Verification**: Tests continue using authentic NOAA ENC charts from test/fixtures/

**Overall Constitution Status**: ✅ PASS - No constitutional violations identified

## Project Structure

### Documentation (this feature)
```
specs/002-fix-stuck-tests/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
lib/
├── features/
│   └── charts/
│       └── chart_browser_screen.dart  # UI being tested
├── core/
│   ├── services/
│   │   └── noaa/
│   │       └── noaa_chart_discovery_service.dart  # Service being mocked
│   ├── logging/
│   │   └── app_logger.dart  # Logger being mocked
│   └── state/
│       └── providers.dart  # Riverpod providers

test/
├── features/
│   └── charts/
│       ├── chart_browser_screen_test.dart  # STUCK TESTS HERE
│       └── chart_browser_screen_test.mocks.dart  # Generated mocks
├── utils/
│   └── test_fixtures.dart  # Test data utilities
└── flutter_test_config.dart  # Global test configuration

pubspec.yaml  # Dependencies: mockito, build_runner
build.yaml    # (if exists) build_runner configuration
```

**Structure Decision**: Single Flutter project structure with lib/ for production code and test/ for test files. This is a standard Flutter desktop application layout. The bug fix targets test infrastructure files only - specifically test execution patterns in chart_browser_screen_test.dart and build_runner configuration for mock generation.

## Phase 0: Outline & Research
**Status**: ✅ COMPLETE

Research completed and documented in `research.md`. Key findings:

### Root Causes Identified
1. **Test Hangs**: pumpAndSettle() enters infinite loop with continuously rebuilding widgets (filter controls with Sliders)
2. **Mock Generation**: build_runner dependency conflicts or invalid @GenerateMocks annotations in CI

### Technical Decisions
1. **Replace pumpAndSettle() with pumpAndWait()** for filter interactions
   - Rationale: Avoids infinite settle loops, provides explicit wait control
   - Pattern: pump() → Future.delayed() → pump()
   
2. **Add explicit timeouts** to tests with complex UI
   - Rationale: Prevents indefinite hangs, fails fast with clear error
   - Pattern: `timeout: Timeout(Duration(minutes: 2))`

3. **Use --verbose flag** for build_runner in CI
   - Rationale: Provides diagnostic information for debugging failures
   - Pattern: `flutter packages pub run build_runner build --delete-conflicting-outputs --verbose`

4. **Preserve all test assertions** (Constitution Principle III)
   - Rationale: Tests exist for safety reasons, only execution strategy changes
   - Pattern: No changes to expect() statements or test data

### Research Artifacts
- Decision matrix: pump strategies comparison
- Best practices: Flutter widget test async handling
- CI integration: build_runner optimization patterns

**Output**: `research.md` with all unknowns resolved

## Phase 1: Design & Contracts
**Status**: ✅ COMPLETE

### Generated Artifacts

1. **data-model.md**: Test execution state machines
   - Test Execution State (normal flow, error flow, stuck state)
   - Widget Pump Strategy (pumpAndSettle, pump, pumpAndWait)
   - Mock Generation Workflow (CI and local environments)
   - Test Fixture State (mocks, test data, provider overrides)

2. **contracts/test-pump-strategies.md**: Test helper contracts
   - pumpAndWait() contract
   - pumpAndSettleWithTimeout() contract  
   - Manual pump() pattern contract
   - Test timeout configuration contract

3. **contracts/mock-generation.md**: build_runner contract
   - Command interface and flags
   - Input/output specifications
   - Error modes and resolutions
   - CI integration patterns
   - Validation procedures

4. **quickstart.md**: Reproduction and validation guide
   - Step-by-step reproduction of stuck tests
   - Fix application instructions
   - Validation procedures
   - CI integration validation
   - Troubleshooting guide

### Design Validation
- ✅ No new data models in application code (test infrastructure only)
- ✅ All contracts specify behavior without implementation details
- ✅ Test preservation requirements documented
- ✅ CI/local parity requirements specified

**Output**: data-model.md, contracts/, quickstart.md complete

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

### Task Generation Strategy

The /tasks command will generate tasks based on the contracts and design documents:

1. **From test-pump-strategies.md contract**:
   - Task: Identify all stuck tests (grep for specific test names)
   - Task: Replace pumpAndSettle() with pumpAndWait() for each stuck test
   - Task: Add explicit timeouts to tests without them
   - Task: Validate pumpAndWait() helper is correctly implemented

2. **From mock-generation.md contract**:
   - Task: Verify @GenerateMocks annotations in all test files
   - Task: Update CI workflow with --verbose flag for build_runner
   - Task: Add build artifact caching to CI
   - Task: Test mock generation locally with clean build
   - Task: Validate CI mock generation in test branch

3. **From quickstart.md validation**:
   - Task: Run reproduction steps to confirm issue
   - Task: Apply fixes systematically
   - Task: Execute full test suite validation
   - Task: Verify no test behavior changes
   - Task: Update documentation with debugging patterns

### Ordering Strategy

**Phase 2.1: Preparation and Analysis** [P = parallel-safe tasks]
1. [P] Identify all stuck tests using terminal output and grep
2. [P] Audit @GenerateMocks annotations in all test files
3. [P] Verify pumpAndWait() helper implementation
4. [P] Document current test execution times (baseline)

**Phase 2.2: Test Execution Fixes**
5. Replace pumpAndSettle() in "should show date filtering controls" test
6. Replace pumpAndSettle() in "should filter charts by scale range" test
7. Add explicit timeout to enhanced filtering tests group
8. Scan for other filter-related tests needing same fix
9. [P] Add timeout to other complex UI tests

**Phase 2.3: Mock Generation Fixes**
10. [P] Add --verbose flag to CI mock generation step
11. [P] Add build artifact caching to CI workflow
12. [P] Update mock generation error messages
13. Run build_runner clean + build locally to validate

**Phase 2.4: Validation**
14. Run stuck tests individually to confirm completion
15. Run full chart_browser_screen_test.dart file
16. Verify test count and assertions unchanged
17. Measure test execution time vs baseline
18. [P] Test mock generation in CI (push to branch)

**Phase 2.5: Documentation**
19. Update .github/copilot-instructions.md with patterns ✅ (Already complete)
20. [P] Add test debugging guide to docs/
21. [P] Update PR description with findings
22. [P] Create issue templates for future test hangs

### Estimated Output
- **~22 numbered tasks** in tasks.md
- **6-8 parallel-safe tasks** marked [P]
- **TDD order**: Analysis → Fixes → Validation
- **Dependency order**: Test fixes before CI updates before documentation

### Task Template Structure
```markdown
## Task N: [Task Title]
**Type**: [Fix/Analysis/Validation/Documentation]
**Parallel-Safe**: [Yes/No]
**Estimated Time**: [5m/15m/30m/1h]

### Objective
[What this task accomplishes]

### Files to Modify
- path/to/file.dart (line range)

### Validation
- [ ] Validation criterion 1
- [ ] Validation criterion 2

### Dependencies
- Requires Task M to complete first (if any)
```

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented (N/A - no violations)

**Artifacts Generated**:
- [x] research.md (Phase 0)
- [x] data-model.md (Phase 1)
- [x] contracts/test-pump-strategies.md (Phase 1)
- [x] contracts/mock-generation.md (Phase 1)
- [x] quickstart.md (Phase 1)
- [x] .github/copilot-instructions.md updated (Phase 1)
- [ ] tasks.md (/tasks command)

---
*Based on Constitution v1.3.0 - See `.specify/memory/constitution.md`*
