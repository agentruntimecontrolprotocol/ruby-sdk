# Idiomatic Ruby Style Guide for Public SDKs

Authoritative style for gems intended for public consumption. Optimized for
readability, predictable public API surface, and Claude Code consumption.

When this guide conflicts with personal taste, this guide wins. When it
conflicts with RuboCop defaults, this guide wins and the cop gets configured.

---

## Hard Limits (Non-Negotiable)

- Line length: aspire **80**, hard cap **100**.
- Method length: **10 lines** (excluding `def`/`end`).
- Class length: **100 lines** (excluding comments).
- Module length: **100 lines**.
- File length: **200 lines**.
- Cyclomatic complexity: **6** per method.
- Perceived complexity: **7** per method.
- ABC size: **17** per method.
- Block nesting: **3** levels.
- Method parameters: **4** (use keyword args or a `Data`/`Struct` beyond).
- Module nesting: **3** levels deep.

When a limit is breached, **refactor — do not configure the linter to allow
exceptions**. Excess size is a design smell, not a formatting problem.

---

## File Organization

- One class or module per file. No exceptions for "small helpers".
- Filename mirrors the constant: `MyGem::HTTPClient` lives at
  `lib/my_gem/http_client.rb`.
- `lib/my_gem.rb` is the entry point and does nothing but `require` and
  define the top-level module.
- `lib/my_gem/version.rb` holds `VERSION = "x.y.z"` and nothing else.
- Use Zeitwerk for autoloading in any non-trivial gem.
- Group by domain, not by type. Prefer `lib/my_gem/billing/invoice.rb` over
  `lib/my_gem/models/invoice.rb`. Domain folders scale; type folders don't.

## Magic Comments

Every `.rb` file starts with:

```ruby
# frozen_string_literal: true
```

No exceptions. Add it to generators, templates, and rake tasks too.

---

## Naming

- `snake_case` for methods, variables, and files.
- `CamelCase` for classes and modules.
- `SCREAMING_SNAKE_CASE` for constants.
- Predicate methods end with `?` and return strict booleans where possible.
- Bang methods (`!`) signal mutation, danger, or raise-on-failure. Always
  pair with a non-bang version unless raising is the only sensible behavior.
- Avoid `get_` and `set_` prefixes. Use attribute accessors.
- Spell names out. Abbreviate only when the abbreviation is more recognizable
  than the word (`url`, `http`, `id`, `db`).
- Boolean attributes read as questions: `active?`, not `is_active`.
- Collection variables are plural: `users`, not `user_list`.

---

## Module & Class Design

- Wrap every public symbol in your top-level gem module.
- Prefer composition over inheritance. Inherit at most one level deep unless
  modeling a genuine is-a hierarchy.
- Use `Module` for namespacing and stateless helpers. Use `Class` for objects
  that carry state.
- Mix in `Comparable` / `Enumerable` instead of reimplementing their
  contracts.
- Freeze public constants: `DEFAULT_TIMEOUT = 30` then `.freeze` mutable
  literals (arrays, hashes, strings without the magic comment).
- For value objects, prefer `Data.define` (Ruby 3.2+) or `Struct` over
  hand-rolled classes with `attr_reader` boilerplate.
- A class with only class methods is a module. Convert it.

---

## Method Design

- One method, one responsibility. If the name needs "and", split it.
- Required positional args come first, then keyword args.
- Use keyword arguments when a method has 3+ parameters, **or** any boolean
  parameter (positional booleans are always wrong).
- Return meaningful values. Avoid returning `self` unless chaining is part
  of the documented public API.
- No side effects in predicate methods.
- Methods that can fail in expected ways either return a result object or
  raise a domain-specific error. Do not return `nil` ambiguously.

```ruby
# Good
def find_user(id:)
  repo.fetch(id) or raise NotFoundError, "User #{id} not found"
end

# Bad
def find_user(id)
  repo.fetch(id) # returns nil on miss — caller has to guess
end
```

---

## Error Handling

Define an error hierarchy rooted at one class so consumers can rescue a
single type:

```ruby
module MyGem
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end
  class RateLimitError < APIError; end
  class NotFoundError < APIError; end
end
```

- Every gem-raised error inherits from `MyGem::Error`.
- Never `rescue Exception`. Never `rescue` bare.
- Rescue the narrowest class that handles the case.
- Error messages include actionable context: IDs, URLs, expected vs got.
- Do not swallow errors silently. If suppression is required, log via a
  configurable logger.
- Do not raise from initializers unless construction is genuinely
  impossible.

---

## Public API Discipline

- Mark every method `public`, `private`, or `protected` explicitly in any
  class that has non-public methods.
- Tag internal-but-reachable methods with `# @api private` (YARD).
- Public constants are frozen and documented.
- Keep the public surface small. Each new public method is a permanent
  maintenance commitment.
- Do not monkey-patch core classes from a published gem. Use refinements
  only when unavoidable, scoped to the smallest file possible.
- Never modify `Object`, `Kernel`, `Class`, or `Module`.

---

## Configuration

Single block-based entry point:

```ruby
MyGem.configure do |c|
  c.api_key = ENV.fetch("MY_GEM_KEY")
  c.timeout = 10
end
```

- Validate at configure time. Fail loudly on missing required keys.
- Freeze the config object after the block returns.
- Provide sensible defaults for every optional setting.
- Expose `MyGem.configuration` as a frozen reader, never a writer.

