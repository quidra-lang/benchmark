# Task B selection: 62_edit_distance / Dart

## Common answer requirements

Explain empty-prefix initialization and the three prefix-subproblem transitions, including zero-cost matching, then trace flaw/lawn through the table entries needed for its final distance.

## Supported analysis

Let D(i,j) represent source prefix length i to target prefix length j. D(i,0)=i deletes the source prefix; D(0,j)=j inserts the target prefix. Each cell takes the minimum of D(i-1,j)+1 (delete source character), D(i,j-1)+1 (insert target character), and D(i-1,j-1)+cost (keep a match at zero or replace at one). For flaw/lawn the rows, including empty prefix, are [0,1,2,3,4], [1,1,2,3,4], [2,1,2,3,4], [3,2,1,2,3], [4,3,2,1,2]. A final optimal chain is D(1,0)=1, D(2,1)=1 for matching l, D(3,2)=1 for matching a, D(4,3)=1 for matching w, then D(4,4)=min(3+1,1+1,2+1)=2, inserting n. The selected character comparison and neighbor accesses establish those meanings and values rather than simply asserting the answer.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 4 | 12 | `  for (final p in [` |
| 6 | 13 | `    ('flaw', 'lawn'),` |
| 10 | 6 | `  ]) {` |
| 11 | 12 | `    final a = p.$1,` |
| 12 | 11 | `        b = p.$2,` |
| 13 | 11 | `        dp = List.generate(` |
| 14 | 15 | `          p.$1.length + 1,` |
| 15 | 29 | `          (_) => List.filled(p.$2.length + 1, 0),` |
| 16 | 5 | `        );` |
| 17 | 28 | `    for (var i = 0; i <= a.length; i++) {` |
| 18 | 15 | `      dp[i][0] = i;` |
| 19 | 3 | `    }` |
| 20 | 28 | `    for (var j = 0; j <= b.length; j++) {` |
| 21 | 15 | `      dp[0][j] = j;` |
| 22 | 3 | `    }` |
| 23 | 28 | `    for (var i = 1; i <= a.length; i++) {` |
| 24 | 29 | `      for (var j = 1; j <= b.length; j++) {` |
| 25 | 17 | `        dp[i][j] = math.min(` |
| 26 | 42 | `          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),` |
| 27 | 52 | `          dp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),` |
| 28 | 5 | `        );` |
| 29 | 4 | `      }` |
| 30 | 3 | `    }` |
| 32 | 3 | `  }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **389 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 495 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 391 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
