# Task B selection — Zig

## Answer requirements shared across languages

1. Identify the source value that supplies all four initial castling rights KQkq.
2. Connect that initial value to the castling-rights field of the starting position.
3. Explain why the rights are initialized independently of the empty move history.

## Selected source locations

- `main.zig`: 55, 248, 250, 287, 288, 293, 305, 310, 317, 318, 541

## Evidence and language semantics

The valid starting FEN supplies KQkq as the third field. The parser starts the rights bitmask at zero, maps each character to its index in KQkq, and ORs 1 shifted by that index into the rights field. All four iterations produce bits 0–3, hence mask 15. The initialized position and empty move history are separately constructed; the history is not used to infer or derive rights.

## Minimization and alternatives

The literal alone would not establish how the custom FEN parser stores its third field, while the parser alone would not establish the starting value. Both links and the separate empty-history construction are retained. Piece placement, legality checks, move generation and later castling-rights removal do not answer this initialization question and are excluded. Only the rights-bearing portions of constructors are retained; unrelated fields are not expanded. Selecting NEW plus every startup step would duplicate evidence already supplied by the default starting-position construction.

The excerpt contains 326 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
