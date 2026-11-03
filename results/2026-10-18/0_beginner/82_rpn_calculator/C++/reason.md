# Task B selection: 82_rpn_calculator / C++

## Common answer requirements

Trace expression 2 negative-number recognition, stack operand order and truncating negative division; locate expression 3 first underflow and explain why final token is skipped.

## Answer and source dependencies

Expression 2 pushes -17 and 5; division takes the top as b and the previous as a and computes a/b, truncating -17/5 toward zero to -3. It then pushes 4 and -3, multiplies to -12, and computes -3 - (-12) = 9. Only exact one-character operator tokens are operators, so -17 and -3 are parsed as signed integers. Expression 3 first adds 1 and 2 to leave one operand, then reaches * with fewer than two operands: underflow causes break or immediate return, so its trailing 3 is never parsed. Native signed integer division or an explicit truncation operation supplies truncation; sign/magnitude implementations floor the positive magnitude then restore the sign.



## Scope and dependency evidence checked after independent review

Link the literal second/third expressions to the actual expression variable consumed by splitting/tokenization or to the evaluate call. The numeric branch ends after conversion/continue; the underflow branch ends before either pop; the selected arithmetic conditional/switch ends before its result is pushed. Thus -17 and -3 are integer operands, division is -17/5→-3 toward zero, subtraction uses older-left minus newer-right to obtain9, and expression3 breaks/returns at* with stack[3], leaving final3 unread. Helper and expression-list boundaries associate these operations with their actual supplied strings.

Source: `main.cpp`. Selected original locations: L8,L9,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L28,L29,L30.

- L8: `    const std::array<std::string, 7> expressions = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    for (const std::string &expression : expressions) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        std::istringstream input(expression);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        std::vector<long long> stack;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        for (std::string token; input >> token;) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            if (token.size() == 1 && std::string("+-*/").find(token[0]) != std::string::npos) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `                if (stack.size() < 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `                    error = "stack underflow";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                    break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `                long long b = stack.back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `                stack.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `                long long a = stack.back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `                stack.pop_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `                stack.push_back(token == "+" ? a + b : token == "-" ? a - b : token == "*" ? a * b : a / b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                stack.push_back(std::stoll(token));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **498 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 359 tokens. The contiguous original span L8–L30 costs 565 tokens; the complete original source costs 745 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 432 tokens; removes `const std::array<std::string, 7> expressions = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",` from the dependency chain described above.
- Without L9: 397 tokens; removes `"15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"};` from the dependency chain described above.
- Without L10: 478 tokens; removes `for (const std::string &expression : expressions) {` from the dependency chain described above.
- Without L11: 486 tokens; removes `std::istringstream input(expression);` from the dependency chain described above.
- Without L12: 484 tokens; removes `std::vector<long long> stack;` from the dependency chain described above.
- Without L14: 476 tokens; removes `for (std::string token; input >> token;) {` from the dependency chain described above.
- Without L15: 449 tokens; removes `if (token.size() == 1 && std::string("+-*/").find(token[0]) != std::string::npos) {` from the dependency chain described above.
- Without L16: 478 tokens; removes `if (stack.size() < 2) {` from the dependency chain described above.
- Without L17: 482 tokens; removes `error = "stack underflow";` from the dependency chain described above.
- Without L18: 490 tokens; removes `break;` from the dependency chain described above.
- Without L19: 492 tokens; removes `}` from the dependency chain described above.
- Without L20: 479 tokens; removes `long long b = stack.back();` from the dependency chain described above.
- Without L21: 485 tokens; removes `stack.pop_back();` from the dependency chain described above.
- Without L22: 479 tokens; removes `long long a = stack.back();` from the dependency chain described above.
- Without L23: 485 tokens; removes `stack.pop_back();` from the dependency chain described above.
- Without L28: 426 tokens; removes `stack.push_back(token == "+" ? a + b : token == "-" ? a - b : token == "*" ? a * b : a / b);` from the dependency chain described above.
- Without L29: 489 tokens; removes `} else {` from the dependency chain described above.
- Without L30: 479 tokens; removes `stack.push_back(std::stoll(token));` from the dependency chain described above.
