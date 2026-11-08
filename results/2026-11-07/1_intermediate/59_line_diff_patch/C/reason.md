# Task B selection — C

## Answer requirements shared across languages

1. Explain recognition of @@ -oldRange +newRange @@, signed range splitting, decimal parsing, omitted count1 and start0 permitted only for count0.
2. Trace context/deletion/addition body consumption against both counts and construction of the parsed hunk.
3. Compare X and X,0; distinguish malformed header, truncated body, bad/overflowing body and no-change errors with their reported line.

## Selected source locations

- `main.c`: 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 776, 777, 778, 779, 780, 781, 782, 783, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833

## Evidence and language semantics

parse_number/pair enforce one-to-four decimal digits and an optional single comma. parse_range applies signs, omitted count1 and start0 only with count0. parse_patch records header/body line numbers, counts each kind, distinguishes EOF from invalid lines, rejects no changes and returns populated PatchHunk entries or an error string plus line. A range X means startX,count1; X,0 means startX,count0 and consumes no line on that side. Thus0 alone is invalid, while0,0 is allowed by the range parser. Space-prefixed context contributes to both counts, minus only old and plus only new; parsing continues until both declared counts are met. EOF while either remains produces truncated hunk at the original header line; a malformed range/delimiter produces bad hunk header at that header, and an encountered invalid or overflowing body line produces bad hunk line at its own line. A new @@ line encountered before the body counts are met is a bad hunk line rather than EOF truncation. A body with no additions/deletions, including both counts zero, fails no changes. Hunk application, matching offsets/fuzz, document mutation and diff generation are outside this parse operation and were excluded.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1642 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
