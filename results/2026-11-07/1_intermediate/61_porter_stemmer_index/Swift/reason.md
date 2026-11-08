# Task B selection — Swift

## Answer requirements shared across languages

1. Load an initial stopword set and a document with multiple body lines, retaining maximal ASCII-letter tokens in original order, one-based document-wide positions and one-based line numbers.
2. Explain lowercase query/document forms, stemming and index inclusion without discarding original tokens; an active stopword is not indexed but still occupies its original position.
3. Trace PHRASE argument validation, normalization into stems and one-token stopword wildcards, matching consecutive original tokens across a line boundary, numeric document/reference ordering and output of starting references.
4. Change the stopword set and query again; prove the original token positions are unchanged and explain the distinct all-stopword query error and printed STOP/UNSTOP counts.
5. Use the same concrete short-word scenario in every language, allowing the no-suffix stemming base case to supply sufficient evidence without unrelated Porter suffix rules.

## Selected source locations

- `main.swift`: 1, 2, 3, 4, 5, 15, 142, 143, 144, 145, 146, 147, 156, 159, 160, 164, 165, 166, 167, 168, 169, 176, 177, 178, 179, 180, 192, 193, 199, 200, 267, 268, 269, 270, 271, 272, 273, 278, 279, 280, 281, 282, 283, 284, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 317, 318, 446, 452, 453, 454, 455, 456, 457, 458, 464, 476, 477, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 524, 525, 526, 527, 528, 531, 538, 539, 540, 541, 542, 543, 544, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 630, 631, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 835, 837, 838, 839, 840, 841, 842, 843

## Evidence and language semantics

Trace STOPWORDS a; DOC 1; body lines "Ox a," and "ox"; ENDDOC; PHRASE A ox; UNSTOP a; PHRASE A ox; STOP ox; PHRASE ox ox; END. Original tokens are (ox,line1,pos1), (a,line1,pos2), (ox,line2,pos3). The initial index contains ox at positions1,3. The first PHRASE normalizes to "? ox", matches across the line boundary starting at 1:1:2, and prints PHRASE "? ox" matches=1 1:1:2. UNSTOP a prints indexed=1 and makes the next phrase "a ox", again matches=1 1:1:2. STOP ox prints unindexed=2; the final query raises ERROR STOPWORDS ONLY before matching. Every chosen form has at most two letters, so the selected early-return/no-step stemming branch proves the actual stems without needing suffix rules. Token structs and Array storage retain original fields; filtered arrays and occurrence tuples copy values without renumbering them. Document is a class, but STOP and UNSTOP touch only the SearchEngine Set. The ASCII predicate and selected manual scan determine maximal tokens. Sorted Int keys and increasing starts preserve result ordering; thrown CommandError carries its description through the output catch.

## Minimization and alternatives

The common scenario is fixed before language selection. Keeping all raw-token storage and the active-stopword filter, rather than selecting unrelated INDEX/SEARCH command implementations, is the smaller evidence set for why positions survive. The phrase loop and custom matching/reference/format helpers are necessary: names alone cannot prove wildcard width, cross-line matching or start-reference semantics. Only the short-word stemming branch is relevant; long-word suffix rules, KWIC, ranking, similarity, deletion and append are excluded. STOP and UNSTOP are both retained to show a changed subsequent query and the separate all-stopword error. Alternative long-word examples would require a larger Porter rule closure; an INDEX command trace would duplicate the already visible index storage/filter. Individual selected statements were reviewed for the input-to-output chain, and the final excerpt was independently checked against the common trace.

The excerpt contains 2581 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
