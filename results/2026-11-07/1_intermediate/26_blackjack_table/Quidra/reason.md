# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the complete hand-display path: ordered card labels, ace-adjusted total/soft flag, split-sensitive blackjack precedence, bust, soft and ordinary status, and the final status delimiters.
2. Explain changing only displayed status parentheses to square brackets and how player/dealer consumers receive the same revised formatter; preserve hand data, values and outcome rules.

## Selected source locations

- `main.qui`: 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 236, 267

## Evidence and language semantics

hand_text takes const Hand, maps ordered cards to labels and joins them, then returns interpolation with the status. hand_line and dealer emit consume it directly; const data and local status isolate the representation change. The read-only display path computes the same total and chooses blackjack before bust, soft and ordinary totals. Cards keep their input order and spaces. Only the parentheses enclosing the chosen status are representation literals to replace with brackets; card values, split flags, calculations and outcome consumers need no change. The selected player/dealer calls demonstrate propagation through the existing formatter.

## Minimization and alternatives

Kept card-label/point semantics, total and blackjack calculations, the complete status-formatting operation and representative player/dealer consumers. Standard join/interpolation/Display/toString formatting is followed only through custom wrappers. Dealing, mutations, payouts, rule parsing and every repeated call site add no additional delimiter or status case. Selecting only the final format line would omit status precedence and split/soft semantics; including outcome implementations would not support a display-only change.

The excerpt contains 457 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
