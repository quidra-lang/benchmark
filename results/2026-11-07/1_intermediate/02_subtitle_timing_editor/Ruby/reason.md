# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace a valid two-cue SRT scenario from block separation, index/timestamp/text parsing and storage to MERGE command dispatch, arity/numeric/range validation and its error output.
2. Locate the strict gap comparison and explain changing only it to accept equality; retain dialogue exclusion, greedy wrapping at 42 columns and the at-most-two-line eligibility test.
3. Trace the evolving retained-cue state: the first identity/start survive, end becomes the maximum, text is replaced by wrapped combined text, joins increment, rejected pairs remain separate, and subsequent comparisons use the evolving end.
4. Explain the MERGE summary and a following PRINT/SRT export, including an equal-gap success example, a dialogue or over-two-line rejection and unchanged malformed-command behavior.

## Selected source locations

- `main.rb`: 1, 4, 5, 7, 11, 19, 20, 24, 25, 28, 29, 30, 31, 32, 40, 41, 42, 43, 66, 67, 68, 84, 85, 88, 89, 92, 93, 94, 95, 96, 97, 98, 101, 142, 143, 144, 145, 146, 147, 148, 149, 150, 153, 154, 156, 157, 158, 159, 160, 161, 162, 164, 165, 166, 167, 168, 169, 173, 174, 177, 178, 179, 181, 182, 193, 194, 196, 198, 209, 212, 213, 259, 262, 263, 264, 265, 328, 329, 330, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 484, 485, 621, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 637

## Evidence and language semantics

A concrete trace uses SRT cues 7 (00:00:00,000 to 00:00:01,000, text alpha) and 8 (00:00:01,100 to 00:00:02,100, text beta), then MERGE 100 and PRINT. The current strict test rejects their 100 ms gap; changing that gap test alone to inclusive accepts it. The retained cue remains index 7/start 0 ms, has end 2100 ms and text alpha beta; summary is MERGE merged=1 cues=1, and PRINT emits index 7 and 00:00:00,000 --> 00:00:02,100 followed by alpha beta and a blank separator. A text beginning "- " or combined greedy wrapping requiring three lines leaves two cues and no join, rather than raising an error. A malformed/extra argument or a gap above 60000 follows the selected validation/error path before the merging mutation. The selected merge loop also shows that any next cue is compared against the last retained, already-extended cue. The selected arity/schema declarations and numeric parser resolve MERGE to one decimal gap in 0..60000 and PRINT to no arguments. Input splitting and load code establish original cue index, parsed millisecond start/end and text storage; selected dispatch/error handling establishes validation before merge and the ERROR prefix. Ruby hashes are objects and merged stores the same retained hash referenced by previous; []= on its end/text keys changes that retained cue and leaves index/start intact. The wrap/dialogue implementations establish the exact greedy 42-column and hyphen-space tests, while standard collection/string/formatting semantics suffice for the remaining operations. The selected PRINT path requires no markup helper.

## Minimization and alternatives

Compared a boundary-only excerpt with this end-to-end slice: the shorter candidate cannot establish loading, validation, text eligibility, state propagation or export. Conversely, including all command branches, markup conversion, validation reports, statistics, undo storage and other edit operations contributes no required fact. PRINT is the lowest-cost subsequent export because it needs no VTT/ASS conversion. Bare delimiters, cleanup-only operations and unrelated schema entries are omitted where their absence loses no fact; a combined source line is retained verbatim when it also contains irrelevant branches. Standard formatting/string/collection operations use documented semantics. The selected custom helpers are retained only where their body, rather than its name, establishes needed behavior. A final excerpt-only review removed empty lines and standalone closing delimiters that add no necessary information; control conditions, meaningful else/continue/break lines, field bindings and result propagation remain.

The excerpt contains 1770 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
