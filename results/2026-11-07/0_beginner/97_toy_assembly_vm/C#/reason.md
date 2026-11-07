# Task B selection: 97_toy_assembly_vm / C#

Count only arithmetic/SET and JNZ after decoding, excluding PRINT and HALT while retaining PC/register effects. Initial SETs contribute 3; eight factorial iterations contribute 8*4=32; two Euclid setup SETs contribute 2; three Euclidean iterations contribute 3*5=15, including final non-taken JNZ. Revised executed is 52. PRINT still shows factorials 1,2,6,24,120,720,5040,40320 and gcd 21 because only accounting changes.

The complete instruction data, operand resolution, PC/register/loop semantics and output are needed for the exact whole-run count. Imports and entry-point/culture scaffolding are unnecessary.

Selected complete source lines in `Program.cs`: 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
