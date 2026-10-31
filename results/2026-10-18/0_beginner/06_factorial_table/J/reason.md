# Task B selection: 06_factorial_table / J

## Common answer requirements

1. Locate the range endpoint and every representation/output dependency relevant to exact factorials through 15.
2. Explain how to produce sixteen increasing rows, including 0!, without overflow or lossy decimal output.

## Answer supported by the excerpt

Extend the inclusive endpoint to 15, or the exclusive/count endpoint to 16. The largest result is 15! = 1307674368000, which exceeds signed 32-bit range but fits signed 64-bit and the exact-integer range of binary64. Widen a 32-bit accumulator before multiplication; preserve the n=0 handling. Keep arbitrary-precision integer implementations as they are. Adjust a fixed-width decimal formatter if widening changes its required argument type. Architecture-dependent integer implementations must use a sufficiently wide integer representation rather than assume that a version number guarantees word size.

## Source evidence and dependencies

Selected `main.ijs` lines: 2-3. The excerpt preserves these complete lines in their original order and indentation.

The endpoint supplies the extent edit; the accumulator declaration, reduction or factorial call establishes the representation. A multiplication is additionally retained where operand type coupling or exactness matters. A format line is retained where the representation change can affect that formatter. Separate generic interpolation/stream output needs no edit when it already prints the resulting integer.

Extend i.13 to sixteen terms. If avoiding a machine-integer-width dependency, use extended-integer input to the factorial primitive; the zero-fraction 8!:2 rendering already produces decimal integers.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. The loop endpoint alone is insufficient for fixed-width implementations because it hides the overflow risk. Copying the entire program adds only unchanged framing. The selected endpoint plus representation and affected formatting is the narrower sufficient set.

The selected excerpt contains **45 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 45 tokens; the complete source contains 65 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
