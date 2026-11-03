# Task B selection: 83_topological_sort / Lua

## Common answer requirements

Identify alphabetically-last eligible-course selection at each step while preserving eligibility recomputation, termination, order formats and ascending cycle remainder.

## Answer and source dependencies

Change the eligible-course selector only: reverse the name comparison from less-than to greater-than, choose the last matching index in an ascending name list, or remove the last element of the ascending ready list. Retain readiness recomputation after each selected course. Do not reverse the shared alphabetical course list or change the remainder sorter, because the cycle line must remain ascending. The existing loop stops when no course is available; changing which eligible element is selected does not change this stop condition.



## Scope and dependency evidence checked after independent review

Change only the eligible-course selector: reverse the explicit lexical best comparison, use last/max rather than first/min on the ascending eligible sequence, or remove the ascending scan early break so the last eligible item wins. Retained ordering, index-to-name mapping and current eligibility predicate locate this edit. Leave prerequisite updates and enclosing repetition unchanged so eligibility is reconsidered after each choice; unchanged cycle construction and output formatting require no edit and are omitted. In ready-queue variants the initial and repeated sorts establish that selecting the other end remains valid after newly eligible courses enter.

Source: `main.lua`. Selected original locations: L12,L15,L16,L17,L18,L19,L20,L21.

- L12: `    table.sort(courses)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        local ready` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        for _, course in ipairs(courses) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            if not taken[course] and indegree[course] == 0 then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                ready = course` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `                break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **82 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 140 tokens. The contiguous original span L12–L21 costs 106 tokens; the complete original source costs 806 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L12: 74 tokens; removes `table.sort(courses)` from the dependency chain described above.
- Without L15: 76 tokens; removes `local ready` from the dependency chain described above.
- Without L16: 64 tokens; removes `for _, course in ipairs(courses) do` from the dependency chain described above.
- Without L17: 57 tokens; removes `if not taken[course] and indegree[course] == 0 then` from the dependency chain described above.
- Without L18: 72 tokens; removes `ready = course` from the dependency chain described above.
- Without L19: 76 tokens; removes `break` from the dependency chain described above.
- Without L20: 77 tokens; removes `end` from the dependency chain described above.
- Without L21: 78 tokens; removes `end` from the dependency chain described above.
