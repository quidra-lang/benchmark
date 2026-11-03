# Task B selection: 82_rpn_calculator / Swift

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.swift`. Selected original locations: L1,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L19,L20,L21,L22,L23,L24,L25,L26.

- L1: `let expressions = ["3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    "2 3 4 + 5", "46341 46339 * -2 /"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `for expression in expressions {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    var stack = [Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    for raw in expression.split(separator: " ") {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        let token = String(raw)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        if token.count == 1 && "+-*/".contains(token) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `            if stack.count < 2 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `                error = "stack underflow"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `                break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `            let b = stack.removeLast(), a = stack.removeLast()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            switch token {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            case "+": stack.append(a + b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            case "-": stack.append(a - b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            case "*": stack.append(a * b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            default: stack.append(a / b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            stack.append(Int(token)!)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **358 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 302 tokens. The contiguous original span L1–L26 costs 485 tokens; the complete original source costs 581 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 305 tokens; removes `let expressions = ["3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",` from the dependency chain described above.
- Without L3: 322 tokens; removes `"2 3 4 + 5", "46341 46339 * -2 /"]` from the dependency chain described above.
- Without L4: 348 tokens; removes `for expression in expressions {` from the dependency chain described above.
- Without L5: 345 tokens; removes `var stack = [Int]()` from the dependency chain described above.
- Without L7: 337 tokens; removes `for raw in expression.split(separator: " ") {` from the dependency chain described above.
- Without L8: 345 tokens; removes `let token = String(raw)` from the dependency chain described above.
- Without L9: 330 tokens; removes `if token.count == 1 && "+-*/".contains(token) {` from the dependency chain described above.
- Without L10: 343 tokens; removes `if stack.count < 2 {` from the dependency chain described above.
- Without L11: 344 tokens; removes `error = "stack underflow"` from the dependency chain described above.
- Without L12: 352 tokens; removes `break` from the dependency chain described above.
- Without L13: 353 tokens; removes `}` from the dependency chain described above.
- Without L14: 330 tokens; removes `let b = stack.removeLast(), a = stack.removeLast()` from the dependency chain described above.
- Without L19: 349 tokens; removes `switch token {` from the dependency chain described above.
- Without L20: 337 tokens; removes `case "+": stack.append(a + b)` from the dependency chain described above.
- Without L21: 337 tokens; removes `case "-": stack.append(a - b)` from the dependency chain described above.
- Without L22: 337 tokens; removes `case "*": stack.append(a * b)` from the dependency chain described above.
- Without L23: 341 tokens; removes `default: stack.append(a / b)` from the dependency chain described above.
- Without L24: 353 tokens; removes `}` from the dependency chain described above.
- Without L25: 350 tokens; removes `} else {` from the dependency chain described above.
- Without L26: 344 tokens; removes `stack.append(Int(token)!)` from the dependency chain described above.
