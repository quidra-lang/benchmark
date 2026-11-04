# Task B selection: 97_toy_assembly_vm / Quidra

## Common answer requirements

Exclude PRINT and HALT from executed count while counting every executed arithmetic instruction and JNZ once.

## Source evidence

The existing increment happens once for every fetched instruction before dispatch. Guard that increment by the decoded operation, excluding PRINT and HALT there. The JNZ branch changes pc and continues whether its condition is true or false, so counting must remain before that control transfer. The PRINT operation, HALT break, and final executed label stay unchanged.

## Minimization

The loop, affected counter, and three special dispatch paths show why moving the count to the loop bottom would omit jumps. Arithmetic/register implementations do not inform the count guard. Selected complete lines of `main.qui`: 20, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 46.
