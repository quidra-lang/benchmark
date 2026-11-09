# Task B selection: 73_merge_sort_inversions / Quidra

## Answer requirements

Suppose each merge-trace line gains a suffix inversions=K containing the cumulative count at that merge's completion. Explain the dependency between right-side selections during merging, their inversion increments, recursive merge completion order and trace emission. Identify where the suffix must read the count so it includes prior merges and the just-completed merge, while the final sorted and inversions lines keep their formats.

## Answer and source evidence

A right-side choice while left values remain contributes the number of unmerged left values. The comparison, left-index advancement, right-side selection/advancement and increment establish that dependency. The increment is `int(#first) - i`, because `i` is the zero-based head of the remaining left sequence. Both recursive calls finish in source order: left child, right child, then the current merge and its trace. Read the cumulative count at the selected merge-trace emission, after the current loop has finished, and append ` inversions=K` there. For a trace emitted in several writes, insert the suffix after its value-writing loop and before its newline. Do not change the final sorted or inversion-total renderers.

The `int &inversions` parameter and `&inversions` call arguments share the caller binding initialized to zero. Both recursive children and the current merge update that same accumulator.

Selected `main.qui` lines: 3, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 24, 27, 28. Every line is complete, verbatim and in source order.

## Language semantics and minimization

The selected scope/binding or parameter/result chain establishes that the count includes earlier merges. The bounds, comparison, index progression and increment establish the remaining-left contribution; recursion and the loop boundary establish when the trace reads it. Structural delimiters are retained where they show the trace is outside the incrementing loop or distinguish the caller from the routine. Ordinary synchronous calls, lexical scope, reference/value semantics and standard output operations supply the language facts.

Remainder-draining operations and sorted-array writeback do not update the count and are unnecessary for locating its trace-time read, so they are omitted. Unaffected final renderers are also omitted: the change is confined to the merge trace. Independent temporary-result initialization and concrete input values are excluded unless they share a needed physical binding/call line. A caller is omitted when lexical binding already establishes the shared count; it is retained when needed to connect a count parameter or default value to its initialization. A declaration-only excerpt would lose the increment and completion-order evidence; selecting the whole merge would add the unrelated operations just excluded.

The selected source costs 302 tokens with `metric/tokenizer.py` (the previous excerpt cost 295). These counts describe the excerpt, not the explanation. This is source analysis under the Task B assumptions; no Task A program was compiled, built, run or tested.
