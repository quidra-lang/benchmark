# Task B selection: 82_rpn_calculator / Python

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.py`. Selected original locations: L1,L3,L4,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L24,L25,L26,L27,L28,L29,L30,L31,L32.

- L1: `expressions = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    "-17 5 / 4 -3 * -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    "1 2 + * 3",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `for expression in expressions:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    stack = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    for token in expression.split():` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        if token not in {"+", "-", "*", "/"}:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            stack.append(int(token))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        if len(stack) < 2:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `            error = "stack underflow"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        b, a = stack.pop(), stack.pop()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        if token == "+":` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            result = a + b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        elif token == "-":` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            result = a - b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        elif token == "*":` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            result = a * b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        else:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            result = int(a / b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        stack.append(result)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **284 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 267 tokens. The contiguous original span L1–L32 costs 448 tokens; the complete original source costs 527 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 278 tokens; removes `expressions = [` from the dependency chain described above.
- Without L3: 263 tokens; removes `"-17 5 / 4 -3 * -",` from the dependency chain described above.
- Without L4: 270 tokens; removes `"1 2 + * 3",` from the dependency chain described above.
- Without L9: 282 tokens; removes `]` from the dependency chain described above.
- Without L10: 275 tokens; removes `for expression in expressions:` from the dependency chain described above.
- Without L11: 277 tokens; removes `stack = []` from the dependency chain described above.
- Without L13: 270 tokens; removes `for token in expression.split():` from the dependency chain described above.
- Without L14: 253 tokens; removes `if token not in {"+", "-", "*", "/"}:` from the dependency chain described above.
- Without L15: 271 tokens; removes `stack.append(int(token))` from the dependency chain described above.
- Without L16: 279 tokens; removes `continue` from the dependency chain described above.
- Without L17: 270 tokens; removes `if len(stack) < 2:` from the dependency chain described above.
- Without L18: 271 tokens; removes `error = "stack underflow"` from the dependency chain described above.
- Without L19: 279 tokens; removes `break` from the dependency chain described above.
- Without L20: 262 tokens; removes `b, a = stack.pop(), stack.pop()` from the dependency chain described above.
- Without L24: 271 tokens; removes `if token == "+":` from the dependency chain described above.
- Without L25: 271 tokens; removes `result = a + b` from the dependency chain described above.
- Without L26: 271 tokens; removes `elif token == "-":` from the dependency chain described above.
- Without L27: 271 tokens; removes `result = a - b` from the dependency chain described above.
- Without L28: 271 tokens; removes `elif token == "*":` from the dependency chain described above.
- Without L29: 271 tokens; removes `result = a * b` from the dependency chain described above.
- Without L30: 279 tokens; removes `else:` from the dependency chain described above.
- Without L31: 268 tokens; removes `result = int(a / b)` from the dependency chain described above.
- Without L32: 275 tokens; removes `stack.append(result)` from the dependency chain described above.
