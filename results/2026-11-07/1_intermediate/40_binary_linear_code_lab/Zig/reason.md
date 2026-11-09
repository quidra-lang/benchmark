# Task B selection — Zig

## Answer requirements shared across languages

1. Establish the left-to-right message/codeword/syndrome bit convention from the actual text or packed-bit conversions, dimensions, and iteration indices.
2. Trace each message position to its generator row and XOR contribution for matrix encoding; derive how flipping a codeword position changes syndrome by the corresponding parity-check column.
3. Include the actual cyclic polynomial encoder and parity-check conversion where present, distinguishing systematic shifted-message/remainder encoding from direct generator-row selection while preserving the same column convention.

## Selected source locations

- `main.zig`: 55, 56, 58, 59, 61, 62, 64, 65, 70, 71, 83, 84, 85, 86, 87, 90, 91, 109, 110, 111, 112, 113, 114, 116, 117, 121, 123, 124, 126, 127, 128, 130, 131, 132, 262, 263, 264, 265, 270, 271, 278, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 298, 299, 300, 301, 474, 475, 476, 478, 480, 481, 483, 484, 485, 486, 487, 488, 489, 490, 491

## Evidence and language semantics

The excerpt fixes a common high-order-first convention: the leftmost displayed bit occupies the highest power of two. Matrix ENCODE tests message bit i against generator row i and XORs that entire row. For any codeword position j, replacing w by w XOR 2^(n-1-j) toggles the parity for exactly those H rows whose j-th bit is 1; the syndrome difference is therefore column j of H, in H-row order. The syndrome fold shifts its previous value left before adding each row parity, so its first row is the leftmost output bit. A valid codeword has zero syndrome under the stipulated correct-code assumption. CYCLIC retains shifted polynomial generator rows but takes the separate systematic encoder branch: shift message by n-k, divide over GF(2), and combine the remainder. Its H construction divides each descending-power unit vector and appends the remainder bits as successive columns; this is why a flipped bit has the same position meaning in the polynomial representation. The selected division lines show cancellation by XOR at the degree difference; quotient accumulation is irrelevant to the selected remainder and is omitted.

Zig for(slice,0..) is zero based. Matrix.add appends at len and slice exposes rows[0..len], so the custom container preserves order. @popCount provides parity; binary base-2 parsing and the Bits formatter use the same bit accessor. @intCast on valid shift counts does not alter their values.

## Minimization and alternatives

An encoder-only excerpt would miss H-row order and cannot justify the single-bit syndrome contribution. A syndrome-only excerpt would not establish which message bit selects which generator row. Omitting the cyclic conversion would wrongly suggest that every ENCODE uses direct generator-row summation. Conversely Gaussian elimination, code enumeration, decoding, leader tables, command-wide validation and unrelated constructors do not determine this interaction and are excluded. The retained tiny arithmetic/conversion loops each supply a required initialization, iteration order, contribution or return. Internal loop and conditional boundaries are retained when they distinguish the repeated contribution from the subsequent result, or separate the polynomial encoder from matrix encoding. Indentation supplies those boundaries in Python and Quidra. Redundant outer declaration boundaries, blank lines, and unused quotient updates are omitted; this is an excerpt, not a standalone program. An alternative selection could inline the relevant helper body at its call sites, but complete-line copying forbids rewriting, and repeating the same definition would increase cost. For matrix codes the correctness of H as a parity-check matrix follows the README valid-program assumption; no extra proof of the nullspace implementation is needed to explain indexing. Compared with 9efb28574 on byte-identical source. The Dart unused yes/no formatter and Quidra redundant dimension validation were removed; all remaining encoding/syndrome/parity witnesses are unchanged.

The excerpt contains 1309 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
