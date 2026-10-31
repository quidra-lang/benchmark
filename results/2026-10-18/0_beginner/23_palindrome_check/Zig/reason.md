# Task B source selection

## Common answer requirements

Trace Step on no pets. through letter filtering/case normalization and palindrome test; identify original phrase preservation in printed output.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The source phrase is Step on no pets. Filtering removes three spaces and the final period; case normalization changes S to s, yielding steponnopets. Comparing that sequence with its reversal, or comparing opposing pairs through the midpoint, finds every pair equal and produces yes. The normalized sequence is a separate string/array; the original phrase remains the input variable read by the output statement. Consequently output retains the original capital S, spaces and final period: Step on no pets. -> yes.



## Source evidence and dependencies

The selected locations in `main.zig` are L12, L15, L17, L18, L19, L20, L21, L22, L25, L26, L27, L28, L29, L32. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L12: `"Step on no pets.",`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L15: `for (phrases) |phrase| {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L17: `var len: usize = 0;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L18: `for (phrase) |c| {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L19: `const lower = std.ascii.toLower(c);`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L20: `if (lower >= 'a' and lower <= 'z') {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L21: `clean[len] = lower;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L22: `len += 1;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L25: `var palindrome = true;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L26: `for (0..len / 2) |i| {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L27: `if (clean[i] != clean[len - 1 - i]) {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L28: `palindrome = false;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L29: `break;`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L32: `try out.print("{s} -> {s}\n", .{ phrase, if (palindrome) @as([]const u8, "yes") else "no" });`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **298 tokens** for the final selected lines. The prior candidate measured 264 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final original source lines: L7, L12, L15, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L29, L30, L31, L32.
- L7: `    const phrases = [_][]const u8{` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.
- L23: `            }` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.
- L24: `        }` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.
- L30: `            }` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.
- L31: `        }` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final selection: 298 metric tokens; contiguous span L7–L32: 394 tokens; complete source: 512 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
