# Copilot Instructions

## Libraries & Dependencies
- Use well-maintained public libraries wherever they simplify the codebase, improve resilience, or reduce code we must maintain. Do not reinvent the wheel.
- Research available libraries before implementing non-trivial functionality from scratch.
- Do not offload things that don't make sense as dependencies (trivial helpers, core business logic), but do for everything else that makes the code simpler, more resilient, or more lightweight.

## Code Quality
- Code must be clean, scalable, and maintainable. Never take the easy route — always take the correct route for long-term maintainability and scale.
- Complexity is not a blocker. If the right solution is complex, implement it correctly rather than cutting corners.
- Follow DRY (Don't Repeat Yourself) — extract shared logic into reusable functions, protocols, or modules.
- Follow SOLID principles:
  - **S**ingle Responsibility: each type/function does one thing.
  - **O**pen/Closed: extend behavior without modifying existing code.
  - **L**iskov Substitution: subtypes must be substitutable for their base types.
  - **I**nterface Segregation: prefer small, focused protocols over large ones.
  - **D**ependency Inversion: depend on abstractions, not concrete implementations.

## Naming & Readability
- Names are documentation. Use clear, descriptive names that make comments unnecessary. If a name needs a comment to explain it, rename it.
- Comments explain **why**, never **what**. The code itself should make the "what" obvious.
- Keep functions short and at a single level of abstraction. If a function does setup, processing, and cleanup — split it into three.
- Use guard clauses and early returns to avoid deep nesting. Flat code is readable code.

## Type Safety
- Leverage the type system to make invalid states unrepresentable. Use enums over raw strings/ints, strong types over primitives (e.g., `UserID` over `String`).
- Prefer compile-time guarantees over runtime checks wherever possible.

## Testing — Non-Negotiable
- **A feature is not done until its tests are written, run, and passing.** Never claim a feature is implemented without this.
- Write tests for every new feature, every bug fix, and every non-trivial change. No exceptions.
- Cover the happy path, edge cases, error/failure paths, and boundary conditions. Aim for coverage that makes bugs nearly impossible.
- Tests must be **run** (not just written) before considering work complete. If tests cannot be run in the current environment, flag it explicitly.
- Write tests first (TDD) when the requirements are clear. When exploring, write tests immediately after the implementation solidifies — but always before calling it done.
- Test behavior, not implementation details. Tests should survive refactors without rewriting.
- Use mocks/stubs for external dependencies (network, database, file system) so tests are fast, deterministic, and isolated.
- If existing code lacks tests, add them before modifying that code. Never make untested code worse.

## Testability & Dependency Injection
- Design every component to be testable. Inject dependencies through initializers or protocols — never reach for global singletons directly.
- If something is hard to test, that's a design smell. Refactor until it's easy to test.

## Error Handling
- Fail fast and fail loud. Surface errors early with clear, actionable messages. Do not silently swallow failures.
- Use assertions and preconditions for programmer errors; use proper error types for runtime failures.
- Handle errors at the right layer. Low-level code throws; high-level code catches and presents.

## Defensive Boundaries
- Validate all external input at the boundary (API responses, user input, file reads). Once validated, trust the data internally — don't scatter validation everywhere.
- Never force-unwrap or force-cast outside of tests. If it can fail, handle the failure.

## Concurrency
- All concurrent/async code must be data-race safe. Use actors, structured concurrency, or other concurrency primitives appropriate to the language — never unprotected shared mutable state.
- Prefer structured concurrency patterns (task groups, async/await) over unstructured fire-and-forget patterns.

## Logging & Observability
- Add structured logging at meaningful points: operation start/end, error paths, state transitions. Logs should tell the story of what happened when debugging after the fact.
- Use appropriate log levels (debug, info, warning, error). Do not log noise.

## Git & Change Hygiene
- Each change should do one thing. If a refactor is needed to enable a feature, do the refactor in a separate commit first.
- Write commit messages that explain **why** the change was made, not just what files were touched.

## Problem-Solving Approach
- Research thoroughly before implementing. Look into best practices, existing solutions, and relevant libraries.
- If the answer is unclear after a few iterations, stop and debug collaboratively with the user rather than spinning endlessly.
- When fixing a bug, find the root cause first. Never patch symptoms — understand why it broke, then fix it at the source.
- Before adding new code, check if existing code already handles or nearly handles the case. Extend before you create.

## Ripple-Through Changes
- When making a change, trace its impact across the entire codebase. Update every caller, every test, every related component. Do not leave stale references or orphaned code.
- Do not add backward-compatibility shims, adapters, or deprecation wrappers. If something needs to change, change it everywhere — rewrite, refactor, and overhaul as necessary.
- A change is not complete until the whole codebase is consistent with it. Partial migrations are worse than no migration.
