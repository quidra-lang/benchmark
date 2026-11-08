# Task B selection — R

## Answer requirements shared across languages

1. Trace NEW replacing an arbitrary previous board by an otherwise empty board with W at d4/e5 and B at e4/d5.
2. Establish black to move, nonterminal status, empty history/redo, and OK; identify the resulting state retained for the next query.
3. Show startup uses the same explicit initial-value contract without inferring it from move generation.

## Selected source locations

- `main.R`: 100, 101, 102, 103, 104, 340, 341, 342, 343, 344, 345, 346, 350, 351, 352, 353, 358, 359, 360, 361, 624, 625, 626

## Evidence and language semantics

The initial-board builder writes the four central discs into a fresh empty 64-cell board. Zero-based positions 27/36 are d4/e5 and 28/35 are e4/d5; one-based host arrays use positions 28/37 and 29/36. The selected NEW branch invokes reset and emits OK. Reset directly installs the initial board, black side, false terminal flag and empty history/redo, so all later queries see those stored values regardless of the previous state. The startup constructor/initializer establishes the same values, either by calling reset or by explicit field defaults. C zeroes the Game with memset, which sets its integer history lengths and boolean over to zero; C#/Java/Go zero-initialization likewise provides false/empty fields where omitted. Zig clears the active history/redo lengths, leaving backing array bytes irrelevant. Swift stores ASCII codes 46, 87 and 66 for ., W and B. These are language guarantees, not values inferred from legal-move generation. 

## Minimization and alternatives

The board builder, reset writes, NEW-to-reset/OK call and startup initialization each support a distinct required fact. Query algorithms, legal-move generation, old-state snapshots, undo implementation and solver caches cannot alter what NEW installs and are omitted. A second full query path would duplicate the stored-state evidence. For restore helpers, only its assignments used by reset are included; for direct field assignment no helper is added. Omitting startup would fail the explicit startup requirement; omitting history/redo clears would leave prior-game state unspecified.

The excerpt contains 286 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
