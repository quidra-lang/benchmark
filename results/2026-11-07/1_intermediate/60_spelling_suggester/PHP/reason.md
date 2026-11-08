# Task B selection — PHP

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.php`: 5, 6, 7, 8, 9, 10, 11, 12, 19, 20, 22, 24, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 144, 145, 146, 235, 236, 237, 238, 241, 242, 249, 250, 251, 255, 256, 257, 258, 259, 260, 261, 262, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 727, 728, 729, 736, 746, 747, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. The zero-based final DP row contains all prefix lengths. A guard must exclude shorter words before min sees an empty selected range. usort explicitly compares distance, reverse frequency and strcmp; array_slice limits the emitted items while count(found) is the total. COMPLETE never writes dictionary, only local arrays and the output buffer. explode, lowercase regex and strict integer validation close the input path; intdiv defines the threshold and the retained header array preserves zero-result formatting.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 2816 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
