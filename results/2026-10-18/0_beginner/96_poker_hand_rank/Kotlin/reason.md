# Task B selection: 96_poker_hand_rank / Kotlin

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.kt`. Selected original locations: L1,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L22,L23,L24,L25,L26,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43.

- L1: `data class Hand(val text: String, val category: Int, val sequence: List<Int>)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `fun evaluate(text: String): Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    val cards = text.split(' ')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    val counts = cards.groupingBy { "23456789TJQKA".indexOf(it[0]) + 2 }.eachCount()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    val ranks = counts.keys.sorted()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    val wheel = ranks == listOf(2, 3, 4, 5, 14)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    val straight = wheel || (ranks.size == 5 && ranks.last() - ranks.first() == 4)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    val flush = cards.all { it[1] == cards[0][1] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    val largest = counts.values.max()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    val pairs = counts.values.count { it == 2 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    val category = when {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        straight && flush -> 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        largest == 4 -> 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        largest == 3 && pairs == 1 -> 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        flush -> 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        straight -> 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    var sequence = counts.keys.sortedWith(compareByDescending<Int> { counts.getValue(it) }.thenByDescending { it })` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    if (wheel && straight) sequence = listOf(5, 4, 3, 2, 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    return Hand(text, category, sequence)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    val input = listOf("9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    val categories = listOf("high card", "one pair", "two pair", "three of a kind", "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        "flush", "full house", "four of a kind", "straight flush")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    val hands = input.map(::evaluate).sortedWith { a, b ->` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        var comparison = b.category.compareTo(a.category)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        if (comparison == 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            for (i in a.sequence.indices) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `                comparison = b.sequence[i].compareTo(a.sequence[i])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                if (comparison != 0) break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `        comparison` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    for ((i, hand) in hands.withIndex()) println("${i + 1}. ${hand.text}: ${categories[hand.category]}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **841 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 759 tokens. The contiguous original span L1–L43 costs 895 tokens; the complete original source costs 897 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 808 tokens; removes `data class Hand(val text: String, val category: Int, val sequence: List<Int>)` from the dependency chain described above.
- Without L3: 826 tokens; removes `fun evaluate(text: String): Hand {` from the dependency chain described above.
- Without L4: 825 tokens; removes `val cards = text.split(' ')` from the dependency chain described above.
- Without L5: 796 tokens; removes `val counts = cards.groupingBy { "23456789TJQKA".indexOf(it[0]) + 2 }.eachCount()` from the dependency chain described above.
- Without L6: 826 tokens; removes `val ranks = counts.keys.sorted()` from the dependency chain described above.
- Without L7: 811 tokens; removes `val wheel = ranks == listOf(2, 3, 4, 5, 14)` from the dependency chain described above.
- Without L8: 800 tokens; removes `val straight = wheel || (ranks.size == 5 && ranks.last() - ranks.first() == 4)` from the dependency chain described above.
- Without L9: 811 tokens; removes `val flush = cards.all { it[1] == cards[0][1] }` from the dependency chain described above.
- Without L10: 826 tokens; removes `val largest = counts.values.max()` from the dependency chain described above.
- Without L11: 818 tokens; removes `val pairs = counts.values.count { it == 2 }` from the dependency chain described above.
- Without L12: 830 tokens; removes `val category = when {` from the dependency chain described above.
- Without L13: 829 tokens; removes `straight && flush -> 8` from the dependency chain described above.
- Without L14: 829 tokens; removes `largest == 4 -> 7` from the dependency chain described above.
- Without L15: 821 tokens; removes `largest == 3 && pairs == 1 -> 6` from the dependency chain described above.
- Without L16: 833 tokens; removes `flush -> 5` from the dependency chain described above.
- Without L17: 833 tokens; removes `straight -> 4` from the dependency chain described above.
- Without L22: 838 tokens; removes `}` from the dependency chain described above.
- Without L23: 798 tokens; removes `var sequence = counts.keys.sortedWith(compareByDescending<Int> { counts.getValue(it) }.thenByDescending { it })` from the dependency chain described above.
- Without L24: 808 tokens; removes `if (wheel && straight) sequence = listOf(5, 4, 3, 2, 1)` from the dependency chain described above.
- Without L25: 827 tokens; removes `return Hand(text, category, sequence)` from the dependency chain described above.
- Without L26: 839 tokens; removes `}` from the dependency chain described above.
- Without L29: 765 tokens; removes `val input = listOf("9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L30: 773 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D")` from the dependency chain described above.
- Without L31: 794 tokens; removes `val categories = listOf("high card", "one pair", "two pair", "three of a kind", "straight",` from the dependency chain described above.
- Without L32: 809 tokens; removes `"flush", "full house", "four of a kind", "straight flush")` from the dependency chain described above.
- Without L33: 814 tokens; removes `val hands = input.map(::evaluate).sortedWith { a, b ->` from the dependency chain described above.
- Without L34: 821 tokens; removes `var comparison = b.category.compareTo(a.category)` from the dependency chain described above.
- Without L35: 827 tokens; removes `if (comparison == 0) {` from the dependency chain described above.
- Without L36: 822 tokens; removes `for (i in a.sequence.indices) {` from the dependency chain described above.
- Without L37: 816 tokens; removes `comparison = b.sequence[i].compareTo(a.sequence[i])` from the dependency chain described above.
- Without L38: 825 tokens; removes `if (comparison != 0) break` from the dependency chain described above.
- Without L39: 836 tokens; removes `}` from the dependency chain described above.
- Without L40: 837 tokens; removes `}` from the dependency chain described above.
- Without L41: 837 tokens; removes `comparison` from the dependency chain described above.
- Without L42: 838 tokens; removes `}` from the dependency chain described above.
- Without L43: 789 tokens; removes `for ((i, hand) in hands.withIndex()) println("${i + 1}. ${hand.text}: ${categories[hand.category]}")` from the dependency chain described above.
