---
name: oban-workers
description: "Use this skill when writing, editing, or testing Oban workers in this codebase (lib/emisint/workers/**, modules with `use Oban.Worker`). Captures the cross-product of Oban + Ash + JSON-serialised job args — each rule below maps to a real runtime error that has bitten this project. Also consult when adding a new queue, configuring Oban, or wiring up Oban tests."
---

# Oban Workers (Emisint)

Workers in this project sit at the intersection of three things that each have their own gotchas: Oban (job lifecycle + JSON args), Ash (queries, multitenancy, bulk ops), and ExUnit (Oban.Testing macros). Each rule below comes from a real runtime error.

## 1. Always `require Ash.Query`

`use Oban.Worker` does **not** import Ash macros. The pin operator inside a filter looks like Elixir but is a macro:

```elixir
defmodule MyWorker do
  use Oban.Worker, queue: :data_ingestion
  require Ash.Query   # <-- without this, the `^ids` below fails to compile

  def perform(%Oban.Job{args: %{"ids" => ids}}) do
    Resource
    |> Ash.Query.filter(id in ^ids)   # macro — needs `require Ash.Query`
    |> Ash.read!(tenant: org_id, authorize?: false)
  end
end
```

Symptom without `require`: a confusing compile-time error pointing at the `^` pin.

## 2. `Ash.Query.filter` does NOT support `field in ^list`

This is the single most common Ash trap inside workers. Elixir's parser rejects `in` as a binary operator combined with a runtime-pinned list — `field in ^ids` will not parse the way you want inside `Ash.Query.filter`.

**Wrong:**
```elixir
Ash.Query.filter(Resource, id in ^ids)   # parser error / does not work
```

**Right — define a named read action and pin via `arg`:**

```elixir
# in the resource
read :by_ids do
  argument :ids, {:array, :uuid}, allow_nil?: false
  filter expr(id in ^arg(:ids))
end
```

```elixir
# in the worker
Resource
|> Ash.Query.for_read(:by_ids, %{ids: ids}, tenant: org_id)
|> Ash.read!(authorize?: false)
```

Note: `expr(field in ^arg(:ids))` works fine; only the `Ash.Query.filter(... in ^var)` form is broken.

## 3. `Ash.bulk_create` with `upsert? true` requires explicit `upsert_fields`

Without `upsert_fields:`, Ash raises an `ArgumentError` at runtime — not at compile time, so it won't be caught by `mix compile`.

```elixir
Ash.bulk_create(
  rows,
  Resource,
  :upsert_action,
  upsert?: true,
  upsert_fields: [:score, :scored_at, :updated_at],   # REQUIRED
  tenant: org_id,
  authorize?: false,
  return_errors?: true
)
```

Pick the fields that should be overwritten on conflict. Don't use `:replace_all` blindly — it will overwrite tenant/foreign-key columns and bypass the point of upsert.

## 4. JSON round-trip turns atom keys into strings

Job args are serialised to JSONB. Atom keys in `args` come back as **string keys** in `perform/1`. Same for any `:map` type attribute on a resource.

```elixir
# Enqueue
%{organization_id: org_id, ids: ids} |> MyWorker.new() |> Oban.insert()

# In perform — keys are strings, not atoms
def perform(%Oban.Job{args: %{"organization_id" => org_id, "ids" => ids}}) do
  ...
end
```

Pattern-match on string keys. Never write `args.organization_id` or `args[:organization_id]` in `perform/1` — both will return `nil`.

For `:map` attributes on a resource, same rule: read with `map["key"]`, not `map.key`, in any code that reads the persisted value back. Test assertions in particular need to match string keys.

## 5. Workers carry no actor or tenant — pass them explicitly

There's no `current_user` in a worker. Every Ash call needs `tenant:` and (if relevant) `actor:`:

```elixir
Resource
|> Ash.Query.for_read(:by_ids, %{ids: ids}, tenant: org_id)
|> Ash.read!(authorize?: false)
```

`authorize?: false` is acceptable in trusted worker code, but it does **not** replace `tenant:` — `tenant:` is required for query scoping regardless of authorization. (Consult the `ash-multitenancy` skill for the full ruleset.)

The org_id should arrive in the job args from the caller — never look it up "globally."

## 6. `perform_job` is an Oban.Testing macro — don't shadow it

In tests:

```elixir
use Oban.Testing, repo: Emisint.Repo
```

This defines a `perform_job/2,3` macro. If you write a test helper called `perform_job`, it silently shadows the macro and tests start behaving oddly (or stop running the job at all).

**Convention:** name local helpers `run_worker/2` or similar. Reserve `perform_job` for the Oban macro.

## 7. Oban config layout

- `config/config.exs`:
  ```elixir
  config :emisint, Oban,
    queues: [default: 10, data_ingestion: 5, analytics: 5],
    repo: Emisint.Repo
  ```
- `config/test.exs`: `testing: :manual` — jobs are inserted but not run; tests drain or invoke them explicitly.

When adding a new queue, add it in `config.exs` and choose the worker's `queue:` option to match. Mismatched queue names cause jobs to sit in the queue forever with no error.

## Worker template (canonical shape)

```elixir
defmodule Emisint.Workers.MyWorker do
  use Oban.Worker, queue: :data_ingestion, max_attempts: 3
  require Ash.Query

  alias Emisint.SomeDomain.SomeResource

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => org_id, "ids" => ids}}) do
    SomeResource
    |> Ash.Query.for_read(:by_ids, %{ids: ids}, tenant: org_id)
    |> Ash.read!(authorize?: false)
    |> do_work(org_id)

    :ok
  end

  defp do_work(records, org_id), do: ...
end
```

## Test template

```elixir
defmodule Emisint.Workers.MyWorkerTest do
  use Emisint.DataCase
  use Oban.Testing, repo: Emisint.Repo

  test "processes ids" do
    args = %{"organization_id" => org.id, "ids" => [a.id, b.id]}
    assert :ok = perform_job(Emisint.Workers.MyWorker, args)
    # assertions on side effects
  end
end
```

Use `perform_job/2` directly — it's the Oban.Testing macro. No need for a custom helper.

## Quick checklist when writing a new worker

- [ ] `require Ash.Query` at the top
- [ ] `queue:` matches a queue in `config.exs`
- [ ] `perform/1` matches **string** keys in args
- [ ] All Ash calls pass `tenant:` (and `authorize?: false` if appropriate)
- [ ] Any `id in [list]` filter uses a named read action with `^arg(:ids)`, not `Ash.Query.filter(... in ^ids)`
- [ ] Any `Ash.bulk_create(..., upsert?: true)` includes `upsert_fields: [...]`
- [ ] Test file uses `use Oban.Testing, repo: Emisint.Repo` and calls `perform_job/2` directly