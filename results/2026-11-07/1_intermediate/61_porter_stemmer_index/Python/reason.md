# Task B selection — Python

## Answer requirements shared across languages

1. Load an initial stopword set and a document with multiple body lines, retaining maximal ASCII-letter tokens in original order, one-based document-wide positions and one-based line numbers.
2. Explain lowercase query/document forms, stemming and index inclusion without discarding original tokens; an active stopword is not indexed but still occupies its original position.
3. Trace PHRASE argument validation, normalization into stems and one-token stopword wildcards, matching consecutive original tokens across a line boundary, numeric document/reference ordering and output of starting references.
4. Change the stopword set and query again; prove the original token positions are unchanged and explain the distinct all-stopword query error and printed STOP/UNSTOP counts.
5. Use the same concrete short-word scenario in every language, allowing the no-suffix stemming base case to supply sufficient evidence without unrelated Porter suffix rules.

## Selected source locations

- `main.py`: 9, 10, 29, 30, 139, 140, 141, 147, 151, 152, 159, 160, 161, 162, 174, 175, 176, 177, 178, 179, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 250, 251, 324, 325, 326, 327, 328, 329, 335, 347, 348, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 382, 383, 384, 385, 386, 387, 395, 396, 397, 398, 399, 400, 401, 402, 403, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672

## Evidence and language semantics

Trace STOPWORDS a; DOC 1; body lines "Ox a," and "ox"; ENDDOC; PHRASE A ox; UNSTOP a; PHRASE A ox; STOP ox; PHRASE ox ox; END. Original tokens are (ox,line1,pos1), (a,line1,pos2), (ox,line2,pos3). The initial index contains ox at positions1,3. The first PHRASE normalizes to "? ox", matches across the line boundary starting at 1:1:2, and prints PHRASE "? ox" matches=1 1:1:2. UNSTOP a prints indexed=1 and makes the next phrase "a ox", again matches=1 1:1:2. STOP ox prints unindexed=2; the final query raises ERROR STOPWORDS ONLY before matching. Every chosen form has at most two letters, so the selected early-return/no-step stemming branch proves the actual stems without needing suffix rules. Tokens are dataclass objects kept in each document, and occurrence_map builds a stem-keyed view of non-stopword objects. No stop-set mutation rewrites tokens, so the surviving ox positions remain1 and3. Python short-circuit or makes wildcard match any one stored token, while nonwildcard requires current indexing and the stem. range of windows spans the entire document.tokens sequence, independently of its lines; sorted document IDs and sequential starts fix reference order.

## Minimization and alternatives

The common scenario is fixed before language selection. Keeping all raw-token storage and the active-stopword filter, rather than selecting unrelated INDEX/SEARCH command implementations, is the smaller evidence set for why positions survive. The phrase loop and custom matching/reference/format helpers are necessary: names alone cannot prove wildcard width, cross-line matching or start-reference semantics. Only the short-word stemming branch is relevant; long-word suffix rules, KWIC, ranking, similarity, deletion and append are excluded. STOP and UNSTOP are both retained to show a changed subsequent query and the separate all-stopword error. Alternative long-word examples would require a larger Porter rule closure; an INDEX command trace would duplicate the already visible index storage/filter. Individual selected statements were reviewed for the input-to-output chain, and the final excerpt was independently checked against the common trace.

The excerpt contains 1988 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
