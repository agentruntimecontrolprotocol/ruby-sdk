# Style

This repository defaults to the Ruby Style Guide and RuboCop on Ruby `3.4`.
When code and the linter disagree, preserve behavior first and make the
smallest idiomatic change that keeps the test suite green.

## Baseline

- Prefer guard clauses over nested conditionals.
- Prefer `Data.define`, pattern matching, and endless methods when they improve
  clarity without hiding control flow.
- Prefer explicit, boring enumerables over clever `reduce` chains.
- Prefer immutable values and non-mutating collection operations unless a
  measured reason exists to mutate in place.
- Keep comments focused on protocol rationale, edge cases, and tradeoffs, not
  on restating the code.

## Documented deviations

- `Style/Documentation` is disabled.
  Rationale: public API and protocol behavior are documented in README, RFC
  notes, and YARD where they add value; blanket top-level comments are not
  required on every class and module.

- `Layout/LineLength` is `110`, with specs excluded.
  Rationale: protocol envelopes and structured payloads stay readable at 110
  columns without forcing noisy line wrapping.

- Metrics cops are intentionally looser than guide defaults.
  Rationale: runtime and protocol orchestration objects are allowed to stay
  cohesive even when they exceed toy-size limits. Large objects should still be
  logged in `REFACTOR_BACKLOG.md` instead of being split opportunistically.

- `Naming/MethodParameterName` allows short names like `id`, `a`, `b`, and `kw`.
  Rationale: narrow protocol ids and tiny block-local destructuring do not
  benefit from invented longer names.

- `Naming/PredicateMethod` is disabled.
  Rationale: a few manager command methods return a success boolean to report
  whether a state transition occurred. Renaming those command verbs to `?`
  forms would misdescribe their side effects.

- `RSpec/MultipleDescribes` is disabled.
  Rationale: integration and protocol scenario specs are easier to scan when
  top-level groups describe the scenario directly.

- `RSpec/SpecFilePathFormat` is disabled.
  Rationale: specs are organized by test layer (`unit`, `integration`, `e2e`)
  rather than mirroring the source tree exactly.

- `Style/ClassAndModuleChildren` uses nested style.
  Rationale: nested namespaces read cleanly with the protocol's split files and
  avoid churn around compact namespace syntax.
