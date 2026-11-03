# Task B selection: 16_collatz_steps / Quidra

## Common answer requirements

1. Explain why start 1 has zero operations but an initial maximum of one.
2. Trace start 6, deriving its operation count and maximum.
3. Identify how the starting value enters the maximum before operations are counted.

## Implementation decision

Task A remains unchanged. Minimize both language excerpts by omitting the input list and its outer loop; keep every state initialization and transition needed by the trace.

## Evidence and answer

The selected int n = start explicitly binds the question-supplied starting value to the evolving integer; steps starts at zero and largest starts at n before the while guard. Thus start one executes no body and keeps maximum one. For six the selected transition produces 3,10,5,16,8,4,2,1: eight operations and maximum sixteen. The step increment and largest update show their distinct timing. The question supplies both scalar starting values; the other literal starts and their collection traversal add no needed recurrence or initialization fact. The Python tuple initializer supports the same boundary.

## Selection and minimization

Selected complete main.qui lines: 3, 4, 5, 6, 7, 8, 9, 10. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 163 → 163; Task B 139 → 101. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
