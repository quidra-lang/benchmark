# Task B selection — Julia

## Answer requirements shared across languages

1. Load an initial stopword set and a document with multiple body lines, retaining maximal ASCII-letter tokens in original order, one-based document-wide positions and one-based line numbers.
2. Explain lowercase query/document forms, stemming and index inclusion without discarding original tokens; an active stopword is not indexed but still occupies its original position.
3. Trace PHRASE argument validation, normalization into stems and one-token stopword wildcards, matching consecutive original tokens across a line boundary, numeric document/reference ordering and output of starting references.
4. Change the stopword set and query again; prove the original token positions are unchanged and explain the distinct all-stopword query error and printed STOP/UNSTOP counts.
5. Use the same concrete short-word scenario in every language, allowing the no-suffix stemming base case to supply sufficient evidence without unrelated Porter suffix rules.

## Selected source locations

- `main.jl`: 1, 2, 19, 20, 21, 125, 126, 127, 134, 137, 139, 143, 144, 145, 155, 156, 157, 158, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 223, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 338, 339, 340, 341, 342, 343, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 624, 625, 626, 627, 629, 635, 647, 648, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685

## Evidence and language semantics

Trace STOPWORDS a; DOC 1; body lines "Ox a," and "ox"; ENDDOC; PHRASE A ox; UNSTOP a; PHRASE A ox; STOP ox; PHRASE ox ox; END. Original tokens are (ox,line1,pos1), (a,line1,pos2), (ox,line2,pos3). The initial index contains ox at positions1,3. The first PHRASE normalizes to "? ox", matches across the line boundary starting at 1:1:2, and prints PHRASE "? ox" matches=1 1:1:2. UNSTOP a prints indexed=1 and makes the next phrase "a ox", again matches=1 1:1:2. STOP ox prints unindexed=2; the final query raises ERROR STOPWORDS ONLY before matching. Every chosen form has at most two letters, so the selected early-return/no-step stemming branch proves the actual stems without needing suffix rules. Immutable Token records cache form and stem when loaded; mutable vectors keep the raw order even when Set membership changes. occurrence_map filters those records into stem buckets without renumbering positions. The one-based start+offset-1 expression crosses line boundaries while the reference is taken from tokens[start]. Numeric Dict keys are sorted, cached short stems are stable, and only the stopword Set is mutated by STOP/UNSTOP.

## Minimization and alternatives

The common scenario is fixed before language selection. Keeping all raw-token storage and the active-stopword filter, rather than selecting unrelated INDEX/SEARCH command implementations, is the smaller evidence set for why positions survive. The phrase loop and custom matching/reference/format helpers are necessary: names alone cannot prove wildcard width, cross-line matching or start-reference semantics. Only the short-word stemming branch is relevant; long-word suffix rules, KWIC, ranking, similarity, deletion and append are excluded. STOP and UNSTOP are both retained to show a changed subsequent query and the separate all-stopword error. Alternative long-word examples would require a larger Porter rule closure; an INDEX command trace would duplicate the already visible index storage/filter. Individual selected statements were reviewed for the input-to-output chain, and the final excerpt was independently checked against the common trace.

The excerpt contains 1980 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
