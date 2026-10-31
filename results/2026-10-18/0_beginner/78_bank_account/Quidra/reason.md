# Task B source selection

## Common answer requirements

Trace current balances at Emma-to-Nina transfers 2500 then 2000, including equality and atomic failure; follow Emma into withdrawal 300.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Emma begins at 800 and receives a deposit of 1200, so has 2000. Nina begins at 12000 and has already transferred 5000 to Leo, so has 7000. Emma cannot transfer 2500: the source checks the current source balance before either debit or credit and performs neither on failure, leaving Emma 2000 and Nina 7000. Equality is allowed (balance >= amount, equivalently failure only on balance < amount): the subsequent transfer of 2000 succeeds, leaving Emma 0 and Nina 9000. The immediately following withdrawal of 300 fails and leaves Emma at 0. Transaction iteration, parsing, amount selection, condition, and guarded mutations establish that every decision uses the balances existing at that moment.



## Source evidence and dependencies

The selected locations in `main.qui` are L1, L2, L3, L4, L7, L8, L9, L10, L11, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `int account(string name, string[] names)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L2: `for 0 <= int i < int(len(names))`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L3: `if names[i] == name`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L4: `return i`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L7: `string[] names = ["Nina", "Leo", "Emma"]`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L8: `int[] balances = [12000, 3500, 800]`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L9: `string[] commands = [`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L10: `"deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000", "withdraw Leo 4000",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L11: `"transfer Emma Nina 2500", "transfer Emma Nina 2000", "withdraw Emma 300", "deposit Nina 750",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L14: `for 0 <= int i < 10`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L15: `string[] fields = commands[i].split(" ")`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L16: `int source = account(fields[1], names)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L17: `int amount = int.parse(fields[len(fields) - 1])`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L18: `bool success = true`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L19: `if fields[0] == "deposit"`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L20: `balances[source] += amount`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L21: `elif amount > balances[source]`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L22: `success = false`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L23: `else`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L24: `balances[source] -= amount`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L25: `if fields[0] == "transfer"`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L26: `int target = account(fields[2], names)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L27: `balances[target] += amount`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **407 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L27 costs **443 tokens**; the entire source costs **570 tokens**. The selected set plus the additional context line L5 costs **413 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
