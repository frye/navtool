---
name: Test Hang Issue
about: Report a test that hangs or times out
title: '[TEST HANG] '
labels: testing, bug
assignees: ''
---

## Test Information
- **Test File**: (e.g., test/features/charts/chart_browser_screen_test.dart)
- **Test Name**: (exact test description)
- **Line Number**: (approximate location)

## Symptoms
- [ ] Test hangs indefinitely
- [ ] Test times out after X minutes
- [ ] Requires manual Ctrl+C interruption

## Context
- **Last successful run**: (date or "never")
- **Recent changes**: (related PRs or commits)
- **Pump strategy used**: (pumpAndSettle / pumpAndWait / pump)

## Reproduction Steps
1. Run: `flutter test <file> --plain-name "<test name>"`
2. Observe: (what happens)
3. Expected: Test should complete within [X] seconds/minutes

## Expected Behavior
Test should complete within [X] seconds/minutes without manual interruption.

## Debug Checklist
Before reporting, please verify:
- [ ] Checked for pumpAndSettle() in test
- [ ] Verified timeout is set on test
- [ ] Reviewed widget rebuild triggers
- [ ] Tested with pumpAndWait() as alternative
- [ ] Consulted `docs/test-debugging-guide.md`
- [ ] Verified test expectations are correct (widgets actually exist)

## Additional Context
Add any other context about the problem here:
- CI vs local behavior differences
- Platform-specific issues (macOS, Linux, Windows)
- Mock configuration
- Test data setup

## Constitutional Compliance
- [ ] I have verified this is about test execution, not test assertions
- [ ] I understand test assertions should not be changed to fix hangs (Principle III)
