# Task B selection: 69_bowling_score / Rust

## Common answer requirements

Identify the cumulative state/output and explain producing ten individual scores in order, preserving strike/spare bonuses in their originating frame and limiting the tenth frame to its own rolls and current spacing/label.

## Supported analysis

Keep every existing cumulative score unchanged, including all strike/spare bonuses in their originating frame and the tenth-frame own-roll contribution. Change only the value printed/appended at each score-output site: replace each cumulative value with its difference from the preceding cumulative value, taking the preceding value as zero for frame one. A previous-cumulative variable initialized once per game and updated after each emission implements that transformation; the tenth value is the final cumulative total minus the ninth cumulative total, so earlier frames are not added again. Where a complete frame-local score already exists, print that score directly instead of total. Existing output order/labels/single-space separators remain. The selected producer/consumer sites identify this local edit without changing the scoring algorithm.

The cumulative output stream is the sufficient dependency: adjacent differences recover individual frame contributions while preserving existing bonuses, which are already included before each emission. Scoring branches and roll-index updates remain unchanged and are not needed to explain this output transformation. The local score is bound within each frame and added to total before print; printing score preserves the existing complete frame contribution. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 14 | 15 | `        for frame in 0..10 {` |
| 15 | 8 | `            let score;` |
| 32 | 10 | `            total += score;` |
| 33 | 17 | `            print!(" {}", total);` |
| 34 | 4 | `        }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **54 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 769 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 76 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
