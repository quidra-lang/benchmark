# Task B selection: 91_priority_queue_tasks / Quidra

## Answer requirements

Suppose equal-priority tasks are ordered by ascending task name instead of insertion order. Explain the complete path from parsing the sixteen operations through queue insertion/comparison, each run removal and final remaining-order output. Identify the comparison change and derive the six run lines and remaining line under it, showing why the final list must use the same rule as repeated removals.

## Answer and source evidence

Replace insertion-sequence tie breaking with ascending task name after priority. Preserve parsing and priority values; store/compare a key equivalent to (priority,name) and use it for both removal and remaining order. The six run lines are deploy(priority1), test(2), email(3), review(2), build(1), lint(3), each rendered `run: NAME (priority P)`. Remaining is `remaining: report docs backup cleanup`. Final remaining output must sort/drain with the same comparison as repeated takes, otherwise equal-priority backup/cleanup order could disagree.

PriorityQueue<string,int> currently supplies stable equal-priority insertion order because tie_before is omitted. Keep the numeric priority type and supply its documented tie_before callback comparing task-name strings; both normal and final takes then share that comparison, with no change to the numeric priority field.

Selected `main.qui` lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
