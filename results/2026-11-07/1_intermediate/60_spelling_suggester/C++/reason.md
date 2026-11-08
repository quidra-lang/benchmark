# Task B selection — C++

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.cpp`: 23, 24, 25, 26, 27, 37, 38, 39, 40, 41, 42, 43, 44, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 132, 133, 134, 135, 217, 218, 219, 220, 228, 229, 230, 231, 232, 233, 237, 239, 241, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 648, 649, 653, 654, 655, 656, 668, 670, 673, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 698, 708, 709, 719, 720, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745

## Evidence and language semantics

The required change restricts dictionary-prefix columns to lengths from the input length through the dictionary-word length and excludes a shorter dictionary word before reducing an empty set. The recurrence remains unchanged. With dictionary a:1 and COMPLETE ab 3, keyboard OFF and base limit 2 give threshold 1: the old distance-one a candidate disappears, and the existing empty candidate collection yields COMPLETE ab count=0. Count is the full qualifying set before the requested display limit. The dictionary is read by this command; only local result storage and output are changed. The final vector row indexes prefix length directly. min_element on an empty eligible range would return end, so dereferencing it requires the explicit shorter-word exclusion. Const map iteration builds a local candidate vector, with std::sort comparing distance, decreasing frequency and lexical word; min(found.size(),count) limits display only after total is recorded. The raw-string emit overload suffices for this output path; no custom join implementation is needed.

## Minimization and alternatives

The selected final-row reduction exposes the prefix-length change; COMPLETE exposes the necessary shorter-word guard, inclusive threshold, ranking and count/output. Restricting only the reduction can leave an empty range, so both sites are required. The recurrence and cost helpers close custom distance dependencies; standard containers, slicing, sorting and string operations use language guarantees. Parser/default/option/loading lines connect the valid command end to end. Unrelated checker, SUGGEST, edit-script, rule, learning and undo code has no effect on this route and is excluded. Selecting all surrounding methods would add no necessary evidence. The excerpt was reviewed independently against the shared requirements.

The excerpt contains 3151 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