---

## Dependencies

- Minimize runtime dependencies. Each one constrains downstream users.
- Pin minimum versions (`~> 2.0`). Never pin maximum versions unless a known
  break exists.
- Lazy-require optional dependencies inside the method that uses them and
  raise a clear error if missing.
- Development dependencies go in the Gemfile, not the gemspec.

---

## Idioms to Prefer

- `Array(value)` — nil-safe wrap.
- `Hash#dig` — nested access without nil checks.
- `Object#then` / `yield_self` — readable transformations.
- `Object#tap` — side effects mid-chain.
- Safe navigation `&.` — one level only. Chains of `&.` hide design
  problems.
- Pattern matching (`case/in`) for structural conditionals on Ruby 3+.
- `Set` over `Array#include?` for membership when the collection grows past
  ~10 elements.
- `String#<<` over `+=` in loops.
- Heredocs with `<<~` (squiggly) for multiline strings.
- `each_with_object` over `inject` when accumulating into a mutable
  collection.
- Memoize with `@x ||= compute` **only when** the value cannot legitimately
  be `nil` or `false`. Otherwise use
  `defined?(@x) ? @x : (@x = compute)`.

---

## Anti-Patterns (Forbidden)

- Class variables (`@@var`). Use class instance variables or a registry.
- Global variables (`$var`) outside genuine globals (`$stdout`, `$stderr`).
- `method_missing` without a paired `respond_to_missing?`.
- `eval`, `class_eval` with strings, `instance_eval` with strings.
- `rescue Exception` or bare `rescue`.
- Rescuing in initializers.
- `alias_method_chain`-style wrapping. Use `Module#prepend`.
- Monkey-patching core classes from a published gem.
- Long parameter lists hidden as `**opts` with no documentation.
- Returning different shapes from the same method (`String` or `nil` or
  `Array`). Pick one return type and stick to it.
- `def self.method` scattered through a class. Group under
  `class << self`.

---

## Documentation

- Every public class, module, and method has a YARD docstring.
- Document `@param`, `@return`, `@raise`, and provide at least one
  `@example` for non-trivial methods.
- Keep `README.md` runnable: every snippet must execute against the current
  version. CI should verify this where practical.
- Maintain `CHANGELOG.md` following the Keep a Changelog format.
- Document breaking changes prominently and bump major versions.

---

## Testing

- One test framework per gem. RSpec or Minitest, not both.
- Test the public API exclusively. Private methods are tested through their
  callers.
- One logical assertion per test where practical. Group with
  `aggregate_failures` (RSpec) when assertions are about one outcome.
- Stub external HTTP with WebMock or VCR.
- Run tests under the lowest and highest supported Ruby versions in CI.
- No `sleep` in tests. Use proper synchronization or time travel.

---

## RuboCop Baseline

Ship `.rubocop.yml` with:

```yaml
AllCops:
  NewCops: enable
  TargetRubyVersion: 3.1
  SuggestExtensions: false

Layout/LineLength:
  Max: 100

Metrics/MethodLength:
  Max: 10
Metrics/ClassLength:
  Max: 100
Metrics/ModuleLength:
  Max: 100
Metrics/BlockLength:
  Max: 15
Metrics/AbcSize:
  Max: 17
Metrics/CyclomaticComplexity:
  Max: 6
Metrics/PerceivedComplexity:
  Max: 7
Metrics/ParameterLists:
  Max: 4
  CountKeywordArgs: false

Style/Documentation:
  Enabled: true
Style/FrozenStringLiteralComment:
  EnforcedStyle: always
```

Treat violations as build failures. Refactor first. Disable a cop only with
an inline comment justifying the exception.

---

## Reducing Complexity (Refactor Patterns)

When a method exceeds limits, apply these in order:

1. **Extract Method.** Pull cohesive lines into a named private method.
2. **Replace Conditional with Polymorphism.** A long `case` on a type
   becomes classes implementing a shared interface.
3. **Introduce Parameter Object.** Group related params into `Data` or
   `Struct`.
4. **Replace Temp with Query.** Turn intermediate variables into methods.
5. **Decompose Conditional.** Extract the predicate AND each branch into
   named methods.
6. **Move Method.** If a method uses another object's data more than its
   own, it belongs there.
7. **Replace Loop with Pipeline.** Chain `map` / `select` / `reduce`
   instead of stateful loops.
8. **Guard Clauses.** Replace nested `if` with early returns.

If a class breaches 100 lines, look for a second class trying to escape.
Most overlong classes are hiding a collaborator. Names that signal this:
`*Manager`, `*Handler`, `*Processor`, `*Helper`, `*Utils`.

If a file breaches 200 lines, the class inside has already breached the
class limit. Fix the class, the file follows.

---

## Quick Checklist Before Merge

- [ ] `# frozen_string_literal: true` on every file.
- [ ] No file > 200 lines, no class > 100, no method > 10.
- [ ] No line > 100 chars; most lines ≤ 80.
- [ ] Every public method has a YARD docstring.
- [ ] Every gem-raised error inherits from `MyGem::Error`.
- [ ] No `@@`, no bare `rescue`, no `rescue Exception`.
- [ ] No monkey patches of core classes.
- [ ] RuboCop exits 0.
- [ ] All tests pass on min and max supported Ruby.
- [ ] CHANGELOG updated. Breaking changes flagged.
