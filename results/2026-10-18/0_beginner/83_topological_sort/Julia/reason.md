# Task B selection: 83_topological_sort / Julia

## Common answer requirements

Identify alphabetically-last eligible-course selection at each step while preserving eligibility recomputation, termination, order formats and ascending cycle remainder.

## Answer and source dependencies

Change the eligible-course selector only: reverse the name comparison from less-than to greater-than, choose the last matching index in an ascending name list, or remove the last element of the ascending ready list. Retain readiness recomputation after each selected course. Do not reverse the shared alphabetical course list or change the remainder sorter, because the cycle line must remain ascending. The existing loop stops when no course is available; changing which eligible element is selected does not change this stop condition.



## Scope and dependency evidence checked after independent review

Change only the eligible-course selector: reverse the explicit lexical best comparison, use last/max rather than first/min on the ascending eligible sequence, or remove the ascending scan early break so the last eligible item wins. Retained ordering, index-to-name mapping and current eligibility predicate locate this edit. Leave prerequisite updates and enclosing repetition unchanged so eligibility is reconsidered after each choice; unchanged cycle construction and output formatting require no edit and are omitted. In ready-queue variants the initial and repeated sorts establish that selecting the other end remains valid after newly eligible courses enter.

Source: `main.jl`. Selected original locations: L10,L12,L13,L15.

- L10: `    alphabetical = sort(courses)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        index =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            findfirst(course -> !(course in taken) && indegree[course] == 0, alphabetical)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        course = alphabetical[index]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **60 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 91 tokens. The contiguous original span L10–L15 costs 77 tokens; the complete original source costs 657 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 50 tokens; removes `alphabetical = sort(courses)` from the dependency chain described above.
- Without L12: 54 tokens; removes `index =` from the dependency chain described above.
- Without L13: 27 tokens; removes `findfirst(course -> !(course in taken) && indegree[course] == 0, alphabetical)` from the dependency chain described above.
- Without L15: 49 tokens; removes `course = alphabetical[index]` from the dependency chain described above.
