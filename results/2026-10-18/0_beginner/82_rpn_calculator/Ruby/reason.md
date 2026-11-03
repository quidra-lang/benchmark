# Task B selection: 82_rpn_calculator / Ruby

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.rb`. Selected original locations: L1,L2,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L23,L24,L25,L26,L27,L28,L29,L30.

- L1: `expressions = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  '3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `expressions.each do |expression|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  stack = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  expression.split.each do |token|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    unless %w[+ - * /].include?(token)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `      stack << token.to_i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `      next` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `    if stack.length < 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `      error = 'stack underflow'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `      break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    b, a = stack.pop, stack.pop` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    result = case token` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `             when '+' then a + b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `             when '-' then a - b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `             when '*' then a * b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `             else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `               a.quo(b).truncate` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `             end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `    stack << result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **267 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 237 tokens. The contiguous original span L1–L30 costs 412 tokens; the complete original source costs 491 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 261 tokens; removes `expressions = [` from the dependency chain described above.
- Without L2: 220 tokens; removes `'3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3',` from the dependency chain described above.
- Without L5: 265 tokens; removes `]` from the dependency chain described above.
- Without L6: 257 tokens; removes `expressions.each do |expression|` from the dependency chain described above.
- Without L7: 260 tokens; removes `stack = []` from the dependency chain described above.
- Without L9: 254 tokens; removes `expression.split.each do |token|` from the dependency chain described above.
- Without L10: 247 tokens; removes `unless %w[+ - * /].include?(token)` from the dependency chain described above.
- Without L11: 255 tokens; removes `stack << token.to_i` from the dependency chain described above.
- Without L12: 263 tokens; removes `next` from the dependency chain described above.
- Without L13: 264 tokens; removes `end` from the dependency chain described above.
- Without L14: 256 tokens; removes `if stack.length < 2` from the dependency chain described above.
- Without L15: 255 tokens; removes `error = 'stack underflow'` from the dependency chain described above.
- Without L16: 263 tokens; removes `break` from the dependency chain described above.
- Without L17: 264 tokens; removes `end` from the dependency chain described above.
- Without L18: 250 tokens; removes `b, a = stack.pop, stack.pop` from the dependency chain described above.
- Without L23: 258 tokens; removes `result = case token` from the dependency chain described above.
- Without L24: 249 tokens; removes `when '+' then a + b` from the dependency chain described above.
- Without L25: 249 tokens; removes `when '-' then a - b` from the dependency chain described above.
- Without L26: 249 tokens; removes `when '*' then a * b` from the dependency chain described above.
- Without L27: 261 tokens; removes `else` from the dependency chain described above.
- Without L28: 253 tokens; removes `a.quo(b).truncate` from the dependency chain described above.
- Without L29: 261 tokens; removes `end` from the dependency chain described above.
- Without L30: 260 tokens; removes `stack << result` from the dependency chain described above.
