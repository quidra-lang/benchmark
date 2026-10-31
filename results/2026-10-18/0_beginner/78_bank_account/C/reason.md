# Task B source selection

## Common answer requirements

Trace current balances at Emma-to-Nina transfers 2500 then 2000, including equality and atomic failure; follow Emma into withdrawal 300.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Emma begins at 800 and receives a deposit of 1200, so has 2000. Nina begins at 12000 and has already transferred 5000 to Leo, so has 7000. Emma cannot transfer 2500: the source checks the current source balance before either debit or credit and performs neither on failure, leaving Emma 2000 and Nina 7000. Equality is allowed (balance >= amount, equivalently failure only on balance < amount): the subsequent transfer of 2000 succeeds, leaving Emma 0 and Nina 9000. The immediately following withdrawal of 300 fails and leaves Emma at 0. Transaction iteration, parsing, amount selection, condition, and guarded mutations establish that every decision uses the balances existing at that moment.



## Source evidence and dependencies

The selected locations in `main.c` are L6, L7, L8, L10, L11, L14, L15, L16, L17, L18, L19, L20, L21, L22, L24, L25, L26, L27, L28, L29, L30, L31, L32, L33. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L6: `const char *names[] = {"Nina", "Leo", "Emma"};`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L7: `const char *transactions[] = {"deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L8: `"withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000", "withdraw Emma 300",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L10: `int balances[] = {12000, 3500, 800};`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L11: `for (int k = 0; k < 10; k++) {`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L14: `sscanf(transactions[k], "%15s %15s %15s %d", op, from, to, &amount);`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L15: `if (strcmp(op, "transfer") != 0)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L16: `amount = atoi(to);`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L17: `int a = 0, b = 0;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L18: `while (strcmp(names[a], from))`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L19: `a++;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L20: `if (strcmp(op, "transfer") == 0) {`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L21: `while (strcmp(names[b], to))`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L22: `b++;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L24: `int ok = strcmp(op, "deposit") == 0 || balances[a] >= amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L25: `if (ok) {`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L26: `if (strcmp(op, "deposit") == 0) {`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L27: `balances[a] += amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L28: `} else {`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L29: `balances[a] -= amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L30: `if (strcmp(op, "transfer") == 0)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L31: `balances[b] += amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L32: `}`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L33: `}`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **508 tokens** for the final selected lines. The prior candidate measured 504 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

The transfer-only recipient lookup ends before the common success test. Thus deposits and withdrawals also reach that test, while both transfer balance mutations remain guarded by success.

Final original source lines: L6, L7, L8, L10, L11, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L29, L30, L31, L32, L33.
- L23: `        }` — The transfer-only recipient lookup ends before the common success test. Thus deposits and withdrawals also reach that test, while both transfer balance mutations remain guarded by success.

Final selection: 508 metric tokens; contiguous span L6–L33: 580 tokens; complete source: 894 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
