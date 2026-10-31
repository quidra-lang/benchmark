# Task B selection: 83_topological_sort / Java

## Common answer requirements

Identify alphabetically-last eligible-course selection at each step while preserving eligibility recomputation, termination, order formats and ascending cycle remainder.

## Answer and source dependencies

Change the eligible-course selector only: reverse the name comparison from less-than to greater-than, choose the last matching index in an ascending name list, or remove the last element of the ascending ready list. Retain readiness recomputation after each selected course. Do not reverse the shared alphabetical course list or change the remainder sorter, because the cycle line must remain ascending. The existing loop stops when no course is available; changing which eligible element is selected does not change this stop condition.



## Scope and dependency evidence checked after independent review

Change only the eligible-course selector: reverse the explicit lexical best comparison, use last/max rather than first/min on the ascending eligible sequence, or remove the ascending scan early break so the last eligible item wins. Retained ordering, index-to-name mapping and current eligibility predicate locate this edit. Leave prerequisite updates and enclosing repetition unchanged so eligibility is reconsidered after each choice; unchanged cycle construction and output formatting require no edit and are omitted. In ready-queue variants the initial and repeated sorts establish that selecting the other end remains valid after newly eligible courses enter.

Source: `Main.java`. Selected original locations: L8,L9,L20,L25.

- L8: `        String[] names = Arrays.stream(original).sorted().toArray(String[]::new);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        int n = names.length;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            int next = IntStream.range(0, n).filter(i -> !taken[i] && degree[i] == 0).findFirst().orElse(-1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            order.add(names[next]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **114 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 172 tokens. The contiguous original span L8–L25 costs 336 tokens; the complete original source costs 979 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 84 tokens; removes `String[] names = Arrays.stream(original).sorted().toArray(String[]::new);` from the dependency chain described above.
- Without L9: 101 tokens; removes `int n = names.length;` from the dependency chain described above.
- Without L20: 57 tokens; removes `int next = IntStream.range(0, n).filter(i -> !taken[i] && degree[i] == 0).findFirst().orElse(-1);` from the dependency chain described above.
- Without L25: 100 tokens; removes `order.add(names[next]);` from the dependency chain described above.
