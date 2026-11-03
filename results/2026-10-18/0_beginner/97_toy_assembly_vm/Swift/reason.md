# Task B selection: 97_toy_assembly_vm / Swift

## Common answer requirements

Locate dynamic execution-loop count; count only SET/ADD/SUB/MUL/MOD/JNZ per execution, including untaken JNZ, excluding PRINT/HALT and preserving label.

## Answer and source dependencies

Replace the unconditional per-iteration increment with a guard admitting SET, ADD, SUB, MUL, MOD and JNZ (equivalently excluding PRINT/HALT for this instruction set). Keep the guarded increment at the current dispatch position after reading the operation and before any branch/continue. Thus every dynamic visit counts separately and JNZ counts whether its condition is true or false; PRINT and HALT do not increment. The output statement already reads this counter with the required label. Register updates, jumps and PRINT output do not need edits.



## Scope and dependency evidence checked after independent review

Independent review found the previous candidate included unchanged HALT/final output context. The existing current-opcode binding and unconditional executed increment are the sufficient edit sites. Gate that increment with exactly the whitelist SET,ADD,SUB,MUL,MOD,JNZ. Perform the gate once for each dispatch, before any JNZ taken/not-taken decision, so repeated executions and all JNZ executions count while PRINT/HALT do not. Leave interpreter control flow, PRINT output and the final executed label unchanged. Rust binds op after the current increment, so either test parts[0] directly at that site or establish op before the gated increment.

Source: `main.swift`. Selected original locations: L11,L12.

- L11: `    let parts = program[pc].split(separator: " ").map(String.init)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    executed += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **35 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 88 tokens. The contiguous original span L11–L12 costs 35 tokens; the complete original source costs 624 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L11: 7 tokens; removes `let parts = program[pc].split(separator: " ").map(String.init)` from the dependency chain described above.
- Without L12: 28 tokens; removes `executed += 1` from the dependency chain described above.
