# Task B selection — Java

## Answer requirements shared across languages

1. Identify the complete hand-display path: ordered card labels, ace-adjusted total/soft flag, split-sensitive blackjack precedence, bust, soft and ordinary status, and the final status delimiters.
2. Explain changing only displayed status parentheses to square brackets and how player/dealer consumers receive the same revised formatter; preserve hand data, values and outcome rules.

## Selected source locations

- `Main.java`: 16, 17, 18, 160, 161, 162, 168, 169, 170, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 316, 338, 406

## Evidence and language semantics

Hand.toString and Card.toString implement the standard formatting hooks. emit uses String.format through format, whose %s invokes Hand.toString; one append pair surrounds the status. The read-only display path computes the same total and chooses blackjack before bust, soft and ordinary totals. Cards keep their input order and spaces. Only the parentheses enclosing the chosen status are representation literals to replace with brackets; card values, split flags, calculations and outcome consumers need no change. The selected player/dealer calls demonstrate propagation through the existing formatter.

## Minimization and alternatives

Kept card-label/point semantics, total and blackjack calculations, the complete status-formatting operation and representative player/dealer consumers. Standard join/interpolation/Display/toString formatting is followed only through custom wrappers. Dealing, mutations, payouts, rule parsing and every repeated call site add no additional delimiter or status case. Selecting only the final format line would omit status precedence and split/soft semantics; including outcome implementations would not support a display-only change.

The excerpt contains 664 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
