# Bulletproof

Bulletproof detects ActiveRecord memory problems caused by over-eager `includes`.

- **Static analysis** — Scans Ruby source files and flags `includes` calls that load unbounded record sets
- **Runtime monitoring** — Measures actual record counts and GC pressure per request, and warns when thresholds are exceeded

## Installation

```ruby
# Gemfile
gem "bulletproof", group: :development
```

```sh
bundle install
```

---

## Static Analysis

### CLI

```sh
# Analyze a directory
bundle exec bulletproof app/

# Analyze a single file
bundle exec bulletproof app/models/user.rb

# Override thresholds
bundle exec bulletproof app/ --max-includes-depth 3 --max-associations 5
```

**Output (violations found):**

```
[WARNING] app/models/post.rb:12 — nesting depth 3 (limit: 2), no record-limiting method (limit / find, etc.) in chain
[WARNING] app/controllers/users_controller.rb:45 — 4 associations (limit: 3), no record-limiting method in chain

2 violation(s) found.
```

**Output (clean):**

```
No violations found.
```

The exit code is `0` when clean and `1` when violations are found, making it easy to integrate into CI.

### Programmatic usage

```ruby
report = Bulletproof.analyze("app/")

if report.ok?
  puts "No violations found."
else
  report.violations.each do |v|
    puts "[#{v.severity.upcase}] #{v.file}:#{v.line} — #{v.message}"
  end
end
```

### How detection works

A call to `includes` is only flagged when **both** conditions are true:

1. The nesting depth or association count exceeds the configured threshold
2. No record-limiting method (`limit`, `find`, `first`, `page`, etc.) appears anywhere in the method chain

```ruby
# Flagged — unbounded full-table load
User.includes(posts: { comments: :author }).all
Post.includes(:user, :comments, :tags, :likes)

# Safe — record count is bounded
User.includes(posts: { comments: :author }).limit(10)
User.includes(posts: { comments: :author }).page(1).per(20)
```

---

## Runtime Monitoring (Rails)

### Setup

```ruby
# config/initializers/bulletproof.rb
Bulletproof.configure do |c|
  c.enabled = Rails.env.development?

  # ---- Thresholds ----------------------------------------------------------

  # Max records loaded at once per model (default: 1_000)
  c.max_records_per_model = 1_000

  # Max total records loaded across all models per request (default: 5_000)
  # find_each / in_batches loads are excluded from this count
  c.max_total_records = 5_000

  # Max GC runs per request (default: nil = disabled)
  # GC frequency varies widely between apps; set explicitly if needed
  # c.max_gc_runs_per_request = 10

  # ---- Notifiers -----------------------------------------------------------

  # Log to Rails.logger.warn (default: true)
  c.rails_logger = true

  # Inject console.warn into HTML responses (default: true)
  # Visible in the browser's Console tab (F12)
  c.console = true

  # Inject a floating overlay panel into HTML responses (default: false)
  # Visible on the page without opening DevTools
  c.alert = true

  # Append warnings to a log file (default: nil = disabled)
  # c.log_file = Rails.root.join("log/bulletproof.log").to_s

  # Custom notifier callable — for Slack, etc. (default: nil = disabled)
  # c.notifier = ->(w) { SlackNotifier.ping(w.message) }
end
```

Setting `enabled = true` causes the Railtie to automatically insert the Rack middleware. You do not need to call `config.middleware.use` manually.

### Notifiers

| Key | Default | Description |
|---|---|---|
| `rails_logger` | `true` | Calls `Rails.logger.warn` for each warning |
| `console` | `true` | Injects `console.warn` before `</body>`. Visible in the browser Console tab |
| `alert` | `false` | Injects a floating overlay panel before `</body>`. Dismissible with ✕ |
| `log_file` | `nil` (disabled) | Appends timestamped warnings to the specified file path |
| `notifier` | `nil` (disabled) | Callable receiving a `RuntimeWarning`. Use for Slack, webhooks, etc. |

### Warning output example

```
[Bulletproof] Post: loaded 5,200 records at once (limit: 1,000)
  → app/controllers/posts_controller.rb:15:in 'index'

[Bulletproof] Total records loaded in this request: 7,800 (limit: 5,000) [Post: 5,200, Comment: 2,600]
```

### Warning types

| Type | Condition | Related config key |
|---|---|---|
| `:mass_instantiation` | A single model loaded more than `max_records_per_model` records in one batch | `max_records_per_model` |
| `:high_total_records` | Total records across all models exceeded `max_total_records` (batch loads excluded) | `max_total_records` |
| `:gc_pressure` | GC ran more than `max_gc_runs_per_request` times during the request | `max_gc_runs_per_request` |

### `find_each` / `in_batches`

Batch processing is intentional and memory-safe, so Bulletproof does not warn on it.

```ruby
# No warning — find_each loads records in bounded batches
Post.find_each(batch_size: 500) { |post| process(post) }

# Warning — all records loaded into memory at once
Post.all.to_a
```

### How it works

Bulletproof subscribes to the `instantiation.active_record` ActiveSupport notification for the duration of each request. It accumulates record counts per model and uses `caller_locations` to identify the application code line responsible for each load. Subscription is scoped to the current thread via `Thread.current`, so parallel requests in multi-threaded servers (e.g. Puma) do not interfere with each other.

---

## Configuration reference

| Key | Default | Description |
|---|---|---|
| `enabled` | `false` | Enable runtime monitoring |
| `max_includes_depth` | `2` | Static: max `includes` nesting depth |
| `max_associations` | `3` | Static: max associations per `includes` call |
| `max_records_per_model` | `1_000` | Runtime: max records loaded at once per model |
| `max_total_records` | `5_000` | Runtime: max total records per request (batch loads excluded) |
| `max_gc_runs_per_request` | `nil` (disabled) | Runtime: max GC runs per request |
| `rails_logger` | `true` | Notifier: output to `Rails.logger.warn` |
| `console` | `true` | Notifier: inject `console.warn` into HTML |
| `alert` | `false` | Notifier: inject overlay panel into HTML |
| `log_file` | `nil` (disabled) | Notifier: append to log file |
| `notifier` | `nil` (disabled) | Notifier: custom callable receiving `RuntimeWarning` |

---

## Requirements

- Ruby 3.0+
- Rails 6.0+ (runtime monitoring only)

## License

[MIT License](LICENSE.txt)
