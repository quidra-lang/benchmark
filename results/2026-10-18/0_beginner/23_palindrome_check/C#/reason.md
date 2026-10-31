# Task B source selection

## Common answer requirements

Trace Step on no pets. through letter filtering/case normalization and palindrome test; identify original phrase preservation in printed output.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The source phrase is Step on no pets. Filtering removes three spaces and the final period; case normalization changes S to s, yielding steponnopets. Comparing that sequence with its reversal, or comparing opposing pairs through the midpoint, finds every pair equal and produces yes. The normalized sequence is a separate string/array; the original phrase remains the input variable read by the output statement. Consequently output retains the original capital S, spaces and final period: Step on no pets. -> yes.



## Source evidence and dependencies

The selected locations in `Program.cs` are L7, L9, L11, L12, L13, L14. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L7: `"Step on no pets.", "No lemon, no melon",`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L9: `foreach (string phrase in phrases)`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L11: `string normalized = string.Concat(phrase.Where(ch => ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z'))`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L12: `.ToLowerInvariant();`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L13: `bool palindrome = normalized.SequenceEqual(normalized.Reverse());`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L14: `Console.WriteLine($"{phrase} -> {(palindrome ? "yes" : "no")}");`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **170 tokens** for the final selected lines. The prior candidate measured 161 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final original source lines: L4, L7, L9, L10, L11, L12, L13, L14.
- L4: `string[] phrases =` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.
- L10: `{` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final selection: 170 metric tokens; contiguous span L4–L14: 227 tokens; complete source: 242 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
