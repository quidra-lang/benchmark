## Answer and source evidence

The decoder already depends only on encoded Morse text plus its lookup table. It splits words on " / ", splits each word into complete tokens on one space, does an exact Map/array-key lookup for each token, joins decoded letters with no separator and words with one space. The reverse table pairs . with E and .- with A as distinct complete keys, so neither is a prefix match. To expose a standalone decoder, accept Morse text at the encoded-input site and preserve those stages; no fallback to message letters or table change is needed. Table construction and decoder stages are necessary; the encoder, original message and output are unrelated.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. PHP array/string/arithmetic and formatting operations are interpreted with their standard runtime semantics; no stronger static invariant is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
