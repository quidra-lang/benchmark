# Task B source selection

## Common answer requirements

Trace Step on no pets. through letter filtering/case normalization and palindrome test; identify original phrase preservation in printed output.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The source phrase is Step on no pets. Filtering removes three spaces and the final period; case normalization changes S to s, yielding steponnopets. Comparing that sequence with its reversal, or comparing opposing pairs through the midpoint, finds every pair equal and produces yes. The normalized sequence is a separate string/array; the original phrase remains the input variable read by the output statement. Consequently output retains the original capital S, spaces and final period: Step on no pets. -> yes.



## Source evidence and dependencies

The selected locations in `Main.java` are L7, L8, L9, L10, L11. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L7: `"Step on no pets.", "No lemon, no melon"};`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L8: `for (String phrase : phrases) {`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L9: `String normalized = phrase.replaceAll("[^A-Za-z]", "").toLowerCase(Locale.ROOT);`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L10: `boolean palindrome = normalized.equals(new StringBuilder(normalized).reverse().toString());`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.
- L11: `System.out.println(phrase + " -> " + (palindrome ? "yes" : "no"));`. This line supplies the original phrase, separate normalized-letter sequence, reversal/pair comparison or original-text output; these connect steponnopets to yes without changing the printed phrase.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **166 tokens** for the final selected lines. The prior candidate measured 155 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final original source lines: L5, L7, L8, L9, L10, L11.
- L5: `        String[] phrases = {` — Associate the supplied Step on no pets. literal with the actual phrase sequence/iteration. Where normalization or comparison uses explicit blocks, finish that region before testing the fully normalized sequence or printing the retained original phrase.

Final selection: 166 metric tokens; contiguous span L5–L11: 220 tokens; complete source: 264 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
