# Task B source selection

## Common answer requirements

Identify case-folding/filtering/count indexing and output ordering; separate A-Z/a-z, ignore other characters, uppercase first then lowercase, emit only present letters with preserved case and format.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Remove lowercasing and count the original character case. For fixed arrays use52 counters indexed by uppercase A-Z then lowercase a-z; explicitly accept only those ranges and map output indices back to their original-case letter. For maps retain the original-case key and accept both ASCII ranges; ordinary ASCII sorting puts uppercase before lowercase. Alphabet-scan implementations should scan ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz against the unnormalized sentence. Preserve nonzero-only output and punctuation/newline formatting. Any old modulo26 merge, lowercase-only filter, alphabet size26 or lowercase output offset must change along with the folding operation.



## Source evidence and dependencies

The selected locations in `main.rs` are L3, L4, L5, L6, L7, L10, L12. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L3: `let mut counts = [0; 26];`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L4: `for c in sentence.bytes() {`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L5: `let c = c.to_ascii_lowercase();`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L6: `if c.is_ascii_lowercase() {`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L7: `counts[(c - b'a') as usize] += 1;`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L10: `for (i, n) in counts.iter().enumerate() {`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.
- L12: `println!("{}: {}", (b'a' + i as u8) as char, n);`. This line supplies current case folding, accepted character ranges, merged counter storage/indexing or output alphabet/order; it identifies an affected dependency of separate case counts.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **157 tokens** for the selected original complete lines. A contiguous-context alternative spanning L3–L12 costs **177 tokens**; the entire source costs **221 tokens**. The selected set plus the additional context line L1 costs **165 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
