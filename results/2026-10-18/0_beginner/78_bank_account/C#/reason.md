# Task B source selection

## Common answer requirements

Trace current balances at Emma-to-Nina transfers 2500 then 2000, including equality and atomic failure; follow Emma into withdrawal 300.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Emma begins at 800 and receives a deposit of 1200, so has 2000. Nina begins at 12000 and has already transferred 5000 to Leo, so has 7000. Emma cannot transfer 2500: the source checks the current source balance before either debit or credit and performs neither on failure, leaving Emma 2000 and Nina 7000. Equality is allowed (balance >= amount, equivalently failure only on balance < amount): the subsequent transfer of 2000 succeeds, leaving Emma 0 and Nina 9000. The immediately following withdrawal of 300 fails and leaves Emma at 0. Transaction iteration, parsing, amount selection, condition, and guarded mutations establish that every decision uses the balances existing at that moment.



## Source evidence and dependencies

The selected locations in `Program.cs` are L7, L8, L9, L12, L13, L14, L16, L18, L19, L20, L21, L22, L24, L26, L28, L30, L31, L32, L33. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L7: `string[] transactions = { "deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L8: `"withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L9: `"withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800" };`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L12: `["Nina"] = 12000,`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L13: `["Leo"] = 3500,`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L14: `["Emma"] = 800`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L16: `for (int i = 0; i < transactions.Length; i++)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L18: `string[] parts = transactions[i].Split(' ');`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L19: `string name = parts[1];`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L20: `int amount = int.Parse(parts[^1], CultureInfo.InvariantCulture);`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L21: `bool success = parts[0] == "deposit" || balances[name] >= amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L22: `if (success)`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L24: `if (parts[0] == "deposit")`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L26: `balances[name] += amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L28: `else`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L30: `balances[name] -= amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L31: `if (parts[0] == "transfer") balances[parts[2]] += amount;`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L32: `}`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.
- L33: `}`. This line supplies an initial balance, relevant ordered transaction, account/amount decoding, sufficiency/equality test or guarded debit/credit. These connect the numeric trace to current balances and atomic failure.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **433 tokens** for the final selected lines. The prior candidate measured 388 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.

Final original source lines: L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L29, L30, L31, L32, L33.
- L10: `var balances = new SortedDictionary<string, int>(StringComparer.Ordinal)` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L11: `{` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L15: `};` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L17: `{` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L23: `    {` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L25: `        {` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L27: `        }` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.
- L29: `        {` — The dictionary declaration links named initial balances to balances[name], and explicit success/deposit/else blocks show that failed transfers perform neither balance mutation.

Final selection: 433 metric tokens; contiguous span L7–L33: 433 tokens; complete source: 559 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
