# Task B selection: 82_rpn_calculator / Julia

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.jl`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L24,L26,L28,L29,L34,L35.

- L1: `function evaluate(expression)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    stack = Int[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    for token in split(expression)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        if token in ("+", "-", "*", "/")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `            length(stack) < 2 && return "error: stack underflow"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `            b = pop!(stack)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `            a = pop!(stack)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `            if token == "+"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `                value = a+b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `            elseif token == "-"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `                value = a-b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            elseif token == "*"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `                value = a*b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `                value = div(a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `            push!(stack, value)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `            push!(stack, parse(Int, token))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `for expression in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    "-17 5 / 4 -3 * -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    "1 2 + * 3",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    println(expression, " => ", evaluate(expression))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **315 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 272 tokens. The contiguous original span L1–L35 costs 499 tokens; the complete original source costs 501 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 308 tokens; removes `function evaluate(expression)` from the dependency chain described above.
- Without L2: 307 tokens; removes `stack = Int[]` from the dependency chain described above.
- Without L3: 303 tokens; removes `for token in split(expression)` from the dependency chain described above.
- Without L4: 286 tokens; removes `if token in ("+", "-", "*", "/")` from the dependency chain described above.
- Without L5: 290 tokens; removes `length(stack) < 2 && return "error: stack underflow"` from the dependency chain described above.
- Without L6: 302 tokens; removes `b = pop!(stack)` from the dependency chain described above.
- Without L7: 302 tokens; removes `a = pop!(stack)` from the dependency chain described above.
- Without L9: 302 tokens; removes `if token == "+"` from the dependency chain described above.
- Without L10: 303 tokens; removes `value = a+b` from the dependency chain described above.
- Without L11: 302 tokens; removes `elseif token == "-"` from the dependency chain described above.
- Without L12: 303 tokens; removes `value = a-b` from the dependency chain described above.
- Without L13: 302 tokens; removes `elseif token == "*"` from the dependency chain described above.
- Without L14: 303 tokens; removes `value = a*b` from the dependency chain described above.
- Without L15: 310 tokens; removes `else` from the dependency chain described above.
- Without L16: 299 tokens; removes `value = div(a, b)` from the dependency chain described above.
- Without L17: 310 tokens; removes `end` from the dependency chain described above.
- Without L18: 303 tokens; removes `push!(stack, value)` from the dependency chain described above.
- Without L19: 311 tokens; removes `else` from the dependency chain described above.
- Without L20: 297 tokens; removes `push!(stack, parse(Int, token))` from the dependency chain described above.
- Without L21: 311 tokens; removes `end` from the dependency chain described above.
- Without L22: 312 tokens; removes `end` from the dependency chain described above.
- Without L24: 313 tokens; removes `end` from the dependency chain described above.
- Without L26: 307 tokens; removes `for expression in [` from the dependency chain described above.
- Without L28: 294 tokens; removes `"-17 5 / 4 -3 * -",` from the dependency chain described above.
- Without L29: 301 tokens; removes `"1 2 + * 3",` from the dependency chain described above.
- Without L34: 313 tokens; removes `]` from the dependency chain described above.
- Without L35: 296 tokens; removes `println(expression, " => ", evaluate(expression))` from the dependency chain described above.
