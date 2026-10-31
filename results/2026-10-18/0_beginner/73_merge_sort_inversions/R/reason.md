# Task B selection: 73_merge_sort_inversions / R

## Common answer requirements

Identify merge-trace formatting and inversion state lifetime; explain appending one space plus inversions=K with cumulative increments from all completed earlier work, preserving final sorted/inversions lines.

## Supported analysis

Append " inversions=" and the ordinary decimal cumulative count at the merge trace after all merged values and before its newline. A shared counter threaded through recursion, captured by a closure, or carried as incoming/outgoing state already includes earlier merges: reuse that counter at the trace. Where the current count is only a subtree return value, it is insufficient during a right-subtree trace because it excludes completed work elsewhere. Add a separate shared cumulative counter initialized once at the top call, increment it by the same cross-inversion delta at each existing increment site, pass/capture it in recursive calls, and print it at the trace; retain the current subtree return values for unchanged final reporting. Do not add returned child counts into the shared counter a second time. An equivalent solution threads an incoming count offset left-first, then into the right call with the completed left count, and prints offset plus completed subtree count. The selected signatures/calls, increment, return and trace/output boundary establish the affected paths.

Each base returns inversions=0 and parents sum left/right subtree counts; a separate mutable shared accumulator or incoming offset must reach recursive calls. The current list return remains suitable for unchanged final totals. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.R`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 19 | `merge_sort <- function(numbers, lo, hi) {` |
| 2 | 13 | `  if (lo == hi) {` |
| 3 | 20 | `    return(list(numbers = numbers, inversions = 0))` |
| 4 | 3 | `  }` |
| 5 | 17 | `  mid <- (lo + hi) %/% 2` |
| 6 | 20 | `  left_result <- merge_sort(numbers, lo, mid)` |
| 7 | 28 | `  right_result <- merge_sort(left_result$numbers, mid + 1, hi)` |
| 8 | 11 | `  numbers <- right_result$numbers` |
| 9 | 19 | `  inversions <- left_result$inversions + right_result$inversions` |
| 22 | 23 | `      inversions <- inversions + length(left) - i + 1` |
| 28 | 50 | `  cat(sprintf("merge [%d..%d]: %s\n", lo - 1, hi - 1, paste(merged, collapse = " ")))` |
| 29 | 17 | `  list(numbers = numbers, inversions = inversions)` |
| 30 | 2 | `}` |
| 32 | 57 | `result <- merge_sort(c(47, 12, 85, 33, 6, 71, 29, 58, 90, 14), 1, 10)` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **299 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 595 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 305 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
