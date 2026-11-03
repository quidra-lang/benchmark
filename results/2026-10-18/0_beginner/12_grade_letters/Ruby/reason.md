# Task B selection: 12_grade_letters / Ruby

## Common answer requirements

1. Identify the A/B decision boundary and its letter/index mapping.
2. Keep the same selected grade feeding both the student result and the grade-count update; preserve C/D/F and output order.

## Answer supported by the excerpt

Lower the first A threshold from 90 to 85. The following at-least-80 branch then handles 80 through 84 because the A case has already captured 85 and above. Keep C, D and F thresholds and the letter order unchanged. Both each student result and the matching count continue to use the same classification, so no second independent threshold change or manually altered totals are needed. In an explicit interval match, the A lower bound becomes 85 and the B upper bound can be tightened to 84 to keep the intervals disjoint.

## Source evidence and dependencies

Selected `main.rb` lines: 4-6. The excerpt preserves these complete lines in their original order and indentation.

The threshold expression and letter mapping identify A and B, including zero-based versus one-based grade indices. The count update and student result establish that the same classification drives both requested results. Literal score data, unchanged lower-grade branches on separate lines, and unchanged final table traversal add no independent edit.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Editing printed letters or final totals would not update the shared classification and would require more unrelated sites. The selected shared decision plus its direct consumers demonstrates the smaller sufficient change. Where numeric indices are used, omitting the mapping would lose which boundary denotes A.

The selected excerpt contains **94 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 94 tokens; the complete source contains 217 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
