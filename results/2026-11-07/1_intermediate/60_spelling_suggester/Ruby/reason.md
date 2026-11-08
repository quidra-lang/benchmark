# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.rb`: 3, 4, 5, 6, 7, 8, 9, 10, 16, 17, 19, 21, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 120, 121, 183, 184, 186, 187, 190, 191, 197, 200, 201, 202, 203, 204, 205, 206, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 554, 555, 556, 557, 558, 559, 569, 570, 571, 572, 579, 589, 590, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. The last DP row spans prefix lengths starting at zero; Ruby Array#min on an empty slice yields nil, which cannot be compared numerically to threshold, so the shorter-word exclusion is required. Array lexicographic sort of [distance,-frequency,word] supplies the tie rules. Integer division gives the threshold and first(count) is applied after found.length. Hash iteration and local array mutation show that dictionary entries remain intact.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 2006 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
