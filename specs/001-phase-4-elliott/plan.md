
# Implementation Plan: Elliott Bay Chart Loading UX Improvements

**Branch**: `001-phase-4-elliott` | **Date**: 2025-09-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/Users/frye/Devel/repos/navtool/specs/001-phase-4-elliott/spec.md`

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
Complete Phase 4 UX improvements for Elliott Bay chart loading with three critical components: (1) Fix ZipExtractor to handle NOAA ENC ZIP layouts robustly, (2) Implement integrity mismatch detection with SHA256 verification and first-load hash capture, and (3) Add transient parser failure recovery with exponential backoff retry logic. Includes loading progress indicators (< 500ms threshold), retry/dismiss user actions, sequential queue processing, and dual-level observability (minimal/debug logging). All features tested with widget and unit tests against real NOAA ENC fixtures.

## Technical Context
**Language/Version**: Dart 3.8.1+ / Flutter 3.8.1+
**Primary Dependencies**: `archive` (ZIP handling), `crypto` (SHA256), `flutter_riverpod` (state), `dio` (HTTP), `shared_preferences` (persistence)
**Storage**: SharedPreferences (integrity hash registry persistence), File system (chart ZIP archives)
**Testing**: Flutter test framework, widget tests, unit tests, integration tests with real NOAA ENC fixtures
**Target Platform**: Desktop (Linux, Windows, macOS primary), iOS secondary
**Project Type**: Single Flutter application (mobile architecture)
**Performance Goals**: Chart load < 500ms to show progress indicator, ZIP extraction < 2s for typical harbor chart (400KB), retry with exponential backoff (100ms, 200ms, 400ms, 800ms)
**Constraints**: Offline-first (no network for local ZIP loading), safety-critical (SHA256 integrity verification required), sequential queue processing (one chart at a time)
**Scale/Scope**: ~10 modified files, ~500-800 LOC additions, 3 new test files, real NOAA ENC test fixtures (US5WA50M.zip)

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Safety-Critical Accuracy ✅ PASS
- Chart integrity verification with SHA256 ensures data authenticity
- Prevents corrupted charts from navigation use (FR-006)
- Real NOAA ENC test fixtures validate against actual marine data (US5WA50M.000)

### Principle II: Offline-First Architecture ✅ PASS  
- Feature operates on local ZIP files, no network dependency for loading
- All functionality available without connectivity
- Graceful handling of transient failures with retry logic

### Principle III: Dual Testing Strategy ✅ PASS
- Widget tests for UI scenarios (integrity mismatch, transient retry)
- Unit tests for ZipExtractor with real NOAA ZIP fixtures
- Unit tests for ChartIntegrityRegistry
- Integration tests exist for chart loading pipeline
- TDD approach: Tests written first, fail before implementation

### Principle IV: Maritime Software Conventions ✅ PASS
- S-57 format compliance (working with .000 cell files)
- NOAA ENC standard ZIP layouts supported
- Maritime safety focus (integrity verification, error prevention)

### Principle V: Network Resilience & Graceful Degradation ✅ PASS
- Exponential backoff retry logic (100ms, 200ms, 400ms, 800ms)
- Max 4 retry attempts prevents infinite loops
- Clear error messages with retry/dismiss user actions
- Sequential queue processing ensures resource management

### Principle VI: Feature Modularity & Service Architecture ✅ PASS
- Modular services: ZipExtractor, ChartIntegrityRegistry, ChartLoadError
- Clear interfaces and error handling
- Riverpod-based dependency injection (existing architecture)
- Test hooks for fault injection (ChartLoadTestHooks)

### Principle VII: Performance Constraints ✅ PASS
- Progress indicator within 500ms (configurable constant)
- ZIP extraction optimized for typical chart sizes
- Memory-conscious sequential processing
- Exponential backoff prevents resource thrashing

### Principle VIII: Chart Data Pipeline ✅ PASS
- Works with existing S-57 → SENC pipeline
- ZIP extraction feeds into existing parser
- Integrity verification before SENC generation
- Performance optimization maintained

### Principle IX: Authentic Test Data ✅ PASS
- Uses real NOAA ENC fixtures: `test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip`
- Real S-57 .000 cell files (411KB Elliott Bay chart)
- No synthetic chart data in tests
- Validates against actual maritime data structures

**Status**: ✅ ALL CONSTITUTIONAL REQUIREMENTS MET - No violations or complexity tracking needed

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
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
├── core/
│   ├── services/
│   │   ├── chart_integrity_registry.dart        # [MODIFY] Add first-load capture
│   │   └── ...
│   └── utils/
│       ├── zip_extractor.dart                   # [MODIFY] Fix NOAA layout support
│       └── ...
├── features/
│   └── charts/
│       ├── chart_load_error.dart                # [EXISTS] Structured error types
│       ├── chart_load_test_hooks.dart           # [EXISTS] Fault injection hooks
│       ├── screens/
│       │   └── chart_browser_screen.dart        # [MODIFY] Add retry/dismiss UI
│       └── services/
│           └── chart_loading_service.dart       # [MODIFY] Add retry logic, queue
└── widgets/
    └── ...

test/
├── core/
│   ├── services/
│   │   └── chart_integrity_registry_test.dart   # [NEW] Unit tests for registry
│   └── utils/
│       └── zip_extractor_test.dart              # [MODIFY] Add NOAA layout tests
├── features/
│   └── charts/
│       ├── chart_integrity_mismatch_test.dart   # [EXISTS] Widget test integrity
│       └── chart_transient_retry_test.dart      # [EXISTS] Widget test retry
├── fixtures/
│   └── charts/
│       └── noaa_enc/
│           └── US5WA50M_harbor_elliott_bay.zip  # [EXISTS] Real test fixture
└── ...
```

