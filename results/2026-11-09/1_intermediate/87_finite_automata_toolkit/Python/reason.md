# Task B selection — Python

## Answer requirements shared across languages

1. Preserve COUNT command arity/reference validation and nonnegative length parsing, then identify the exact accepted count for length n and current integer output.
2. Explain the set/subset transition recurrence and epsilon-closed initial state so each distinct length-n string contributes once, not once per accepting path.
3. Use the source alphabet size for the exact denominator |Sigma|^n, with the empty word having denominator one and acceptance determined by the initial epsilon closure.
4. Describe scaled integer floor conversion floor(10000*C/D), overflow/precision safeguards and exactly two fractional digits followed by %, including 1/3 = 33.33%.

## Selected source locations

- `main.py`: 2, 4, 8, 11, 17, 60, 61, 62, 63, 64, 65, 66, 67, 68, 71, 72, 74, 75, 76, 77, 78, 79, 80, 81, 82, 84, 85, 86, 90, 94, 95, 96, 97, 98, 99, 100, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 254, 255, 256, 257, 258, 259, 260, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 501, 502, 503, 510, 511, 515, 516, 517, 518, 519, 520, 521, 522, 696, 697, 698

## Evidence and language semantics

Keep the accepted count C and alphabet symbols unchanged. Build D=|Sigma|^n with exact integer multiplication starting at one; epsilon is not an alphabet symbol. Replace only the current count text with Q=floor(10000*C/D), rendered as (Q div 100), a decimal point, a zero-padded two-digit (Q mod 100), and %. This yields 33.33% for C=1,D=3. At n=0, D=1 and the epsilon-closed initial state yields C=0 or1, hence 0.00% or100.00%. Under the existing input bound D<=10^15, direct C*10000 can reach10^19 and must not use a signed64 intermediate or floating arithmetic. A portable exact alternative uses initial Q=C div D and remainder C mod D, then four decimal long-division steps (Q=10*Q+(10*r div D); r=10*r mod D); each remainder product stays below10^16, within64-bit integers. Arbitrary-precision integers can instead use the direct scaled expression. Python int is arbitrary precision, so exact exponentiation and C*10000//D are directly suitable. Existing COUNT parses length with int after shared arity and reference validation; the input grammar guarantees nonnegative n rather than an additional local range check. The epsilon closure returns a frozenset, explore interns each subset and one edge per alphabet symbol, and determinize marks a subset accepting if any member accepts. count_by_length starts with weight one, sums only accepting DFA states at each length and advances once per symbol, preserving n=0 and distinct strings. The Automaton constructor stores the unchanged alphabet and transition target sets used by delta.

## Minimization and alternatives

The modification belongs in the COUNT output path, retaining its exact counting helper and shared automaton/argument checks. The excerpt independently establishes the counting recurrence, subset/epsilon semantics, alphabet access and replacement output point. Full automaton construction, regex parsing, enumeration, minimization, table printing and unrelated command branches were considered and excluded. Only helper statements necessary to understand subset identity, closure, accepted totals and input dispatch remain; ordinary set/map/integer semantics provide the rest. The proposed arithmetic is described in the rationale, not added to the verbatim source excerpt. No implementation or program execution is performed.

The excerpt contains 1319 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
