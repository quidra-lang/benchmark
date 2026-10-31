# Task B selection: 40_binary_search / C#

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

The outer and while openings place initialization and repeated midpoint/probe/bound updates in their proper scopes. The equality-branch opening confines found assignment to equality, which never holds for50.

Source: `Program.cs`. Selected original lines: 7,8,9,10,11,12,13,14,15,16,17,18,20,21,22,23,24,25,26,27. The following original-line dependencies support the answer above:

- L7: `int[] values = { 3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77 };` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L8: `foreach (int target in new[] { 42, 3, 77, 31, 50, 1 })` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L9: `{` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L10: `    int lo = 0, hi = 15, found = -1;` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `    var probes = new List<int>();` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L12: `    while (lo <= hi)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L13: `    {` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L14: `        int mid = (lo + hi) / 2;` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L15: `        probes.Add(mid);` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L16: `        if (values[mid] == target)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L17: `        {` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L18: `            found = mid;` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L20: `        }` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L21: `        if (values[mid] < target)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L22: `            lo = mid + 1;` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L23: `        else` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L24: `            hi = mid - 1;` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L25: `    }` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L26: `    string result = found >= 0 ? "index " + found : "not found";` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L27: `    Console.WriteLine($"{target}: probes {string.Join(" ", probes)} -> {result}");` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **354 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **400 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L7: 281 tokens (versus 354); removes `int[] values = { 3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77 };`.
- Without L8: 316 tokens (versus 354); removes `foreach (int target in new[] { 42, 3, 77, 31, 50, 1 })`.
- Without L9: 352 tokens (versus 354); removes `{`.
- Without L10: 328 tokens (versus 354); removes `int lo = 0, hi = 15, found = -1;`.
- Without L11: 337 tokens (versus 354); removes `var probes = new List<int>();`.
- Without L12: 343 tokens (versus 354); removes `while (lo <= hi)`.
- Without L13: 351 tokens (versus 354); removes `{`.
- Without L14: 333 tokens (versus 354); removes `int mid = (lo + hi) / 2;`.
- Without L15: 344 tokens (versus 354); removes `probes.Add(mid);`.
- Without L16: 339 tokens (versus 354); removes `if (values[mid] == target)`.
- Without L17: 350 tokens (versus 354); removes `{`.
- Without L18: 344 tokens (versus 354); removes `found = mid;`.
- Without L20: 350 tokens (versus 354); removes `}`.
- Without L21: 339 tokens (versus 354); removes `if (values[mid] < target)`.
- Without L22: 340 tokens (versus 354); removes `lo = mid + 1;`.
- Without L23: 350 tokens (versus 354); removes `else`.
- Without L24: 340 tokens (versus 354); removes `hi = mid - 1;`.
- Without L25: 351 tokens (versus 354); removes `}`.
- Without L26: 321 tokens (versus 354); removes `string result = found >= 0 ? "index " + found : "not found";`.
- Without L27: 317 tokens (versus 354); removes `Console.WriteLine($"{target}: probes {string.Join(" ", probes)} -> {result}");`.
