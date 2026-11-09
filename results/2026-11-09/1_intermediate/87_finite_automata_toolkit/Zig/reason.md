# Task B selection — Zig

## Answer requirements shared across languages

1. Preserve COUNT command arity/reference validation and nonnegative length parsing, then identify the exact accepted count for length n and current integer output.
2. Explain the set/subset transition recurrence and epsilon-closed initial state so each distinct length-n string contributes once, not once per accepting path.
3. Use the source alphabet size for the exact denominator |Sigma|^n, with the empty word having denominator one and acceptance determined by the initial epsilon closure.
4. Describe scaled integer floor conversion floor(10000*C/D), overflow/precision safeguards and exactly two fractional digits followed by %, including 1/3 = 33.33%.

## Selected source locations

- `main.zig`: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 572, 575, 584, 585, 586, 587, 633, 634, 635, 648, 649, 650, 651, 652, 653, 654, 660, 661, 662, 667, 770, 771, 772, 773, 774, 775

## Evidence and language semantics

Keep the accepted count C and alphabet symbols unchanged. Build D=|Sigma|^n with exact integer multiplication starting at one; epsilon is not an alphabet symbol. Replace only the current count text with Q=floor(10000*C/D), rendered as (Q div 100), a decimal point, a zero-padded two-digit (Q mod 100), and %. This yields 33.33% for C=1,D=3. At n=0, D=1 and the epsilon-closed initial state yields C=0 or1, hence 0.00% or100.00%. Under the existing input bound D<=10^15, direct C*10000 can reach10^19 and must not use a signed64 intermediate or floating arithmetic. A portable exact alternative uses initial Q=C div D and remainder C mod D, then four decimal long-division steps (Q=10*Q+(10*r div D); r=10*r mod D); each remainder product stays below10^16, within64-bit integers. Arbitrary-precision integers can instead use the direct scaled expression. Zig canonicalizes closures as ascending state-index slices and serializes them into hash-map keys, so generated states represent sets, not NFA paths. The explicit initial closure, final-state membership and exactly one generated transition per symbol establish empty-word and distinct-word behavior. COUNT arity and optional lookup are checked before parsing usize; the source guarantees nonnegative decimal input. Existing i64 counts are bounded, but the proposed direct scaled product should first promote to u128 (including the denominator base), or use the i64 remainder algorithm. std.fmt integer fields with two-digit zero padding can render the exact quotient and percent marker without floating conversion.

## Minimization and alternatives

The modification belongs in the COUNT output path, retaining its exact counting helper and shared automaton/argument checks. The excerpt independently establishes the counting recurrence, subset/epsilon semantics, alphabet access and replacement output point. Full automaton construction, regex parsing, enumeration, minimization, table printing and unrelated command branches were considered and excluded. Only helper statements necessary to understand subset identity, closure, accepted totals and input dispatch remain; ordinary set/map/integer semantics provide the rest. The proposed arithmetic is described in the rationale, not added to the verbatim source excerpt. No implementation or program execution is performed.

The excerpt contains 3378 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
