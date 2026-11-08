# Task B selection — Python

## Answer requirements shared across languages

1. Trace a valid two-cue SRT scenario from block separation, index/timestamp/text parsing and storage to MERGE command dispatch, arity/numeric/range validation and its error output.
2. Locate the strict gap comparison and explain changing only it to accept equality; retain dialogue exclusion, greedy wrapping at 42 columns and the at-most-two-line eligibility test.
3. Trace the evolving retained-cue state: the first identity/start survive, end becomes the maximum, text is replaced by wrapped combined text, joins increment, rejected pairs remain separate, and subsequent comparisons use the evolving end.
4. Explain the MERGE summary and a following PRINT/SRT export, including an equal-gap success example, a dialogue or over-two-line rejection and unchanged malformed-command behavior.

## Selected source locations

- `main.py`: 2, 3, 7, 14, 16, 22, 27, 38, 39, 42, 43, 44, 45, 46, 47, 48, 49, 52, 53, 54, 55, 56, 57, 58, 59, 71, 78, 79, 80, 81, 82, 83, 105, 106, 107, 148, 149, 152, 153, 169, 170, 171, 172, 173, 174, 184, 185, 186, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 211, 212, 213, 215, 218, 222, 228, 229, 230, 231, 232, 233, 234, 235, 236, 239, 240, 241, 248, 250, 251, 252, 254, 257, 258, 259, 339, 340, 341, 342, 343, 344, 345, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 656, 657, 658, 659, 660, 661, 662, 663, 664

## Evidence and language semantics

A concrete trace uses SRT cues 7 (00:00:00,000 to 00:00:01,000, text alpha) and 8 (00:00:01,100 to 00:00:02,100, text beta), then MERGE 100 and PRINT. The current strict test rejects their 100 ms gap; changing that gap test alone to inclusive accepts it. The retained cue remains index 7/start 0 ms, has end 2100 ms and text alpha beta; summary is MERGE merged=1 cues=1, and PRINT emits index 7 and 00:00:00,000 --> 00:00:02,100 followed by alpha beta and a blank separator. A text beginning "- " or combined greedy wrapping requiring three lines leaves two cues and no join, rather than raising an error. A malformed/extra argument or a gap above 60000 follows the selected validation/error path before the merging mutation. The selected merge loop also shows that any next cue is compared against the last retained, already-extended cue. SCHEMAS links MERGE to a gap and PRINT to no arguments; integer/argument/parse establish decimal syntax, arity and the inclusive legal 0..60000 domain. The Cue initializer binds source index/start/end/text, and self.cues aliases that loaded collection. The explicit handler entries resolve both operations. Python object reference semantics explain why assigning previous.end/lines updates the retained object while index/start persist; no copy helper is required. Imported textwrap.wrap documents no splitting of long words or hyphens with the selected options.

## Minimization and alternatives

Compared a boundary-only excerpt with this end-to-end slice: the shorter candidate cannot establish loading, validation, text eligibility, state propagation or export. Conversely, including all command branches, markup conversion, validation reports, statistics, undo storage and other edit operations contributes no required fact. PRINT is the lowest-cost subsequent export because it needs no VTT/ASS conversion. Bare delimiters, cleanup-only operations and unrelated schema entries are omitted where their absence loses no fact; a combined source line is retained verbatim when it also contains irrelevant branches. Standard formatting/string/collection operations use documented semantics. The selected custom helpers are retained only where their body, rather than its name, establishes needed behavior. A final excerpt-only review removed empty lines and standalone closing delimiters that add no necessary information; control conditions, meaningful else/continue/break lines, field bindings and result propagation remain.

The excerpt contains 2306 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
