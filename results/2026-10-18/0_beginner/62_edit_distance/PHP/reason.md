# Task B selection: 62_edit_distance / PHP

## Common answer requirements

Explain empty-prefix initialization and the three prefix-subproblem transitions, including zero-cost matching, then trace flaw/lawn through the table entries needed for its final distance.

## Supported analysis

Let D(i,j) represent source prefix length i to target prefix length j. D(i,0)=i deletes the source prefix; D(0,j)=j inserts the target prefix. Each cell takes the minimum of D(i-1,j)+1 (delete source character), D(i,j-1)+1 (insert target character), and D(i-1,j-1)+cost (keep a match at zero or replace at one). For flaw/lawn the rows, including empty prefix, are [0,1,2,3,4], [1,1,2,3,4], [2,1,2,3,4], [3,2,1,2,3], [4,3,2,1,2]. A final optimal chain is D(1,0)=1, D(2,1)=1 for matching l, D(3,2)=1 for matching a, D(4,3)=1 for matching w, then D(4,4)=min(3+1,1+1,2+1)=2, inserting n. The selected character comparison and neighbor accesses establish those meanings and values rather than simply asserting the answer.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.php`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 20 | `function editDistance(string $a, string $b): int` |
| 4 | 2 | `{` |
| 5 | 47 | `    $table = array_fill(0, strlen($a) + 1, array_fill(0, strlen($b) + 1, 0));` |
| 6 | 31 | `    for ($i = 0; $i <= strlen($a); $i++) {` |
| 7 | 18 | `        $table[$i][0] = $i;` |
| 8 | 3 | `    }` |
| 9 | 31 | `    for ($j = 0; $j <= strlen($b); $j++) {` |
| 10 | 18 | `        $table[0][$j] = $j;` |
| 11 | 3 | `    }` |
| 12 | 31 | `    for ($i = 1; $i <= strlen($a); $i++) {` |
| 13 | 32 | `        for ($j = 1; $j <= strlen($b); $j++) {` |
| 14 | 41 | `            $cost = $a[$i - 1] === $b[$j - 1] ? 0 : 1;` |
| 15 | 84 | `            $table[$i][$j] = min($table[$i - 1][$j] + 1, $table[$i][$j - 1] + 1, $table[$i - 1][$j - 1] + $cost);` |
| 16 | 4 | `        }` |
| 17 | 3 | `    }` |
| 18 | 21 | `    return $table[strlen($a)][strlen($b)];` |
| 19 | 2 | `}` |
| 21 | 7 | `$pairs = [` |
| 22 | 49 | `    ['kitten', 'sitting'], ['flaw', 'lawn'], ['listen', 'silent'], ['intention', 'execution'],` |
| 24 | 3 | `];` |
| 25 | 20 | `foreach ($pairs as [$a, $b]) {` |
| 26 | 40 | `    printf("%s -> %s: %d\n", $a, $b, editDistance($a, $b));` |
| 27 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **512 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 531 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 512 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
