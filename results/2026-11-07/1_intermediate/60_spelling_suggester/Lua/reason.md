# Task B selection — Lua

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.lua`: 1, 2, 3, 4, 5, 6, 7, 8, 20, 21, 22, 24, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 189, 190, 191, 192, 193, 194, 195, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 306, 307, 309, 314, 315, 318, 319, 325, 328, 329, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 819, 831, 841, 842, 849, 850, 851, 852, 853, 859, 860, 861, 862, 863, 864, 865, 868, 869, 870, 871, 872, 881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 895

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. The DP table explicitly stores zero-based numeric columns even though normal Lua sequences begin at one. prefix_distance currently initializes best from row[0] and loops from 1, so both the initial candidate and loop lower bound must respect input length. ranked_less and take/scored_item are custom and retained to prove ties and truncation. pairs reads the dictionary while matches is a separate table; table.unpack of no formatted items leaves the unchanged header. KEYBOARD OFF is a valid false value, checked against nil, and the threshold uses integer division.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 2599 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
