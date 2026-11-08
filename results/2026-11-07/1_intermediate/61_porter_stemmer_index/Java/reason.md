# Task B selection — Java

## Answer requirements shared across languages

1. Load an initial stopword set and a document with multiple body lines, retaining maximal ASCII-letter tokens in original order, one-based document-wide positions and one-based line numbers.
2. Explain lowercase query/document forms, stemming and index inclusion without discarding original tokens; an active stopword is not indexed but still occupies its original position.
3. Trace PHRASE argument validation, normalization into stems and one-token stopword wildcards, matching consecutive original tokens across a line boundary, numeric document/reference ordering and output of starting references.
4. Change the stopword set and query again; prove the original token positions are unchanged and explain the distinct all-stopword query error and printed STOP/UNSTOP counts.
5. Use the same concrete short-word scenario in every language, allowing the no-suffix stemming base case to supply sufficient evidence without unrelated Porter suffix rules.

## Selected source locations

- `Main.java`: 26, 27, 42, 43, 44, 54, 56, 62, 98, 239, 240, 241, 242, 251, 254, 255, 262, 263, 266, 267, 268, 269, 270, 284, 285, 286, 287, 288, 342, 343, 344, 345, 346, 347, 348, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 362, 369, 370, 473, 474, 475, 476, 477, 483, 495, 496, 500, 501, 502, 503, 504, 505, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 559, 560, 561, 562, 563, 564, 567, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 695, 859, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 928, 930, 931, 932, 933, 934, 935, 936

## Evidence and language semantics

Trace STOPWORDS a; DOC 1; body lines "Ox a," and "ox"; ENDDOC; PHRASE A ox; UNSTOP a; PHRASE A ox; STOP ox; PHRASE ox ox; END. Original tokens are (ox,line1,pos1), (a,line1,pos2), (ox,line2,pos3). The initial index contains ox at positions1,3. The first PHRASE normalizes to "? ox", matches across the line boundary starting at 1:1:2, and prints PHRASE "? ox" matches=1 1:1:2. UNSTOP a prints indexed=1 and makes the next phrase "a ox", again matches=1 1:1:2. STOP ox prints unindexed=2; the final query raises ERROR STOPWORDS ONLY before matching. Every chosen form has at most two letters, so the selected early-return/no-step stemming branch proves the actual stems without needing suffix rules. Immutable record Token fields and separate TreeMap documents/Set stopwords preserve positions. The record Stemming declares which component .stem() returns; <=2 lowercase words skip suffix rules. Matcher.find produces maximal ASCII tokens and lower uses Locale.ROOT. phraseMatches checks each original offset, including across lines. STOP and UNSTOP change only Set membership; reference and output helpers retain line/position and exact spacing.

## Minimization and alternatives

The common scenario is fixed before language selection. Keeping all raw-token storage and the active-stopword filter, rather than selecting unrelated INDEX/SEARCH command implementations, is the smaller evidence set for why positions survive. The phrase loop and custom matching/reference/format helpers are necessary: names alone cannot prove wildcard width, cross-line matching or start-reference semantics. Only the short-word stemming branch is relevant; long-word suffix rules, KWIC, ranking, similarity, deletion and append are excluded. STOP and UNSTOP are both retained to show a changed subsequent query and the separate all-stopword error. Alternative long-word examples would require a larger Porter rule closure; an INDEX command trace would duplicate the already visible index storage/filter. Individual selected statements were reviewed for the input-to-output chain, and the final excerpt was independently checked against the common trace.

The excerpt contains 3091 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
