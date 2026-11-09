# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate the named-expression registry initialization and where startup would register only ZERO.
2. Identify the existing exact rational-zero expression construction, rather than a floating numeric default.
3. Identify the named lookup and missing-name branch; preserve failure for all other undefined names.
4. Show that ordinary LET overwrites the existing key, without reserving ZERO or changing numerical-evaluation defaults.

## Selected source locations

- `main.js`: 10, 13, 14, 19, 21, 318, 319, 320, 403, 523

## Evidence and language semantics

Initialize the existing named-expression registry with the single ZERO entry after the zero expression is available, before processing commands. The selected number constructor retains numerator zero and denominator one (or its normalized rational representation), and the cached zero expression can be reused. Preserve the selected missing-name error branch: it is not a fallback to zero for every unknown name. The existing key assignment/insertion replaces a previously stored ZERO entry, so LET requires no reservation or special case. Numerical variable values and EVAL argument defaults are a separate operation and require no change.

## Minimization and alternatives

The registry initializer, numeric-construction path, successful/missing named lookup, and ordinary overwriting operation each support a distinct answer requirement. Unrelated differentiation, simplification, rendering and numerical evaluation paths are excluded. The rational helper is retained only through its integer numerator/denominator construction; normalization validation for invalid rational inputs is unnecessary for the valid zero constant under Task B assumptions. Changing the lookup to return zero on absence is an incorrect alternative because it would define every missing name. Changing a numerical variable default would affect a different operation and would not register the named expression.

The excerpt contains 217 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
