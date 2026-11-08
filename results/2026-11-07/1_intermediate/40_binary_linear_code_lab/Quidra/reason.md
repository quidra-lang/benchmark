# Task B selection — Quidra

## Answer requirements shared across languages

1. Establish the left-to-right message/codeword/syndrome bit convention from the actual text or packed-bit conversions, dimensions, and iteration indices.
2. Trace each message position to its generator row and XOR contribution for matrix encoding; derive how flipping a codeword position changes syndrome by the corresponding parity-check column.
3. Include the actual cyclic polynomial encoder and parity-check conversion where present, distinguishing systematic shifted-message/remainder encoding from direct generator-row selection while preserving the same column convention.

## Selected source locations

- `main.qui`: 104, 105, 110, 111, 113, 114, 115, 116, 117, 118, 120, 121, 122, 123, 124, 125, 127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 138, 155, 157, 159, 160, 162, 163, 229, 230, 231, 244, 245, 246, 247, 248, 249, 250, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 264, 265, 266, 267, 268, 352, 353, 354, 357, 360, 361, 362, 363, 364, 365, 366, 367

## Evidence and language semantics

The excerpt fixes a common high-order-first convention: the leftmost displayed bit occupies the highest power of two. Matrix ENCODE tests message bit i against generator row i and XORs that entire row. For any codeword position j, replacing w by w XOR 2^(n-1-j) toggles the parity for exactly those H rows whose j-th bit is 1; the syndrome difference is therefore column j of H, in H-row order. The syndrome fold shifts its previous value left before adding each row parity, so its first row is the leftmost output bit. A valid codeword has zero syndrome under the stipulated correct-code assumption. CYCLIC retains shifted polynomial generator rows but takes the separate systematic encoder branch: shift message by n-k, divide over GF(2), and combine the remainder. Its H construction divides each descending-power unit vector and appends the remainder bits as successive columns; this is why a flipped bit has the same position meaning in the polynomial representation. The selected division lines show cancellation by XOR at the degree difference; quotient accumulation is irrelevant to the selected remainder and is omitted.

Quidra indices and for-column ranges are zero based. parse_bits folds text left to right; bit(size,column) supplies its matching power of two. generator.indices() and parity[] preserve stored order. OR combines disjoint systematic message and remainder fields.

## Minimization and alternatives

An encoder-only excerpt would miss H-row order and cannot justify the single-bit syndrome contribution. A syndrome-only excerpt would not establish which message bit selects which generator row. Omitting the cyclic conversion would wrongly suggest that every ENCODE uses direct generator-row summation. Conversely Gaussian elimination, code enumeration, decoding, leader tables, command-wide validation and unrelated constructors do not determine this interaction and are excluded. The retained tiny arithmetic/conversion loops each supply a required initialization, iteration order, contribution or return; brace-only/blank lines and unused quotient updates are omitted. An alternative selection could inline the relevant helper body at its call sites, but complete-line copying forbids rewriting, and repeating the same definition would increase cost. For matrix codes the correctness of H as a parity-check matrix follows the README valid-program assumption; no extra proof of the nullspace implementation is needed to explain indexing.

The excerpt contains 1092 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
