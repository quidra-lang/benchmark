# Task B source selection

## Common answer requirements

Trace first three customers arrival and teller availability before each assignment; distinguish earliest-free teller choice from service start, prove teller-1 ties and single-teller availability update.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The first six generator states are 2027382,1226992407,551494037,961371815,1404753842,2076553157. Odd draws give interarrivals 3,3,3, so arrivals are 3,6,9; even draws give services 6,7,2. Customer 1 sees teller free times (0,0), chooses teller 1 by the equality tie, starts 3 and ends 9, leaving (9,0). Customer 2 sees (9,0), chooses teller 2, starts 6 and ends 13, leaving (9,13). Customer 3 sees (9,13), chooses teller 1, starts 9 and ends 11, leaving (11,13). Teller selection compares free times before applying max(arrival,chosen-free-time); the max determines start only. The indexed assignment changes only the chosen teller. Index-first minimum operations pick the first teller on equal minima; zero-based implementations add one for the printed teller number.



## Source evidence and dependencies

The selected locations in `main.py` are L1, L2, L3, L5, L6, L7, L8, L9, L10, L11, L12, L13, L18. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `state = 42`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L2: `arrival = 0`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L3: `free_times = [0, 0]`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L5: `for customer in range(1, 21):`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L6: `state = state * 48271 % 2147483647`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L7: `arrival += state % 5 + 1`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L8: `state = state * 48271 % 2147483647`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L9: `service = state % 7 + 2`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L10: `teller = 0 if free_times[0] <= free_times[1] else 1`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L11: `start = max(arrival, free_times[teller])`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L12: `end = start + service`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L13: `free_times[teller] = end`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.
- L18: `f"teller={teller + 1} wait={wait}"`. This line supplies the seed/arrival/free-time initialization, interleaved random draws, teller minimum/tie rule, service timing, selected-teller update or printed teller numbering needed for the first three assignments.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **219 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L18 costs **278 tokens**; the entire source costs **345 tokens**. The selected set plus the additional context line L4 costs **225 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
