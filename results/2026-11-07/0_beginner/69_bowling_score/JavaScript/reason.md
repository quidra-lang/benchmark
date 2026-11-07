## Answer and source evidence

At per-game ingestion normalize every roll with Number(token) in JavaScript/TypeScript or (int) token in PHP, before any strict comparison or addition. The present entry point receives rolls unchanged and immediately uses rolls[index]===10 or $rolls[$position]===10 and adds neighboring rolls; it performs no ingestion conversion. A string "10" would otherwise fail the strict numeric strike comparison, and JS + can concatenate strings. The game binding and first comparisons/addition are sufficient evidence for where conversion must precede existing frame rules; other frame branches and original numeric literal arrays are unnecessary.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. JavaScript uses ordinary Number arithmetic (IEEE 754 double precision); no integer-only static contract is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
