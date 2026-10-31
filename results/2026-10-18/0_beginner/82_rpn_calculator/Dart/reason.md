# Task B selection: 82_rpn_calculator / Dart

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.dart`. Selected original locations: L2,L4,L5,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L27,L28,L29,L30,L31,L32,L33.

- L2: `  for (final expression in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    '-17 5 / 4 -3 * -',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    '1 2 + * 3',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  ]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    final stack = <int>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    for (final token in expression.split(' ')) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `      if (token.length != 1 || !'+-*/'.contains(token)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        stack.add(int.parse(token));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `      if (stack.length < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        error = 'stack underflow';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `      final b = stack.removeLast(), a = stack.removeLast();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `      stack.add(switch (token) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        '+' => a + b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        '-' => a - b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        '*' => a * b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        '/' => a ~/ b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        _ => throw StateError('operator'),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `      });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **306 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 274 tokens. The contiguous original span L2–L33 costs 477 tokens; the complete original source costs 562 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 294 tokens; removes `for (final expression in [` from the dependency chain described above.
- Without L4: 285 tokens; removes `'-17 5 / 4 -3 * -',` from the dependency chain described above.
- Without L5: 292 tokens; removes `'1 2 + * 3',` from the dependency chain described above.
- Without L10: 300 tokens; removes `]) {` from the dependency chain described above.
- Without L11: 293 tokens; removes `final stack = <int>[];` from the dependency chain described above.
- Without L13: 284 tokens; removes `for (final token in expression.split(' ')) {` from the dependency chain described above.
- Without L14: 275 tokens; removes `if (token.length != 1 || !'+-*/'.contains(token)) {` from the dependency chain described above.
- Without L15: 291 tokens; removes `stack.add(int.parse(token));` from the dependency chain described above.
- Without L16: 301 tokens; removes `continue;` from the dependency chain described above.
- Without L17: 302 tokens; removes `}` from the dependency chain described above.
- Without L18: 290 tokens; removes `if (stack.length < 2) {` from the dependency chain described above.
- Without L19: 293 tokens; removes `error = 'stack underflow';` from the dependency chain described above.
- Without L20: 301 tokens; removes `break;` from the dependency chain described above.
- Without L21: 302 tokens; removes `}` from the dependency chain described above.
- Without L22: 278 tokens; removes `final b = stack.removeLast(), a = stack.removeLast();` from the dependency chain described above.
- Without L27: 292 tokens; removes `stack.add(switch (token) {` from the dependency chain described above.
- Without L28: 291 tokens; removes `'+' => a + b,` from the dependency chain described above.
- Without L29: 291 tokens; removes `'-' => a - b,` from the dependency chain described above.
- Without L30: 291 tokens; removes `'*' => a * b,` from the dependency chain described above.
- Without L31: 291 tokens; removes `'/' => a ~/ b,` from the dependency chain described above.
- Without L32: 289 tokens; removes `_ => throw StateError('operator'),` from the dependency chain described above.
- Without L33: 300 tokens; removes `});` from the dependency chain described above.