**Structure Decision**: NavTool uses a single Flutter application structure with feature-based organization. Charts feature is in `lib/features/charts/`, core services in `lib/core/services/`, and shared utilities in `lib/core/utils/`. Tests mirror source structure in `test/`. This feature modifies existing files and adds new unit tests, leveraging the existing widget test infrastructure.

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per endpoint
   - Assert request/response schemas
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Each story → integration test scenario
   - Quickstart test = story validation steps

5. **Update agent file incrementally** (O(1) operation):
   - Run `.specify/scripts/bash/update-agent-context.sh copilot`
     **IMPORTANT**: Execute it exactly as specified above. Do not add or remove any arguments.
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, agent-specific file

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each contract → contract test task [P]
- Each entity → model creation task [P] 
- Each user story → integration test task
- Implementation tasks to make tests pass

**Ordering Strategy**:
- TDD order: Tests before implementation 
- Dependency order: Models before services before UI
- Mark [P] for parallel execution (independent files)

**Estimated Output**: 25-30 numbered, ordered tasks in tasks.md

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
- [x] Phase 0: Research complete (/plan command) ✅
- [x] Phase 1: Design complete (/plan command) ✅
- [x] Phase 2: Task planning complete (/plan command - describe approach only) ✅
- [x] Phase 3: Tasks generated (/tasks command) ✅
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS ✅
- [x] Post-Design Constitution Check: PASS ✅
- [x] All NEEDS CLARIFICATION resolved ✅
- [x] Complexity deviations documented (None - no violations) ✅

**Phase 1 Deliverables**:
- [x] research.md created with 7 technical decisions ✅
- [x] data-model.md created with 6 entity definitions ✅
- [x] contracts/service-contracts.md created with 6 service contracts ✅
- [x] quickstart.md created with 9 test scenarios ✅
- [x] .github/copilot-instructions.md updated with Phase 4 context ✅

**Phase 3 Deliverables**:
- [x] tasks.md created with 32 ordered tasks ✅
- [x] Task dependencies mapped (setup → tests → core → UI → polish) ✅
- [x] Parallel execution groups identified (3 groups) ✅
- [x] TDD workflow enforced (Phase 3.2 tests before Phase 3.3 implementation) ✅

**Ready for implementation**: ✅ All planning phases complete, begin T001

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*
