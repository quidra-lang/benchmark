# Task B selection — Python

## Answer requirements shared across languages

1. Trace a valid initial dictionary and COMPLETE word k through command parsing, lowercase/word and numeric validation, keyboard/limit options, and the derived inclusive distance threshold.
2. Identify how existing prefix distance examines prefixes and how to restrict eligible prefix lengths to at least the input length; exclude shorter dictionary words before taking a minimum.
3. Preserve the distance recurrence, ordering by distance then decreasing frequency then lexical word, result limit k, and total qualifying count before truncation.
4. Use dictionary {a:1} and COMPLETE ab 3 with default keyboard OFF/limit 2 to show an old distance-one candidate becoming no candidates; preserve COMPLETE ab count=0 and dictionary state.

## Selected source locations

- `main.py`: 5, 6, 7, 8, 9, 10, 11, 12, 23, 24, 25, 26, 27, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 155, 156, 224, 225, 226, 229, 230, 236, 237, 249, 259, 260, 267, 268, 269, 270, 271, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 634, 635, 636, 637, 638, 639, 644, 645, 646, 647, 648, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663

## Evidence and language semantics

The final dynamic-programming row is indexed by dictionary-prefix length, including zero. Restrict its minimum to columns len(word)..len(other), and skip other words shorter than word before evaluating an empty range. tuple sorting already implements distance ascending, frequency descending, then normalized word; matches[:count] limits display after len(matches) supplies the total. With only a at frequency one, default OFF gives threshold 1 and old distance(ab,a)=1; the new eligibility filter removes it. emit with an empty generator still prints COMPLETE ab count=0. COMPLETE iterates the existing dictionary and mutates only its local matches/output, so removing candidates must not remove dictionary entries.

## Minimization and alternatives

The distance recurrence and its cost/swap helpers are retained because prefix_distance is custom, not an intrinsic. The exact adjacency table closes the optional keyboard cost dependency; unrelated edit scripts/SUGGEST paths are excluded. Dictionary loading, selected handler/argument route, defaults and option setters supply the complete valid route without text-checking, learning, undo or rules. The alternative of filtering only after distance computation risks taking a minimum over no eligible prefixes; selecting COMPLETE and the final-row reduction exposes both required edit sites with fewer tokens than full parser/ranking classes. Final selected lines were reviewed independently against the shared requirements.

The excerpt contains 2159 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
