# Contributing

## Environment

- Use Ruby `3.4.8`.
- This repository includes both `.ruby-version` and `.tool-versions`.
- If your shell does not activate the project Ruby automatically, make sure
  your version manager does before running Bundler commands. With `asdf`, use
  `asdf exec bundle exec ...` as a fallback.

## Setup

1. `bundle install`
2. Install `lefthook` if you do not already have it.
3. `lefthook install`

## Local checks

Run these before opening a pull request:

- `bundle exec rubocop`
- `bundle exec rspec`
- `bundle exec bundle-audit check --update`
- `bundle exec yard --fail-on-warning`
- `bundle exec rake`

`spec/spec_helper.rb` enforces a minimum SimpleCov line coverage floor. If a
refactor reduces coverage, add or fix tests in the same change.

## Change discipline

- Preserve public behavior unless the change is explicitly approved.
- Read the implementation, its tests, and its callers before refactoring.
- Keep commits single-purpose and easy to review.
- Log architectural follow-up work in `REFACTOR_BACKLOG.md` instead of mixing
  design changes into an idiom pass.
