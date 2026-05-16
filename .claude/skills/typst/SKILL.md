---
name: typst
description: "Use this skill when working with Typst PDF templates that receive data from Elixir/JSON (e.g. priv/typst/**). Covers type coercion for booleans and numbers — the #1 source of runtime errors in this codebase."
---

# Typst + Elixir/JSON Templates

Typst templates in this project receive data passed from Elixir (usually via JSON). After the JSON round-trip, **types do not survive**. This is the dominant source of runtime errors in PDF generation. Always coerce at the boundary.

## Boolean coercion

Booleans arrive as the **strings** `"true"` / `"false"`, not Typst booleans. Default param values do not save you — a string caller still triggers a type error.

Coerce at the top of every function that accepts a boolean from Elixir:

```typst
#let my-func(approximate: false) = {
  let approximate = if type(approximate) == str { approximate == "true" } else { approximate }
  // ... safe to use `approximate` as a real boolean from here
}
```

## Numeric coercion (the big one)

All numbers arrive as **strings** after JSON round-trip:
- Floats become strings like `"42.5"` — `calc.round("42.5")` throws *"expected integer, float, or decimal, found string"*.
- Elixir `nil` becomes the **string** `"nil"` — NOT Typst `none`. `float("nil")` throws *"invalid float: nil"*.
- Truly absent values may also appear as Typst `none`.

### Required pattern: define `to-num` ONCE at the top of the template

Place this **before any function that uses it** — Typst requires functions to be defined before reference, otherwise you get *"unknown variable: to-num"*.

```typst
#let to-num(v) = {
  if v == none { none }
  else if type(v) == str {
    let t = v.trim()
    if t == "nil" or t == "" or t == "N/A" { none }
    else { float(t) }
  } else { float(v) }
}
```

### Rules

1. **Define `to-num` before all other functions.**
2. **Call `to-num` at the top of every function** that takes a numeric param from Elixir data:
   ```typst
   #let fmt-score(v) = {
     let n = to-num(v)
     if n == none { "—" } else { str(calc.round(n, digits: 1)) }
   }
   ```
3. **Never call `calc.round`, `/`, `*`, `calc.min`, `calc.max`** on a raw Elixir value without first piping through `to-num`.
4. **Guard divisions** — wrap in `if v != none { ... } else { 0.0 }` (or appropriate fallback) before dividing.
5. **Inline template uses** also need coercion:
   ```typst
   #let mp = to-num(elixir_data.enrollment.male_pct)
   #if mp != none [ ... use mp safely ... ]
   ```

## The `nil`-string trap (do not skip this)

It is tempting to write:

```typst
// WRONG — "nil" is a string, this guard misses it, then calc.round crashes
if v == none { "—" } else { calc.round(v, digits: 1) }
```

This fails because Elixir `nil` arrives as the **string** `"nil"`, which is not equal to Typst `none`. The guard passes, `calc.round("nil")` blows up.

**Correct pattern:** always call `to-num(v)` first, bind the result, then check the result for `none`:

```typst
let n = to-num(v)
if n == none { "—" } else { calc.round(n, digits: 1) }
```

## Error → cause cheat sheet

| Error message | Cause | Fix |
|---|---|---|
| `expected integer, float, or decimal, found string` | Raw string passed to `calc.round` / arithmetic | Pipe through `to-num` first |
| `invalid float: nil` | `float("nil")` — Elixir `nil` serialised as string | Use `to-num`; it handles `"nil"` |
| `unknown variable: to-num` | `to-num` defined after a function that calls it | Move `to-num` to the top of the template |
| `cannot divide none by integer` | `to-num` returned `none`, division had no nil guard | Add `if v != none { ... }` before division |

## Workflow when editing a Typst template

1. Confirm `to-num` is defined at the top.
2. For every numeric param a function receives, the **first line** should be `let v = to-num(v)`.
3. For every boolean param, coerce string-to-bool at the top of the function.
4. Re-render the PDF locally — string-type errors only surface at compile time.