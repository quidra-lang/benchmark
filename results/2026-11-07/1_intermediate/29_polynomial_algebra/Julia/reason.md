# Task B selection — Julia

## Answer requirements shared across languages

1. Trace INTERP token splitting, destination extraction, and left-to-right exact rational parsing, including zero-denominator errors before duplicate processing.
2. Identify the current unconditional repeated-x rejection and the modification: compare exact y with the first surviving equal-x point, discard equal pairs in input order, and reject the first conflicting repeated x.
3. Feed only surviving paired x/y arrays and their new count into divided differences and polynomial reconstruction; explain one surviving point as its constant polynomial.
4. Trace registration/replacement and canonical result output after success; show that validation/interpolation errors precede writes and preserve any previously stored destination.
5. Use a valid equivalent-spelling example and a later conflicting repeat, explaining first-error precedence and error output without implementing the proposed change.

## Selected source locations

- `main.jl`: 1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 46, 51, 52, 53, 54, 55, 56, 57, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 539, 540, 541, 542, 676, 677, 683, 684, 685, 686, 693, 694, 695, 696, 697, 698, 699, 700

## Evidence and language semantics

For the proposed behavior, INTERP R 0 3/2 0/2 6/4 1 3/2 parses every rational first; the second pair equals the first and must be discarded, leaving (0,3/2),(1,3/2). Newton differences then contain 3/2,0 and reconstruct the constant 3/2, registered as R = 3/2. Replace the final pair with 0 2 to obtain a later conflicting x and ERROR DUPLICATE X 0; if a later argument has denominator zero, the earlier rational-validation stage wins. The retained first y must be compared before differences mutate y values, and both coordinate arrays/counts must be compacted together. A single survivor skips the differences loop and reconstructs its constant. No registration occurs for a rejected command. This is modification analysis, not a claim that current code already accepts repeated points. Julia Rational{Int64} and // provide normalization and exact rational arithmetic/equality as library semantics; polynomial operators and storage/output are custom and therefore selected. Exceptions bypass pending writes.

## Minimization and alternatives

Compared selecting only the INTERP dispatch/duplicate test with following its parsing, exact comparison, interpolation, registration and output dependencies. The former cannot establish canonical equality, precedence, one-point behavior or rollback. Selected only the relevant arithmetic, coefficient operations, formatter and success/error path; expression parsing, named operands, other commands and unrelated algebra are omitted. Standard-library arithmetic/collection/I/O implementations are unnecessary. Blank lines and standalone syntactic delimiters add no answer evidence and are omitted. Both local staging and the final write site are needed where storage is deferred; direct-store languages instead need only their write boundary. Removing any semantic stage loses one of the shared requirements.

The excerpt contains 2186 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
