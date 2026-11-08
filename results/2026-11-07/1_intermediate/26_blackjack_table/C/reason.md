# Task B selection — C

## Answer requirements shared across languages

1. Identify the complete hand-display path: ordered card labels, ace-adjusted total/soft flag, split-sensitive blackjack precedence, bust, soft and ordinary status, and the final status delimiters.
2. Explain changing only displayed status parentheses to square brackets and how player/dealer consumers receive the same revised formatter; preserve hand data, values and outcome rules.

## Selected source locations

- `main.c`: 128, 132, 133, 134, 135, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 154, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 170, 176

## Evidence and language semantics

show_hand writes ordered cards and all four status cases directly to stdout; each of its four literals contains the delimiters. const Hand pointers and local Total expose the nonmutating path; hand_line and dealer_line call it. The read-only display path computes the same total and chooses blackjack before bust, soft and ordinary totals. Cards keep their input order and spaces. Only the parentheses enclosing the chosen status are representation literals to replace with brackets; card values, split flags, calculations and outcome consumers need no change. The selected player/dealer calls demonstrate propagation through the existing formatter.

## Minimization and alternatives

Kept card-label/point semantics, total and blackjack calculations, the complete status-formatting operation and representative player/dealer consumers. Standard join/interpolation/Display/toString formatting is followed only through custom wrappers. Dealing, mutations, payouts, rule parsing and every repeated call site add no additional delimiter or status case. Selecting only the final format line would omit status precedence and split/soft semantics; including outcome implementations would not support a display-only change. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 573 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
