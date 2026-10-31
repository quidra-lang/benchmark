# Task B selection: 66_fisher_yates_shuffle / Julia

## Common answer requirements

Trace the first two MINSTD updates and swap indices/card positions; establish one random update per shuffle iteration even for self-swaps, and identify arithmetic representation keeping the intermediate product exact.

## Supported analysis

The seed is 2026. At i=51 the product is 97,797,046, below the modulus, so the new state is 97,797,046 and j=22. Swap zero-based positions 51 and 22: KC and TH exchange. At i=50 the product is 4,720,761,207,466; modulo 2,147,483,647 yields 592,151,360 and j=50. This is a self-swap of QC at position 50, which leaves it unchanged. The state update is unconditional inside the descending shuffle loop and occurs before choosing j or swapping, so even that self-swap consumes one generator value. The maximum possible product is below 2^47, which fits the selected wide-integer or exact-number arithmetic described below. Deck initialization and rank/suit mapping establish card identities without relying on final printed deck output.

The platform Int used by the integer seed and constants has sufficient range for the <2^47 product; physical deck indices are i+1,j+1. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.jl`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 36 | `    deck = [string(rank, suit) for suit in "SHDC" for rank in "A23456789TJQK"]` |
| 3 | 10 | `    state = 2026` |
| 4 | 15 | `    for i = 51:-1:1` |
| 5 | 27 | `        state = state*48271 % 2147483647` |
| 6 | 16 | `        j = state % (i+1)` |
| 7 | 34 | `        deck[i+1], deck[j+1] = deck[j+1], deck[i+1]` |
| 8 | 3 | `    end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **141 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 197 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 146 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
