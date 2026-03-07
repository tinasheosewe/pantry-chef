# Full Codebase Audit

Perform a comprehensive, deep audit of the entire codebase. Scan every file methodically. Do not skim — read thoroughly.

## What to look for

### Bugs & Code-Level Errors
- Race conditions, deadlocks, or unsafe concurrent access to shared state
- Off-by-one errors, nil/null dereferences, force-unwraps, force-casts
- Unreachable code, dead code paths, or impossible conditions
- Missing error handling (unhandled throws, ignored Results, empty catch blocks)
- Resource leaks (unclosed connections, missing cleanup, retain cycles)
- Incorrect state transitions or missing state resets

### Logic & Behavioral Errors
- Features that don't actually do what they claim or intend to do — trace the logic end-to-end and verify it produces the correct result
- Conditions or branches that look right but are subtly wrong (inverted booleans, wrong comparison operators, incorrect enum cases)
- Data transformations that silently lose, corrupt, or misinterpret data
- Flows where user-facing behavior diverges from the apparent intent (e.g., a "save" that doesn't persist, a "delete" that leaves orphaned data, a filter that doesn't actually filter)
- Sequences that depend on order but don't enforce it — steps that can execute out of order or be skipped
- Edge cases the logic doesn't account for (empty collections, zero values, max values, nil/optional paths, first-run states, offline/no-data states)
- Stale or outdated logic that was correct once but no longer matches current models, APIs, or requirements

### Architecture & Design
- Violations of SOLID principles (god classes, tight coupling, leaky abstractions)
- Business logic in the wrong layer (e.g., logic in views, UI in services)
- Duplicated logic that should be extracted (DRY violations)
- Inconsistent patterns — similar things done differently across the codebase
- Missing protocol abstractions where dependency injection is needed
- Overly complex code that could be simplified without losing correctness

### Error Handling & Resilience
- Silent failures — errors caught and swallowed without logging or surfacing
- Missing validation at boundaries (API responses, user input, file reads)
- Crash-prone patterns (force unwraps, unguarded array access, implicit optionals)
- Missing retry logic or timeout handling for network/external calls

### Code Quality & Style
- Poor naming — unclear, misleading, or abbreviated names
- Functions doing too many things or at mixed abstraction levels
- Deep nesting that should use guard clauses / early returns
- Comments explaining "what" instead of "why" (or missing "why" comments)
- Magic numbers/strings that should be named constants or enums
- Unused imports, unused variables, unused parameters

### Concurrency
- Unprotected shared mutable state
- Main-thread-blocking operations (network, disk I/O on main thread)
- Missing @MainActor annotations on UI-mutating code
- Fire-and-forget Tasks that should be structured

### Testing Gaps
- Public functions/types with no test coverage
- Untested error paths and edge cases
- Tests that test implementation details instead of behavior
- Missing mocks for external dependencies

### Dependencies & Configuration
- Hardcoded secrets, API keys, or URLs that should be in config
- Outdated or unused dependencies
- Missing or incorrect access control (public vs internal vs private)

## Output Format

Organize findings by severity:

### 🔴 Critical — Bugs, crashes, data loss, or security issues
### 🟠 High — Architectural problems, missing error handling, race conditions
### 🟡 Medium — Code quality, DRY violations, naming, style issues
### 🔵 Low — Minor improvements, suggestions, nitpicks

For each finding:
1. **File and location** (with line reference)
2. **What's wrong** — concise description of the issue
3. **Why it matters** — impact if left unfixed
4. **Fix** — concrete recommendation or code snippet

After all findings, provide a **Summary** with:
- Total count by severity
- Top 3 most impactful things to fix first
- Overall health assessment of the codebase
