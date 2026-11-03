# Task B selection: 98_bank_queue_simulation / Go

## Common answer requirements

Trace first three customers arrival and teller availability before each assignment; distinguish earliest-free teller choice from service start, prove teller-1 ties and single-teller availability update.

## Answer and source dependencies

The first six generator states are 2027382,1226992407,551494037,961371815,1404753842,2076553157. Odd draws give interarrivals 3,3,3, so arrivals are 3,6,9; even draws give services 6,7,2. Customer 1 sees teller free times (0,0), chooses teller 1 by the equality tie, starts 3 and ends 9, leaving (9,0). Customer 2 sees (9,0), chooses teller 2, starts 6 and ends 13, leaving (9,13). Customer 3 sees (9,13), chooses teller 1, starts 9 and ends 11, leaving (11,13). Teller selection compares free times before applying max(arrival,chosen-free-time); the max determines start only. The indexed assignment changes only the chosen teller. Index-first minimum operations pick the first teller on equal minima; zero-based implementations add one for the printed teller number.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review found the teller-selection if block was not closed before start/end/free updates. Original L17 closes that choice; service start is then max(arrival, selected teller free time). First arrivals3,6,9/services6,7,2 see free times[0,0],[9,0],[9,13], choose tellers1,2,1, and end at9,13,11 respectively. Strict comparison gives teller1 on an equal-free-time tie; only the selected slot is overwritten.

Source: `main.go`. Selected original locations: L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L21,L25.

- L6: `	x := int64(42)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `	freeTime := [2]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `	arrival, totalWait, maximum := 0, 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `	for k := 1; k <= 20; k++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `		x = x * 48271 % 2147483647` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `		arrival += int(x%5) + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `		x = x * 48271 % 2147483647` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `		service := int(x%7) + 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `		teller := 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `		if freeTime[1] < freeTime[0] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `			teller = 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `		start := max(arrival, freeTime[teller])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `		end := start + service` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		freeTime[teller] = end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `			teller+1, wait)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **253 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 249 tokens. The contiguous original span L6–L25 costs 341 tokens; the complete original source costs 435 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 242 tokens; removes `x := int64(42)` from the dependency chain described above.
- Without L7: 240 tokens; removes `freeTime := [2]int{}` from the dependency chain described above.
- Without L8: 233 tokens; removes `arrival, totalWait, maximum := 0, 0, 0` from the dependency chain described above.
- Without L9: 230 tokens; removes `for k := 1; k <= 20; k++ {` from the dependency chain described above.
- Without L10: 224 tokens; removes `x = x * 48271 % 2147483647` from the dependency chain described above.
- Without L11: 236 tokens; removes `arrival += int(x%5) + 1` from the dependency chain described above.
- Without L12: 224 tokens; removes `x = x * 48271 % 2147483647` from the dependency chain described above.
- Without L13: 236 tokens; removes `service := int(x%7) + 2` from the dependency chain described above.
- Without L14: 245 tokens; removes `teller := 0` from the dependency chain described above.
- Without L15: 233 tokens; removes `if freeTime[1] < freeTime[0] {` from the dependency chain described above.
- Without L16: 244 tokens; removes `teller = 1` from the dependency chain described above.
- Without L17: 249 tokens; removes `}` from the dependency chain described above.
- Without L18: 235 tokens; removes `start := max(arrival, freeTime[teller])` from the dependency chain described above.
- Without L19: 241 tokens; removes `end := start + service` from the dependency chain described above.
- Without L21: 241 tokens; removes `freeTime[teller] = end` from the dependency chain described above.
- Without L25: 242 tokens; removes `teller+1, wait)` from the dependency chain described above.
