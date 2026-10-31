# Task B selection: 82_rpn_calculator / C

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.c`. Selected original locations: L6,L7,L8,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41.

- L6: `    const char *expressions[] = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `                                 "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    for (int k = 0; k < 7; k++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        strcpy(text, expressions[k]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        long long stack[64];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        int top = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        for (char *token = strtok(text, " "); token; token = strtok(NULL, " ")) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            if (strlen(token) == 1 && strchr("+-*/", token[0])) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `                if (top < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `                    error = "stack underflow";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                    break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `                long long b = stack[--top], a = stack[--top], v = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `                switch (token[0]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `                    case '+':` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `                        v = a + b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `                        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `                    case '-':` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                        v = a - b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `                        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `                    case '*':` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `                        v = a * b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `                        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `                    case '/':` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `                        v = a / b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `                        break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `                stack[top++] = v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                stack[top++] = strtoll(token, NULL, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **614 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 488 tokens. The contiguous original span L6–L41 costs 701 tokens; the complete original source costs 863 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 522 tokens; removes `const char *expressions[] = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",` from the dependency chain described above.
- Without L7: 540 tokens; removes `"4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"};` from the dependency chain described above.
- Without L8: 588 tokens; removes `for (int k = 0; k < 7; k++) {` from the dependency chain described above.
- Without L10: 600 tokens; removes `strcpy(text, expressions[k]);` from the dependency chain described above.
- Without L11: 601 tokens; removes `long long stack[64];` from the dependency chain described above.
- Without L12: 603 tokens; removes `int top = 0;` from the dependency chain described above.
- Without L14: 571 tokens; removes `for (char *token = strtok(text, " "); token; token = strtok(NULL, " ")) {` from the dependency chain described above.
- Without L15: 578 tokens; removes `if (strlen(token) == 1 && strchr("+-*/", token[0])) {` from the dependency chain described above.
- Without L16: 598 tokens; removes `if (top < 2) {` from the dependency chain described above.
- Without L17: 598 tokens; removes `error = "stack underflow";` from the dependency chain described above.
- Without L18: 606 tokens; removes `break;` from the dependency chain described above.
- Without L19: 608 tokens; removes `}` from the dependency chain described above.
- Without L20: 577 tokens; removes `long long b = stack[--top], a = stack[--top], v = 0;` from the dependency chain described above.
- Without L25: 599 tokens; removes `switch (token[0]) {` from the dependency chain described above.
- Without L26: 602 tokens; removes `case '+':` from the dependency chain described above.
- Without L27: 597 tokens; removes `v = a + b;` from the dependency chain described above.
- Without L28: 605 tokens; removes `break;` from the dependency chain described above.
- Without L29: 602 tokens; removes `case '-':` from the dependency chain described above.
- Without L30: 597 tokens; removes `v = a - b;` from the dependency chain described above.
- Without L31: 605 tokens; removes `break;` from the dependency chain described above.
- Without L32: 602 tokens; removes `case '*':` from the dependency chain described above.
- Without L33: 597 tokens; removes `v = a * b;` from the dependency chain described above.
- Without L34: 605 tokens; removes `break;` from the dependency chain described above.
- Without L35: 602 tokens; removes `case '/':` from the dependency chain described above.
- Without L36: 597 tokens; removes `v = a / b;` from the dependency chain described above.
- Without L37: 605 tokens; removes `break;` from the dependency chain described above.
- Without L38: 608 tokens; removes `}` from the dependency chain described above.
- Without L39: 599 tokens; removes `stack[top++] = v;` from the dependency chain described above.
- Without L40: 605 tokens; removes `} else {` from the dependency chain described above.
- Without L41: 589 tokens; removes `stack[top++] = strtoll(token, NULL, 10);` from the dependency chain described above.
