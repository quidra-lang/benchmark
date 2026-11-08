# Task B selection — J

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.ijs`: 1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 16, 19, 20, 24, 25, 31, 33, 34, 35, 36, 37, 38, 39, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 121, 123, 203, 421, 422, 423, 424, 425, 426, 427, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. J computes a padded matrix for all dictionary words at once. prefixDistances currently takes each real word length plus one from its row before reducing, avoiding padded columns. The change must preserve that real-word bound, drop the first #word columns, and exclude original indices with length below #word from matches; merely dropping columns from a padded row would introduce invalid prefixes. distanceOrder grades indices by distance, negative Frequencies and lexical wordRank. Keep original indices aligned with Words and Frequencies; do not destructively filter the dictionary globals. Empty shown contributes no fields to say, retaining the header. Complete command, arity and handler vectors are positional and must all be retained to prove mapping.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 2081 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
