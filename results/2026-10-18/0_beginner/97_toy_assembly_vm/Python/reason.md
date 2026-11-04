# Task B selection — 97_toy_assembly_vm / Python

## Common answer requirements

Locate the per-instruction increment and count exactly the six named opcodes, once per dispatch including untaken JNZ. Preserve existing output and control flow.

## Source evidence

The current program counter selects a line, split supplies its fields, and the first field is the operation. Guard the existing increment with membership in SET, ADD, SUB, MUL, MOD and JNZ. Its original per-dispatch location counts repeated visits and every JNZ regardless of the later branch outcome.

## Minimization

Selected complete lines of `main.py`: L29, L30, L31. The selected fetch, opcode and increment are sufficient to locate the guarded count. The HALT and JNZ control flow, register updates and output can all remain as written, so the larger dispatch excerpt is unnecessary.

The selected excerpt measures **30 tokens** with `metric/tokenizer.py`.
