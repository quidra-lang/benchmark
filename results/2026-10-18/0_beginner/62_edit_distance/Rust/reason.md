# Task B selection: 62_edit_distance / Rust

## Common answer requirements

Explain empty-prefix initialization and the three prefix-subproblem transitions, including zero-cost matching, then trace flaw/lawn through the table entries needed for its final distance.

## Supported analysis

Let D(i,j) represent source prefix length i to target prefix length j. D(i,0)=i deletes the source prefix; D(0,j)=j inserts the target prefix. Each cell takes the minimum of D(i-1,j)+1 (delete source character), D(i,j-1)+1 (insert target character), and D(i-1,j-1)+cost (keep a match at zero or replace at one). For flaw/lawn the rows, including empty prefix, are [0,1,2,3,4], [1,1,2,3,4], [2,1,2,3,4], [3,2,1,2,3], [4,3,2,1,2]. A final optimal chain is D(1,0)=1, D(2,1)=1 for matching l, D(3,2)=1 for matching a, D(4,3)=1 for matching w, then D(4,4)=min(3+1,1+1,2+1)=2, inserting n. The selected character comparison and neighbor accesses establish those meanings and values rather than simply asserting the answer.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 14 | `    for (a, b) in [` |
| 4 | 14 | `        ("flaw", "lawn"),` |
| 8 | 5 | `    ] {` |
| 9 | 29 | `        let (m, n) = (a.len(), b.len());` |
| 10 | 35 | `        let mut dp = vec![vec![0; n + 1]; m + 1];` |
| 11 | 14 | `        for i in 0..=m {` |
| 12 | 16 | `            dp[i][0] = i;` |
| 13 | 4 | `        }` |
| 14 | 14 | `        for j in 0..=n {` |
| 15 | 16 | `            dp[0][j] = j;` |
| 16 | 4 | `        }` |
| 17 | 14 | `        for i in 1..=m {` |
| 18 | 15 | `            for j in 1..=n {` |
| 19 | 48 | `                let cost = usize::from(a.as_bytes()[i - 1] != b.as_bytes()[j - 1]);` |
| 20 | 32 | `                dp[i][j] = (dp[i - 1][j] + 1)` |
| 21 | 25 | `                    .min(dp[i][j - 1] + 1)` |
| 22 | 30 | `                    .min(dp[i - 1][j - 1] + cost);` |
| 23 | 5 | `            }` |
| 24 | 4 | `        }` |
| 26 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **341 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 442 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 343 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
