# Task B selection — J

## Answer requirements shared across languages

1. Identify the complete hand-display path: ordered card labels, ace-adjusted total/soft flag, split-sensitive blackjack precedence, bust, soft and ordinary status, and the final status delimiters.
2. Explain changing only displayed status parentheses to square brackets and how player/dealer consumers receive the same revised formatter; preserve hand data, values and outcome rules.

## Selected source locations

- `main.ijs`: 2, 3, 27, 28, 29, 30, 34, 35, 36, 37, 38, 39, 40, 41, 78, 79, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 133, 160, 251

## Evidence and language semantics

hand_text is a dyad: x is the split flag and y is ordered Cards. hand_display extracts the per-hand flag; dealer passes zero. The custom number and join verbs establish the actual output construction, with a single delimiter pair. The read-only display path computes the same total and chooses blackjack before bust, soft and ordinary totals. Cards keep their input order and spaces. Only the parentheses enclosing the chosen status are representation literals to replace with brackets; card values, split flags, calculations and outcome consumers need no change. The selected player/dealer calls demonstrate propagation through the existing formatter.

## Minimization and alternatives

Kept card-label/point semantics, total and blackjack calculations, the complete status-formatting operation and representative player/dealer consumers. Standard join/interpolation/Display/toString formatting is followed only through custom wrappers. Dealing, mutations, payouts, rule parsing and every repeated call site add no additional delimiter or status case. Selecting only the final format line would omit status precedence and split/soft semantics; including outcome implementations would not support a display-only change.

The excerpt contains 486 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
