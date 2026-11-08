# Task B selection — Rust

## Answer requirements shared across languages

1. Load an initial stopword set and a document with multiple body lines, retaining maximal ASCII-letter tokens in original order, one-based document-wide positions and one-based line numbers.
2. Explain lowercase query/document forms, stemming and index inclusion without discarding original tokens; an active stopword is not indexed but still occupies its original position.
3. Trace PHRASE argument validation, normalization into stems and one-token stopword wildcards, matching consecutive original tokens across a line boundary, numeric document/reference ordering and output of starting references.
4. Change the stopword set and query again; prove the original token positions are unchanged and explain the distinct all-stopword query error and printed STOP/UNSTOP counts.
5. Use the same concrete short-word scenario in every language, allowing the no-suffix stemming base case to supply sufficient evidence without unrelated Porter suffix rules.

## Selected source locations

- `main.rs`: 46, 52, 174, 175, 176, 177, 186, 189, 190, 197, 198, 199, 200, 201, 202, 203, 204, 205, 218, 219, 221, 228, 229, 230, 232, 235, 236, 237, 238, 239, 243, 244, 245, 246, 247, 248, 376, 377, 378, 379, 380, 381, 382, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 441, 442, 548, 549, 550, 551, 552, 553, 554, 555, 558, 559, 560, 561, 562, 589, 590, 591, 592, 593, 594, 595, 596, 599, 613, 614, 615, 616, 617, 618, 621, 622, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 767, 768, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, 975, 1011, 1012, 1013, 1014, 1015, 1017, 1023, 1035, 1036, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1079, 1081, 1082, 1083

## Evidence and language semantics

Trace STOPWORDS a; DOC 1; body lines "Ox a," and "ox"; ENDDOC; PHRASE A ox; UNSTOP a; PHRASE A ox; STOP ox; PHRASE ox ox; END. Original tokens are (ox,line1,pos1), (a,line1,pos2), (ox,line2,pos3). The initial index contains ox at positions1,3. The first PHRASE normalizes to "? ox", matches across the line boundary starting at 1:1:2, and prints PHRASE "? ox" matches=1 1:1:2. UNSTOP a prints indexed=1 and makes the next phrase "a ox", again matches=1 1:1:2. STOP ox prints unindexed=2; the final query raises ERROR STOPWORDS ONLY before matching. Every chosen form has at most two letters, so the selected early-return/no-step stemming branch proves the actual stems without needing suffix rules. BTreeMap orders numeric document keys and Vec::windows visits contiguous raw tokens across lines. References in the occurrence map borrow stored Token values rather than rebuilding positions. Rust Set insert/remove report the membership change, and no document mutation occurs on those command paths. Result propagation preserves word errors and the separate STOPWORDS ONLY failure; format and with_items establish exact output.

## Minimization and alternatives

The common scenario is fixed before language selection. Keeping all raw-token storage and the active-stopword filter, rather than selecting unrelated INDEX/SEARCH command implementations, is the smaller evidence set for why positions survive. The phrase loop and custom matching/reference/format helpers are necessary: names alone cannot prove wildcard width, cross-line matching or start-reference semantics. Only the short-word stemming branch is relevant; long-word suffix rules, KWIC, ranking, similarity, deletion and append are excluded. STOP and UNSTOP are both retained to show a changed subsequent query and the separate all-stopword error. Alternative long-word examples would require a larger Porter rule closure; an INDEX command trace would duplicate the already visible index storage/filter. Individual selected statements were reviewed for the input-to-output chain, and the final excerpt was independently checked against the common trace.

The excerpt contains 3115 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
