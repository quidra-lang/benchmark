# Task B selection: 82_rpn_calculator / R

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.R`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L28,L29,L31,L32.

- L1: `evaluate <- function(expression) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  stack <- numeric(0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  for (token in strsplit(expression, " ", fixed = TRUE)[[1]]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    if (token %in% c("+", "-", "*", "/")) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `      if (length(stack) < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `        return("error: stack underflow")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `      b <- tail(stack, 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `      a <- stack[length(stack) - 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `      stack <- head(stack, -2)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `      value <- switch(token,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        "+" = a + b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        "-" = a - b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        "*" = a * b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        "/" = trunc(a / b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `      )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `      stack <- c(stack, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `      stack <- c(stack, as.numeric(token))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `expressions <- c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  "3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `for (expression in expressions) cat(sprintf("%s => %s\n", expression, evaluate(expression)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **419 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 357 tokens. The contiguous original span L1–L32 costs 567 tokens; the complete original source costs 567 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 408 tokens; removes `evaluate <- function(expression) {` from the dependency chain described above.
- Without L2: 409 tokens; removes `stack <- numeric(0)` from the dependency chain described above.
- Without L3: 388 tokens; removes `for (token in strsplit(expression, " ", fixed = TRUE)[[1]]) {` from the dependency chain described above.
- Without L4: 386 tokens; removes `if (token %in% c("+", "-", "*", "/")) {` from the dependency chain described above.
- Without L5: 402 tokens; removes `if (length(stack) < 2) {` from the dependency chain described above.
- Without L6: 405 tokens; removes `return("error: stack underflow")` from the dependency chain described above.
- Without L7: 415 tokens; removes `}` from the dependency chain described above.
- Without L8: 405 tokens; removes `b <- tail(stack, 1)` from the dependency chain described above.
- Without L9: 401 tokens; removes `a <- stack[length(stack) - 1]` from the dependency chain described above.
- Without L10: 404 tokens; removes `stack <- head(stack, -2)` from the dependency chain described above.
- Without L14: 408 tokens; removes `value <- switch(token,` from the dependency chain described above.
- Without L15: 404 tokens; removes `"+" = a + b,` from the dependency chain described above.
- Without L16: 404 tokens; removes `"-" = a - b,` from the dependency chain described above.
- Without L17: 404 tokens; removes `"*" = a * b,` from the dependency chain described above.
- Without L18: 402 tokens; removes `"/" = trunc(a / b)` from the dependency chain described above.
- Without L19: 415 tokens; removes `)` from the dependency chain described above.
- Without L20: 405 tokens; removes `stack <- c(stack, value)` from the dependency chain described above.
- Without L21: 412 tokens; removes `} else {` from the dependency chain described above.
- Without L22: 400 tokens; removes `stack <- c(stack, as.numeric(token))` from the dependency chain described above.
- Without L23: 416 tokens; removes `}` from the dependency chain described above.
- Without L24: 416 tokens; removes `}` from the dependency chain described above.
- Without L26: 417 tokens; removes `}` from the dependency chain described above.
- Without L28: 412 tokens; removes `expressions <- c(` from the dependency chain described above.
- Without L29: 338 tokens; removes `"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` from the dependency chain described above.
- Without L31: 417 tokens; removes `)` from the dependency chain described above.
- Without L32: 382 tokens; removes `for (expression in expressions) cat(sprintf("%s => %s\n", expression, evaluate(expression)))` from the dependency chain described above.
