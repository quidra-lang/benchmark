# Task B selection — Java

## Answer requirements shared across languages

1. Identify the source value that supplies all four initial castling rights KQkq.
2. Connect that initial value to the castling-rights field of the starting position.
3. Explain why the rights are initialized independently of the empty move history.

## Selected source locations

- `Main.java`: 7, 94, 97, 324, 367, 384, 387, 524, 526, 527, 529, 530

## Evidence and language semantics

The starting FEN literal supplies KQkq as the third space-separated field. The selected parser extraction and position construction retain that field as the position's rights/castling value. The initial-position construction and empty records/history initializer are separate; rights come from this field value, not from the absence of prior moves.

## Minimization and alternatives

The literal alone would not establish how the custom FEN parser stores its third field, while the parser alone would not establish the starting value. Both links and the separate empty-history construction are retained. Piece placement, legality checks, move generation and later castling-rights removal do not answer this initialization question and are excluded. Only the rights-bearing portions of constructors are retained; unrelated fields are not expanded. Selecting NEW plus every startup step would duplicate evidence already supplied by the default starting-position construction.

The excerpt contains 254 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
