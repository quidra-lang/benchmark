# Task B selection: 82_rpn_calculator / Zig

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.zig`. Selected original locations: L7,L9,L10,L15,L16,L17,L18,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L40,L41,L42,L43,L44,L45,L46,L47.

- L7: `    const expressions = [_][]const u8{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        "-17 5 / 4 -3 * -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        "1 2 + * 3",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    for (expressions) |expression| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        var stack: [32]i64 = undefined;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        var len: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        var tokens = std.mem.splitScalar(u8, expression, ' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        while (tokens.next()) |token| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            const operator = token.len == 1 and` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `                (token[0] == '+' or token[0] == '-' or token[0] == '*' or token[0] == '/');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            if (!operator) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `                stack[len] = try std.fmt.parseInt(i64, token, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `                len += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `                continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `            if (len < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                err = "stack underflow";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `                break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `            const b = stack[len - 1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            const a = stack[len - 2];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            len -= 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            stack[len] = switch (token[0]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                '+' => a + b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `                '-' => a - b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                '*' => a * b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `                '/' => @divTrunc(a, b),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `                else => unreachable,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `            };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `            len += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **499 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 450 tokens. The contiguous original span L7–L47 costs 694 tokens; the complete original source costs 957 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 483 tokens; removes `const expressions = [_][]const u8{` from the dependency chain described above.
- Without L9: 477 tokens; removes `"-17 5 / 4 -3 * -",` from the dependency chain described above.
- Without L10: 484 tokens; removes `"1 2 + * 3",` from the dependency chain described above.
- Without L15: 495 tokens; removes `};` from the dependency chain described above.
- Without L16: 486 tokens; removes `for (expressions) |expression| {` from the dependency chain described above.
- Without L17: 481 tokens; removes `var stack: [32]i64 = undefined;` from the dependency chain described above.
- Without L18: 485 tokens; removes `var len: usize = 0;` from the dependency chain described above.
- Without L20: 472 tokens; removes `var tokens = std.mem.splitScalar(u8, expression, ' ');` from the dependency chain described above.
- Without L21: 481 tokens; removes `while (tokens.next()) |token| {` from the dependency chain described above.
- Without L22: 480 tokens; removes `const operator = token.len == 1 and` from the dependency chain described above.
- Without L23: 442 tokens; removes `(token[0] == '+' or token[0] == '-' or token[0] == '*' or token[0] == '/');` from the dependency chain described above.
- Without L24: 487 tokens; removes `if (!operator) {` from the dependency chain described above.
- Without L25: 468 tokens; removes `stack[len] = try std.fmt.parseInt(i64, token, 10);` from the dependency chain described above.
- Without L26: 488 tokens; removes `len += 1;` from the dependency chain described above.
- Without L27: 492 tokens; removes `continue;` from the dependency chain described above.
- Without L28: 494 tokens; removes `}` from the dependency chain described above.
- Without L29: 484 tokens; removes `if (len < 2) {` from the dependency chain described above.
- Without L30: 484 tokens; removes `err = "stack underflow";` from the dependency chain described above.
- Without L31: 492 tokens; removes `break;` from the dependency chain described above.
- Without L32: 494 tokens; removes `}` from the dependency chain described above.
- Without L33: 480 tokens; removes `const b = stack[len - 1];` from the dependency chain described above.
- Without L34: 480 tokens; removes `const a = stack[len - 2];` from the dependency chain described above.
- Without L35: 489 tokens; removes `len -= 2;` from the dependency chain described above.
- Without L40: 478 tokens; removes `stack[len] = switch (token[0]) {` from the dependency chain described above.
- Without L41: 482 tokens; removes `'+' => a + b,` from the dependency chain described above.
- Without L42: 482 tokens; removes `'-' => a - b,` from the dependency chain described above.
- Without L43: 482 tokens; removes `'*' => a * b,` from the dependency chain described above.
- Without L44: 478 tokens; removes `'/' => @divTrunc(a, b),` from the dependency chain described above.
- Without L45: 488 tokens; removes `else => unreachable,` from the dependency chain described above.
- Without L46: 493 tokens; removes `};` from the dependency chain described above.
- Without L47: 489 tokens; removes `len += 1;` from the dependency chain described above.
