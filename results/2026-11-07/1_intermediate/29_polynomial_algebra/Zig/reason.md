# Task B selection — Zig

## Answer requirements shared across languages

1. Trace INTERP token splitting, destination extraction, and left-to-right exact rational parsing, including zero-denominator errors before duplicate processing.
2. Identify the current unconditional repeated-x rejection and the modification: compare exact y with the first surviving equal-x point, discard equal pairs in input order, and reject the first conflicting repeated x.
3. Feed only surviving paired x/y arrays and their new count into divided differences and polynomial reconstruction; explain one surviving point as its constant polynomial.
4. Trace registration/replacement and canonical result output after success; show that validation/interpolation errors precede writes and preserve any previously stored destination.
5. Use a valid equivalent-spelling example and a later conflicting repeat, explaining first-error precedence and error output without implementing the proposed change.

## Selected source locations

- `main.zig`: 57, 58, 63, 64, 69, 70, 71, 72, 73, 74, 75, 77, 80, 81, 82, 83, 84, 86, 87, 88, 90, 91, 93, 94, 95, 96, 97, 98, 100, 101, 103, 104, 106, 107, 109, 110, 112, 113, 115, 116, 118, 119, 121, 122, 124, 125, 138, 139, 140, 144, 145, 146, 147, 148, 149, 150, 152, 153, 154, 155, 157, 158, 160, 161, 163, 164, 166, 167, 169, 170, 172, 173, 175, 176, 177, 178, 190, 191, 192, 193, 194, 195, 197, 319, 320, 322, 323, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 723, 724, 725, 726, 727, 728, 729, 730, 732, 733, 735, 736, 737, 738, 739, 742, 743, 744, 745, 746, 747, 749, 812, 813, 814, 831, 832, 833, 834, 835, 836, 837, 839, 840, 841, 847, 848, 849, 850, 852, 853, 854, 865, 866, 867, 868, 869, 870, 872, 873, 878, 879, 890, 891, 892, 893, 1101, 1111, 1147, 1148, 1149, 1150, 1151, 1153, 1154

## Evidence and language semantics

For the proposed behavior, INTERP R 0 3/2 0/2 6/4 1 3/2 parses every rational first; the second pair equals the first and must be discarded, leaving (0,3/2),(1,3/2). Newton differences then contain 3/2,0 and reconstruct the constant 3/2, registered as R = 3/2. Replace the final pair with 0 2 to obtain a later conflicting x and ERROR DUPLICATE X 0; if a later argument has denominator zero, the earlier rational-validation stage wins. The retained first y must be compared before differences mutate y values, and both coordinate arrays/counts must be compacted together. A single survivor skips the differences loop and reconstructs its constant. No registration occurs for a rejected command. This is modification analysis, not a claim that current code already accepts repeated points. Zig exact integer Fraction methods and eq establish the values and identity; error unions and try/catch stop before save/commit. Session stages stores and main commits only after process succeeds; formatting and replacement are custom evidence.

## Minimization and alternatives

Compared selecting only the INTERP dispatch/duplicate test with following its parsing, exact comparison, interpolation, registration and output dependencies. The former cannot establish canonical equality, precedence, one-point behavior or rollback. Selected only the relevant arithmetic, coefficient operations, formatter and success/error path; expression parsing, named operands, other commands and unrelated algebra are omitted. Standard-library arithmetic/collection/I/O implementations are unnecessary. Blank lines and standalone syntactic delimiters add no answer evidence and are omitted. Both local staging and the final write site are needed where storage is deferred; direct-store languages instead need only their write boundary. Removing any semantic stage loses one of the shared requirements.

The excerpt contains 3807 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
