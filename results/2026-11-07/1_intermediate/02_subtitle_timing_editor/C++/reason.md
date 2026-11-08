# Task B selection — C++

## Answer requirements shared across languages

1. Trace a valid two-cue SRT scenario from block separation, index/timestamp/text parsing and storage to MERGE command dispatch, arity/numeric/range validation and its error output.
2. Locate the strict gap comparison and explain changing only it to accept equality; retain dialogue exclusion, greedy wrapping at 42 columns and the at-most-two-line eligibility test.
3. Trace the evolving retained-cue state: the first identity/start survive, end becomes the maximum, text is replaced by wrapped combined text, joins increment, rejected pairs remain separate, and subsequent comparisons use the evolving end.
4. Explain the MERGE summary and a following PRINT/SRT export, including an equal-gap success example, a dialogue or over-two-line rejection and unchanged malformed-command behavior.

## Selected source locations

- `main.cpp`: 15, 16, 17, 18, 35, 38, 39, 40, 41, 42, 43, 44, 45, 48, 58, 63, 64, 65, 66, 67, 68, 70, 72, 73, 74, 75, 77, 78, 79, 80, 82, 83, 84, 89, 90, 91, 93, 118, 119, 121, 122, 123, 124, 126, 128, 129, 130, 131, 132, 134, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 244, 245, 246, 247, 248, 249, 250, 251, 252, 273, 274, 276, 278, 279, 287, 292, 293, 294, 295, 297, 298, 299, 300, 301, 302, 386, 388, 389, 392, 393, 394, 399, 400, 401, 402, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 518, 520, 521, 657, 659, 660, 661, 662, 663, 664, 665, 666, 667, 670, 671, 672, 673, 674, 675, 676, 681, 683, 684, 686, 687, 688, 689, 690, 691, 692, 693, 694

## Evidence and language semantics

A concrete trace uses SRT cues 7 (00:00:00,000 to 00:00:01,000, text alpha) and 8 (00:00:01,100 to 00:00:02,100, text beta), then MERGE 100 and PRINT. The current strict test rejects their 100 ms gap; changing that gap test alone to inclusive accepts it. The retained cue remains index 7/start 0 ms, has end 2100 ms and text alpha beta; summary is MERGE merged=1 cues=1, and PRINT emits index 7 and 00:00:00,000 --> 00:00:02,100 followed by alpha beta and a blank separator. A text beginning "- " or combined greedy wrapping requiring three lines leaves two cues and no join, rather than raising an error. A malformed/extra argument or a gap above 60000 follows the selected validation/error path before the merging mutation. The selected merge loop also shows that any next cue is compared against the last retained, already-extended cue. The parallel names/schemas arrays resolve MERGE to unsigned and PRINT to zero arguments. unsignedValue and parseArguments establish arity, syntax and 0..60000 validation, with fail caught by main as ERROR. Split and text are custom helpers, so the selected bodies establish token separation and concatenated notices; std::vector push/insert/move and references have standard semantics. Cue &previous refers to result.back(), retaining index/start while its end/text change; moving that result into cues establishes the subsequent export state.

## Minimization and alternatives

Compared a boundary-only excerpt with this end-to-end slice: the shorter candidate cannot establish loading, validation, text eligibility, state propagation or export. Conversely, including all command branches, markup conversion, validation reports, statistics, undo storage and other edit operations contributes no required fact. PRINT is the lowest-cost subsequent export because it needs no VTT/ASS conversion. Bare delimiters, cleanup-only operations and unrelated schema entries are omitted where their absence loses no fact; a combined source line is retained verbatim when it also contains irrelevant branches. Standard formatting/string/collection operations use documented semantics. The selected custom helpers are retained only where their body, rather than its name, establishes needed behavior. A final excerpt-only review removed empty lines and standalone closing delimiters that add no necessary information; control conditions, meaningful else/continue/break lines, field bindings and result propagation remain.

The excerpt contains 3575 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
