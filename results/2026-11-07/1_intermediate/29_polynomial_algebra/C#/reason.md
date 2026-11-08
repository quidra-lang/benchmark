# Task B selection — C#

## Answer requirements shared across languages

1. Trace INTERP token splitting, destination extraction, and left-to-right exact rational parsing, including zero-denominator errors before duplicate processing.
2. Identify the current unconditional repeated-x rejection and the modification: compare exact y with the first surviving equal-x point, discard equal pairs in input order, and reject the first conflicting repeated x.
3. Feed only surviving paired x/y arrays and their new count into divided differences and polynomial reconstruction; explain one surviving point as its constant polynomial.
4. Trace registration/replacement and canonical result output after success; show that validation/interpolation errors precede writes and preserve any previously stored destination.
5. Use a valid equivalent-spelling example and a later conflicting repeat, explaining first-error precedence and error output without implementing the proposed change.

## Selected source locations

- `Program.cs`: 9, 11, 12, 13, 14, 15, 16, 18, 20, 21, 22, 23, 26, 28, 29, 32, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 59, 62, 64, 65, 66, 67, 68, 69, 71, 73, 75, 76, 77, 80, 81, 83, 84, 85, 94, 96, 97, 98, 99, 100, 187, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 201, 537, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 580, 593, 595, 596, 597, 598, 600, 601, 609, 610, 616, 617, 618, 620, 796, 802, 803, 815, 816, 817, 818

## Evidence and language semantics

For the proposed behavior, INTERP R 0 3/2 0/2 6/4 1 3/2 parses every rational first; the second pair equals the first and must be discarded, leaving (0,3/2),(1,3/2). Newton differences then contain 3/2,0 and reconstruct the constant 3/2, registered as R = 3/2. Replace the final pair with 0 2 to obtain a later conflicting x and ERROR DUPLICATE X 0; if a later argument has denominator zero, the earlier rational-validation stage wins. The retained first y must be compared before differences mutate y values, and both coordinate arrays/counts must be compacted together. A single survivor skips the differences loop and reconstructs its constant. No registration occurs for a rejected command. This is modification analysis, not a claim that current code already accepts repeated points. C# value-type fractions and cross-product CompareTo establish exact equality; LINQ ToArray forces all literal parsing before Interpolate; pending dictionary writes occur only after success.

## Minimization and alternatives

Compared selecting only the INTERP dispatch/duplicate test with following its parsing, exact comparison, interpolation, registration and output dependencies. The former cannot establish canonical equality, precedence, one-point behavior or rollback. Selected only the relevant arithmetic, coefficient operations, formatter and success/error path; expression parsing, named operands, other commands and unrelated algebra are omitted. Standard-library arithmetic/collection/I/O implementations are unnecessary. Blank lines and standalone syntactic delimiters add no answer evidence and are omitted. Both local staging and the final write site are needed where storage is deferred; direct-store languages instead need only their write boundary. Removing any semantic stage loses one of the shared requirements.

The excerpt contains 2459 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
