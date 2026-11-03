# Task B selection: 96_poker_hand_rank / PHP

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L24,L25,L26,L27,L28,L29,L30,L32,L33,L34,L35,L36,L37,L38,L39,L41,L42,L43,L44,L45,L46,L47,L48,L49.

- L3: `function describeHand(string $original): array` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `    $cards = explode(' ', $original);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    $frequencies = array_count_values(array_map(fn($card) => strpos('23456789TJQKA', $card[0]) + 2, $cards));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    $distinct = array_keys($frequencies);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    sort($distinct, SORT_NUMERIC);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    $wheel = $distinct === [2, 3, 4, 5, 14];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    $straight = count($distinct) === 5 && (max($distinct) - min($distinct) === 4 || $wheel);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    $flush = count(array_unique(array_map(fn($card) => $card[1], $cards))) === 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    $counts = $frequencies;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    rsort($counts, SORT_NUMERIC);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    $strength = match (true) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        $straight && $flush => 9,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        $counts[0] === 4 => 8,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        $counts === [3, 2] => 7,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        $flush => 6,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        $straight => 5,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `    usort($distinct, fn($a, $b) => ($frequencies[$b] <=> $frequencies[$a]) ?: ($b <=> $a));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    if ($wheel && $straight) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        $distinct = [5, 4, 3, 2, 1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    $categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        'high card', 'one pair', 'two pair', 'three of a kind', 'straight', 'flush', 'full house',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    return [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        'original' => $original,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        'strength' => $strength,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        'sequence' => $distinct,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        'category' => $categories[$strength - 1],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `$originals = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    '9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    '3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `$hands = array_map('describeHand', $originals);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `usort($hands, fn($a, $b) => ($b['strength'] <=> $a['strength']) ?: ($b['sequence'] <=> $a['sequence']));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `foreach ($hands as $position => $hand) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    printf("%d. %s: %s\n", $position + 1, $hand['original'], $hand['category']);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **860 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 829 tokens. The contiguous original span L3–L49 costs 946 tokens; the complete original source costs 951 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 846 tokens; removes `function describeHand(string $original): array` from the dependency chain described above.
- Without L4: 858 tokens; removes `{` from the dependency chain described above.
- Without L5: 842 tokens; removes `$cards = explode(' ', $original);` from the dependency chain described above.
- Without L6: 803 tokens; removes `$frequencies = array_count_values(array_map(fn($card) => strpos('23456789TJQKA', $card[0]) + 2, $cards));` from the dependency chain described above.
- Without L7: 845 tokens; removes `$distinct = array_keys($frequencies);` from the dependency chain described above.
- Without L8: 847 tokens; removes `sort($distinct, SORT_NUMERIC);` from the dependency chain described above.
- Without L9: 831 tokens; removes `$wheel = $distinct === [2, 3, 4, 5, 14];` from the dependency chain described above.
- Without L10: 816 tokens; removes `$straight = count($distinct) === 5 && (max($distinct) - min($distinct) === 4 || $wheel);` from the dependency chain described above.
- Without L11: 818 tokens; removes `$flush = count(array_unique(array_map(fn($card) => $card[1], $cards))) === 1;` from the dependency chain described above.
- Without L12: 850 tokens; removes `$counts = $frequencies;` from the dependency chain described above.
- Without L13: 847 tokens; removes `rsort($counts, SORT_NUMERIC);` from the dependency chain described above.
- Without L14: 846 tokens; removes `$strength = match (true) {` from the dependency chain described above.
- Without L15: 845 tokens; removes `$straight && $flush => 9,` from the dependency chain described above.
- Without L16: 843 tokens; removes `$counts[0] === 4 => 8,` from the dependency chain described above.
- Without L17: 841 tokens; removes `$counts === [3, 2] => 7,` from the dependency chain described above.
- Without L18: 850 tokens; removes `$flush => 6,` from the dependency chain described above.
- Without L19: 850 tokens; removes `$straight => 5,` from the dependency chain described above.
- Without L24: 856 tokens; removes `};` from the dependency chain described above.
- Without L25: 809 tokens; removes `usort($distinct, fn($a, $b) => ($frequencies[$b] <=> $frequencies[$a]) ?: ($b <=> $a));` from the dependency chain described above.
- Without L26: 845 tokens; removes `if ($wheel && $straight) {` from the dependency chain described above.
- Without L27: 836 tokens; removes `$distinct = [5, 4, 3, 2, 1];` from the dependency chain described above.
- Without L28: 857 tokens; removes `}` from the dependency chain described above.
- Without L29: 852 tokens; removes `$categories = [` from the dependency chain described above.
- Without L30: 809 tokens; removes `'high card', 'one pair', 'two pair', 'three of a kind', 'straight', 'flush', 'full house',` from the dependency chain described above.
- Without L32: 856 tokens; removes `];` from the dependency chain described above.
- Without L33: 855 tokens; removes `return [` from the dependency chain described above.
- Without L34: 848 tokens; removes `'original' => $original,` from the dependency chain described above.
- Without L35: 848 tokens; removes `'strength' => $strength,` from the dependency chain described above.
- Without L36: 848 tokens; removes `'sequence' => $distinct,` from the dependency chain described above.
- Without L37: 840 tokens; removes `'category' => $categories[$strength - 1],` from the dependency chain described above.
- Without L38: 856 tokens; removes `];` from the dependency chain described above.
- Without L39: 858 tokens; removes `}` from the dependency chain described above.
- Without L41: 853 tokens; removes `$originals = [` from the dependency chain described above.
- Without L42: 793 tokens; removes `'9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',` from the dependency chain described above.
- Without L43: 793 tokens; removes `'3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D',` from the dependency chain described above.
- Without L44: 857 tokens; removes `];` from the dependency chain described above.
- Without L45: 840 tokens; removes `$hands = array_map('describeHand', $originals);` from the dependency chain described above.
- Without L46: 798 tokens; removes `usort($hands, fn($a, $b) => ($b['strength'] <=> $a['strength']) ?: ($b['sequence'] <=> $a['sequence']));` from the dependency chain described above.
- Without L47: 841 tokens; removes `foreach ($hands as $position => $hand) {` from the dependency chain described above.
- Without L48: 816 tokens; removes `printf("%d. %s: %s\n", $position + 1, $hand['original'], $hand['category']);` from the dependency chain described above.
- Without L49: 858 tokens; removes `}` from the dependency chain described above.
