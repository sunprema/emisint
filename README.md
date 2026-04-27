# Emisint

A SaaS platform for Michigan Charter School Management Companies (EMOs) and
Authorizers. The **Academic Performance Module (APM)** ingests state data from
the Michigan Department of Education (MDE) and provides real-time visibility
into student achievement, contractual compliance (Schedule 7-1), and
state-level accountability.

**Target users**

- **EMO Academic Officers** — monitor a portfolio of schools against contract
  goals and identify schools needing intervention.
- **Authorizer Liaisons** — verify Academies are meeting the legal academic
  requirements defined in their charter contracts.
- **School Principals** — drill into grade-level and subgroup data to adjust
  instructional strategies.

## Tech stack

- **Phoenix 1.8** + **LiveView 1.1** on **Bandit**
- **Ash Framework 3.x** with `AshPostgres`, `AshAuthentication`,
  `AshAuthenticationPhoenix`, `AshPaperTrail`, `AshStateMachine`, `AshOban`,
  `AshAdmin`, `AshCsv`
- **PostgreSQL** (default port `5433` in development)
- **Oban** for background jobs (with **Oban Web** UI)
- **DaisyUI** + **Tailwind** for styling, **esbuild** for JS
- **Imprintor** (Typst) for PDF report generation
- **ExAws** / **ExAws.S3** for object storage
- **Fly.io** for deployment (`fly.toml` provided)

## Domains

Ash domains registered in `config/config.exs`:

| Domain                | Purpose                                                                                                                                              |
| :-------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Emisint.Accounts`    | Tenancy and identity — `Organization`, `User`, `Token`, `ApiKey`. Multitenancy is attribute-based on `organization_id`.                              |
| `Emisint.Assessments` | MDE data ingestion and storage — entity master, ISDs, districts, buildings, public assessment results, SAT, school index, enrollment, comparisons.   |
| `Emisint.Chat`        | Conversational/AI chat surface backed by `ash_ai`.                                                                                                   |

See `CLAUDE.md` for the broader architectural intent (additional `Registry`,
`Compliance`, and `Analytics` domains are described there as planned/in-flight
work — refer to `PLAN.md` for status).

## Prerequisites

- Elixir `~> 1.15` and a matching Erlang/OTP
- PostgreSQL running on `localhost:5433`
- No system Node required — `esbuild` and `tailwind` are managed by Mix

## Getting started

```bash
mix setup           # deps.get + ash.setup + assets + seeds
mix phx.server      # http://localhost:4000
```

Or inside IEx:

```bash
iex -S mix phx.server
```

## Common commands

```bash
mix test                     # full suite (runs `ash.setup --quiet` first)
mix test path/to/test.exs    # single file
mix test path/to/test.exs:42 # single test at line

mix format                   # Styler + Spark + Tailwind + HEEx
mix dialyzer                 # static analysis
mix precommit                # warnings-as-errors + unlock unused + format + test

mix ash.setup                # migrations + Ash introspection
mix ash.codegen <name>       # generate migration for resource changes
mix ash.migrate              # run migrations
mix ash.reset                # drop, create, migrate, seed
```

## Project layout

```
lib/
  emisint/
    accounts/        # Organization, User, Token, ApiKey
    assessments/     # MDE entity master, districts, buildings,
                     # public assessment / SAT / school-index results,
                     # enrollment, comparison snapshots, importers
    chat/            # AI-backed chat
    reports/         # portfolio + school report orchestration
    workers/         # Oban workers for MDE imports and snapshots
    storage.ex       # S3 / object-storage adapter
    application.ex   # supervision tree
  emisint_web/
    live/
      admin/         # org context, organizations, users, data import, history
      dashboard/     # portfolio dashboard
      mde/           # MDE overview, district analysis, entity master
      chat_live.ex
      settings_live.ex
      pending_live.ex
priv/
  repo/              # migrations + seeds.exs
  typst/             # PDF templates: portfolio/, school/
config/              # config.exs, dev.exs, test.exs, runtime.exs
```

## Background jobs

Oban runs MDE ingestion and snapshot jobs. Workers live in
`lib/emisint/workers/`:

- `MdeImportWorker` — generic MDE result importer
- `MdeEnrollmentImportWorker` — enrollment/demographics
- `MdeSatImportWorker` — SAT results
- `MdeSchoolIndexImportWorker` — state school-index results
- `EntityMasterImportWorker` — MDE entity master (ISDs, districts, buildings)
- `MdeComparisonSnapshotWorker` — pre-aggregated comparison snapshots

Oban Web is mounted in the router for queue inspection.

## Reports

PDF reports are rendered via [Imprintor](https://hex.pm/packages/imprintor)
(Typst). Templates live under `priv/typst/`:

- `priv/typst/portfolio/` — portfolio-level reports
- `priv/typst/school/` — per-school reports (e.g. `school_vs_lea`)

When passing data from Elixir into Typst, coerce types explicitly — booleans
and numbers arrive as strings, and `nil` arrives as the string `"nil"`. See
`CLAUDE.md` for the full Typst guidance.

## Deployment

The repo is configured for **Fly.io** (`fly.toml`, `Dockerfile`, `rel/`).
Default app is `emisint` in the `dfw` region; the release command runs
migrations on boot.

```bash
fly deploy
```

For Phoenix-generic deployment guidance, see
[the official deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Conventions

- **Commits**: `type(scope): description` (e.g. `feat(batching): ...`,
  `fix(orders): ...`, `ui(production): ...`).
- **Formatting**: `mix format` runs Styler, `Spark.Formatter` (Ash DSL section
  ordering), `TailwindFormatter`, and `Phoenix.LiveView.HTMLFormatter`.
- **Multitenancy**: every Ash call against a tenant resource must pass
  `tenant: organization_id` — the attribute alone is not enough.

## Further reading

- `CLAUDE.md` — architectural intent, domain model, coding conventions
- `PLAN.md` — implementation phases and progress
- `PERCENT_MET_RULES.md` — Schedule 7-1 evaluation rules
- `db_optimization.md` — performance/indexing notes
- `new_features.md` — in-flight feature notes
