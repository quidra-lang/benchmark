# Task B selection: 82_rpn_calculator / PHP

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L27,L29,L30,L32,L33,L34.

- L3: `function evaluate(string $expression): string` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `    $stack = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    foreach (explode(' ', $expression) as $token) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        if (in_array($token, ['+', '-', '*', '/'], true)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `            if (count($stack) < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `                return 'error: stack underflow';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `            $b = array_pop($stack);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            $a = array_pop($stack);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            $stack[] = match ($token) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `                '+' => $a + $b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                '-' => $a - $b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `                '*' => $a * $b,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `                '/' => intdiv($a, $b),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            $stack[] = (int) $token;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `$expressions = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    '3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3', '15 7 1 1 + - / 3 * 2 1 1 + + -',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `foreach ($expressions as $expression) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    printf("%s => %s\n", $expression, evaluate($expression));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **431 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 357 tokens. The contiguous original span L3–L34 costs 584 tokens; the complete original source costs 591 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 418 tokens; removes `function evaluate(string $expression): string` from the dependency chain described above.
- Without L4: 429 tokens; removes `{` from the dependency chain described above.
- Without L5: 422 tokens; removes `$stack = [];` from the dependency chain described above.
- Without L6: 408 tokens; removes `foreach (explode(' ', $expression) as $token) {` from the dependency chain described above.
- Without L7: 390 tokens; removes `if (in_array($token, ['+', '-', '*', '/'], true)) {` from the dependency chain described above.
- Without L8: 412 tokens; removes `if (count($stack) < 2) {` from the dependency chain described above.
- Without L9: 415 tokens; removes `return 'error: stack underflow';` from the dependency chain described above.
- Without L10: 426 tokens; removes `}` from the dependency chain described above.
- Without L11: 414 tokens; removes `$b = array_pop($stack);` from the dependency chain described above.
- Without L12: 414 tokens; removes `$a = array_pop($stack);` from the dependency chain described above.
- Without L16: 413 tokens; removes `$stack[] = match ($token) {` from the dependency chain described above.
- Without L17: 412 tokens; removes `'+' => $a + $b,` from the dependency chain described above.
- Without L18: 412 tokens; removes `'-' => $a - $b,` from the dependency chain described above.
- Without L19: 412 tokens; removes `'*' => $a * $b,` from the dependency chain described above.
- Without L20: 410 tokens; removes `'/' => intdiv($a, $b),` from the dependency chain described above.
- Without L21: 425 tokens; removes `};` from the dependency chain described above.
- Without L22: 423 tokens; removes `} else {` from the dependency chain described above.
- Without L23: 414 tokens; removes `$stack[] = (int) $token;` from the dependency chain described above.
- Without L24: 427 tokens; removes `}` from the dependency chain described above.
- Without L25: 428 tokens; removes `}` from the dependency chain described above.
- Without L27: 429 tokens; removes `}` from the dependency chain described above.
- Without L29: 424 tokens; removes `$expressions = [` from the dependency chain described above.
- Without L30: 350 tokens; removes `'3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3', '15 7 1 1 + - / 3 * 2 1 1 + + -',` from the dependency chain described above.
- Without L32: 428 tokens; removes `];` from the dependency chain described above.
- Without L33: 417 tokens; removes `foreach ($expressions as $expression) {` from the dependency chain described above.
- Without L34: 403 tokens; removes `printf("%s => %s\n", $expression, evaluate($expression));` from the dependency chain described above.
