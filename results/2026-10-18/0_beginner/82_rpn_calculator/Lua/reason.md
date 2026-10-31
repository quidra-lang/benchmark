# Task B selection: 82_rpn_calculator / Lua

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L28,L29,L31,L32.

- L1: `local function evaluate(expression)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    local stack = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    for token in expression:gmatch("%S+") do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        if token == "+" or token == "-" or token == "*" or token == "/" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `            if #stack < 2 then return "error: stack underflow" end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `            local b = table.remove(stack)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `            local a = table.remove(stack)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `            if token == "+" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `                value = a + b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            elseif token == "-" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `                value = a - b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `            elseif token == "*" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `                value = a * b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `                value = math.abs(a) // math.abs(b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                if (a < 0) ~= (b < 0) then value = -value end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `            stack[#stack + 1] = value` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `            stack[#stack + 1] = tonumber(token)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `local expressions = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    "3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `for _, expression in ipairs(expressions) do io.write(expression, " => ", evaluate(expression), "\n") end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **483 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 415 tokens. The contiguous original span L1–L32 costs 625 tokens; the complete original source costs 625 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 474 tokens; removes `local function evaluate(expression)` from the dependency chain described above.
- Without L2: 473 tokens; removes `local stack = {}` from the dependency chain described above.
- Without L3: 463 tokens; removes `for token in expression:gmatch("%S+") do` from the dependency chain described above.
- Without L4: 439 tokens; removes `if token == "+" or token == "-" or token == "*" or token == "/" then` from the dependency chain described above.
- Without L5: 456 tokens; removes `if #stack < 2 then return "error: stack underflow" end` from the dependency chain described above.
- Without L6: 467 tokens; removes `local b = table.remove(stack)` from the dependency chain described above.
- Without L7: 467 tokens; removes `local a = table.remove(stack)` from the dependency chain described above.
- Without L10: 468 tokens; removes `if token == "+" then` from the dependency chain described above.
- Without L11: 469 tokens; removes `value = a + b` from the dependency chain described above.
- Without L12: 468 tokens; removes `elseif token == "-" then` from the dependency chain described above.
- Without L13: 469 tokens; removes `value = a - b` from the dependency chain described above.
- Without L14: 468 tokens; removes `elseif token == "*" then` from the dependency chain described above.
- Without L15: 469 tokens; removes `value = a * b` from the dependency chain described above.
- Without L16: 478 tokens; removes `else` from the dependency chain described above.
- Without L17: 459 tokens; removes `value = math.abs(a) // math.abs(b)` from the dependency chain described above.
- Without L18: 448 tokens; removes `if (a < 0) ~= (b < 0) then value = -value end` from the dependency chain described above.
- Without L19: 478 tokens; removes `end` from the dependency chain described above.
- Without L20: 466 tokens; removes `stack[#stack + 1] = value` from the dependency chain described above.
- Without L21: 479 tokens; removes `else` from the dependency chain described above.
- Without L22: 463 tokens; removes `stack[#stack + 1] = tonumber(token)` from the dependency chain described above.
- Without L23: 479 tokens; removes `end` from the dependency chain described above.
- Without L24: 480 tokens; removes `end` from the dependency chain described above.
- Without L26: 481 tokens; removes `end` from the dependency chain described above.
- Without L28: 475 tokens; removes `local expressions = {` from the dependency chain described above.
- Without L29: 402 tokens; removes `"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` from the dependency chain described above.
- Without L31: 481 tokens; removes `}` from the dependency chain described above.
- Without L32: 439 tokens; removes `for _, expression in ipairs(expressions) do io.write(expression, " => ", evaluate(expression), "\n") end` from the dependency chain described above.
