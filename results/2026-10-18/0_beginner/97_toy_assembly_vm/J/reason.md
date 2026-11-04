# Task B selection — 97_toy_assembly_vm / J

## Common answer requirements

Locate the per-instruction increment and count exactly the six named opcodes once per dispatch, including untaken JNZ.

## Source evidence

The selected lines show the fetch and split, the first field that identifies the operation, and the count that currently increments before dispatch. Guard that increment with SET, ADD, SUB, MUL, MOD and JNZ, so repeated visits count and the branch decision cannot suppress a JNZ. Leave the instructions, control flow and output untouched.

## Minimization

Selected complete lines of `main.ijs`: L1, L2, L3, L16, L17, L18. The dispatch selector establishes the opcode position where the implementation does not bind it separately. For J the selected local split helper establishes the field order. The remaining opcode implementations and the final printing line add no edit location.

The selected excerpt measures **55 tokens** with `metric/tokenizer.py`.
