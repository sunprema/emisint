---
name: ash-multitenancy
description: "Use this skill whenever writing or editing Ash calls (Ash.create/read/update/destroy, Ash.Changeset.for_*, Ash.Query) in this codebase. Almost every resource is attribute-based multitenant on organization_id; getting the tenant pattern wrong is the #1 source of runtime errors. Also consult when defining a new resource that should be tenant-scoped, when wiring AshPaperTrail on a tenant resource, or when writing LiveViews that read tenant data."
---

# Ash Multitenancy (Emisint)

Almost every resource in this project uses **attribute-based multitenancy** keyed on `organization_id`. The rules below are non-negotiable — Ash will not infer the tenant for you, and forgetting it produces either a runtime crash or, worse, a silent cross-tenant leak.

## The core rule

**Always pass `tenant:` as an option on every Ash call.** The attribute on the input map is not enough — Ash uses the `tenant:` option to scope reads, set the attribute on writes, and validate policies.

```elixir
# Correct
Ash.create(Resource, %{...attrs...}, tenant: org_id, authorize?: false)
Ash.read(Resource, tenant: org_id, actor: user)
Ash.update(record, %{...}, tenant: org_id, actor: user)
Ash.Changeset.for_create(Resource, :action, attrs, tenant: org_id)
Ash.Query.for_read(Resource, :read, %{}, tenant: org_id)
```

## What goes where

| Concern | Where it lives |
|---|---|
| Tenant value (org_id) | The `tenant:` option on the call |
| `organization_id` attribute on the row | Set automatically by Ash from `tenant:` |
| Action `accept` list | **Must NOT include `:organization_id`** — Ash sets it for you |
| Input attrs map | **Must NOT include `:organization_id`** — pointless and error-prone |
| Policies | `expr(organization_id == ^actor(:organization_id))` for record→actor comparisons |

If you put `organization_id` in `accept` or in the attrs map, you create two sources of truth. The `tenant:` option always wins; the attribute in attrs is at best ignored, at worst causes confusing validation errors.

## Return shapes (easy to confuse)

- `Ash.create!/2,3` — returns the **bare struct** (raises on error)
- `Ash.create/2,3` — returns `{:ok, struct} | {:error, reason}`
- Same pattern for `read`, `update`, `destroy`

Pick one based on whether the caller needs to handle errors. Don't `{:ok, x} = Ash.create!(...)` — it will not match.

## Common error message → fix

| Error | Cause | Fix |
|---|---|---|
| `changesets require a tenant to be specified` | Ash call without `tenant:` option | Add `tenant: org_id` |
| `cannot accept :organization_id` (or similar policy/changeset oddity) | `:organization_id` in `accept` list | Remove it; Ash sets it from `tenant:` |
| Cross-tenant data appearing in reads | `Ash.read` without `tenant:` | Add `tenant:`. There is no global "all tenants" read — if you genuinely need it, explicitly pass `tenant: nil` and `authorize?: false` and document why. |
| Policy `forbidden` on records the actor owns | Policy uses `actor.organization_id` instead of `^actor(:organization_id)` | Use the pin form inside `expr` |

## LiveView pattern

In every LiveView that reads tenant data:

```elixir
# In handle_params / mount, after the user is loaded
records =
  Resource
  |> Ash.Query.filter(...)
  |> Ash.read!(tenant: user.organization_id, actor: user)
```

Both `tenant:` and `actor:` are required. `tenant:` scopes the query; `actor:` drives policies. Add `require Ash.Query` to any LiveView that uses `Ash.Query.filter/load`.

## Workers and background jobs

Oban workers do not have an automatic actor or tenant. Pass them explicitly:

```elixir
def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
  Resource
  |> Ash.Query.for_read(:by_ids, %{ids: ids}, tenant: org_id, authorize?: false)
  |> Ash.read!()
end
```

`authorize?: false` is acceptable in trusted worker code, but **do not** use it as a way to skip multitenancy — `tenant:` is still required for scoping the query, regardless of authorization.

## AshPaperTrail on a tenant resource

If the resource is multitenant **and** uses `AshPaperTrail.Resource`, you **must** include:

```elixir
paper_trail do
  change_tracking_mode :changes_only
  store_action_name? true
  attributes_as_attributes [:organization_id]
end
```

`attributes_as_attributes [:organization_id]` is required. Without it, the auto-generated `<Resource>.Version` resource fails Ash's multitenancy validation at compile time. The error is not obvious — it surfaces as a Spark validation about the Version resource, not the parent.

Also in the domain:

```elixir
extensions: [AshPaperTrail.Domain]

paper_trail do
  include_versions? true
end
```

This auto-registers all `*.Version` resources so you don't have to list them.

## Defining a new tenant resource — checklist

1. Add `multitenancy do strategy :attribute; attribute :organization_id end` to the resource.
2. Add a `belongs_to :organization, Emisint.Accounts.Organization` (or equivalent).
3. **Do not** put `:organization_id` in any action `accept` list.
4. Policies that compare to the actor: `expr(organization_id == ^actor(:organization_id))`.
5. If using AshPaperTrail, add `attributes_as_attributes [:organization_id]` (see above).
6. Tests must pass `tenant:` on every call — there is no global default.

## Quick mental model

> The `tenant:` option is to Ash what `WHERE org_id = ?` is to raw SQL. You'd never forget the `WHERE` clause; never forget `tenant:`.
