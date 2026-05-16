---
name: arm64-deps-rebuild
description: "Use this skill when native Elixir deps (picosat_elixir, bcrypt_elixir, or any NIF) fail to load with architecture-mismatch errors, or proactively after `mix deps.get` in a fresh worktree on this machine. The shell runs under Rosetta 2 (x86_64) but BEAM is arm64, so default-compiled NIFs are unloadable. This skill documents the rebuild + copy procedure."
---

# arm64 Native Deps Rebuild (Emisint dev machine)

## Why this exists

On this developer's macOS machine:

- The **shell runs under Rosetta 2** (x86_64).
- The **BEAM is native arm64**.
- When `mix deps.compile` invokes `cc` from the Rosetta shell, the compiler defaults to producing **x86_64 binaries**.
- The arm64 BEAM **cannot load x86_64 `.so` files** — you get NIF load errors at runtime, not compile time.

Affected deps are anything with a NIF / native build step. Confirmed offenders:

- `picosat_elixir`
- `bcrypt_elixir`

Other deps (Phoenix, Ash, etc.) are pure Elixir and unaffected.

## Symptom

A test run or `mix phx.server` fails with something like:

- `could not load NIF library: ... mach-o, but wrong architecture`
- `:erlang.load_nif/2 ... :badarg` immediately after a fresh `mix deps.get`
- bcrypt or picosat-related errors despite `mix deps.compile` reporting success

If you see these, the cause is almost certainly arch mismatch. Do not waste time on Hex versions, Postgres, or `mix.lock` — go straight to the fix.

## Fix — first time in a worktree

Run from the worktree root, after `mix deps.get`:

```bash
CC="cc -arch arm64" mix deps.compile picosat_elixir bcrypt_elixir
```

That forces `cc` to emit arm64. The deps now compile correctly into `_build/dev/`.

## Fix — copy `.so` to test build

`_build/test/` has its own copy of compiled deps. After the dev rebuild, copy the freshly-built shared objects across so `mix test` works too:

```bash
# adjust paths if other NIF deps need this
cp _build/dev/lib/picosat_elixir/priv/*.so _build/test/lib/picosat_elixir/priv/
cp _build/dev/lib/bcrypt_elixir/priv/*.so _build/test/lib/bcrypt_elixir/priv/
```

If `_build/test/lib/<dep>/priv/` doesn't exist yet, run `MIX_ENV=test mix deps.compile <dep>` once first (with the same `CC` override) — that creates the directory structure, then copy.

## When to run this

- **Once per worktree, immediately after `mix deps.get`** — proactive, before you hit the error.
- After upgrading either of the affected deps (the new version's NIFs will be x86_64 again).
- After deleting `_build/`.
- Not needed for ordinary edits — already-built `.so` files persist across `mix compile` runs.

## Verifying the fix

```bash
file _build/dev/lib/picosat_elixir/priv/*.so
# should report: Mach-O 64-bit dynamically linked shared library arm64
```

If it still reports `x86_64`, the `CC` override didn't take — check that you actually exported it on the `mix deps.compile` line and that you're rebuilding the right dep.

## What NOT to do

- **Don't** `arch -arm64 mix ...` — the BEAM is already arm64; the issue is the C compiler subprocess, not Elixir.
- **Don't** edit `mix.exs` or pin different versions — versions are fine.
- **Don't** skip the test-env copy. `mix test` will fail in exactly the same way the dev server does.
- **Don't** delete `_build/` to "start fresh" without re-running the `CC` override afterward — you'll just recreate the problem.

## Quick reference

```bash
# Run after every `mix deps.get` in a fresh worktree:
CC="cc -arch arm64" mix deps.compile picosat_elixir bcrypt_elixir
cp _build/dev/lib/picosat_elixir/priv/*.so _build/test/lib/picosat_elixir/priv/ 2>/dev/null || true
cp _build/dev/lib/bcrypt_elixir/priv/*.so _build/test/lib/bcrypt_elixir/priv/ 2>/dev/null || true
```