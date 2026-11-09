# Task B selection — Kotlin

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.kt`: 4, 5, 6, 7, 8, 15, 16, 20, 21, 23, 26, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 108, 109, 179, 185, 186, 187, 188, 189, 190, 196, 198, 199, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 518, 519, 520, 521, 534, 535, 536, 537, 544, 554, 555, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. The zero-based last row uses column j for a prefix of length j. Kotlin min() on an empty eligible row is undefined, so words shorter than the input must be skipped first. The mapNotNull result is separate from the mutable dictionary, and the comparator fixes distance ascending, frequency descending, word ascending before take(count). Integer division determines the threshold and the joined header remains present with no candidates.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 2260 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
