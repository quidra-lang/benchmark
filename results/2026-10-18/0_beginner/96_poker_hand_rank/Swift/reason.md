# Task B selection: 96_poker_hand_rank / Swift

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.swift`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L28,L30,L32,L34,L35,L36,L37,L38,L40,L41,L42,L43,L44,L45,L46,L47,L48.

- L1: `struct Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    let text: String` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    let category: Int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    let sequence: [Int]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `func evaluate(_ text: String) -> Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    let cards = text.split(separator: " ").map { Array($0) }, alphabet = Array("23456789TJQKA")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    var counts = [Int: Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    for card in cards { counts[alphabet.firstIndex(of: card[0])! + 2, default: 0] += 1 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    let ranks = counts.keys.sorted(), wheel = ranks == [2, 3, 4, 5, 14]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    let straight = wheel || (ranks.count == 5 && ranks.last! - ranks.first! == 4)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    let flush = cards.allSatisfy { $0[1] == cards[0][1] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    let largest = counts.values.max()!, pairs = counts.values.filter { $0 == 2 }.count` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    let category: Int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    if straight && flush {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        category = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    } else if largest == 4 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        category = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else if largest == 3 && pairs == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        category = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    } else if flush {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        category = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    } else if straight {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        category = 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    } else if largest == 3 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    } else if pairs == 2 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    } else if pairs == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    var sequence = counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 > $1 : counts[$0]! > counts[$1]! }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    if wheel && straight { sequence = [5, 4, 3, 2, 1] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    return Hand(text: text, category: category, sequence: sequence)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `let input = ["9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `let categories = ["high card", "one pair", "two pair", "three of a kind", "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    "flush", "full house", "four of a kind", "straight flush"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `let hands = input.map(evaluate).sorted { a, b in` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    if a.category != b.category { return a.category > b.category }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    return b.sequence.lexicographicallyPrecedes(a.sequence)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `for (i, hand) in hands.enumerated() { print("\(i + 1). \(hand.text): \(categories[hand.category])") }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **947 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 823 tokens. The contiguous original span L1–L48 costs 981 tokens; the complete original source costs 981 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 941 tokens; removes `struct Hand {` from the dependency chain described above.
- Without L2: 939 tokens; removes `let text: String` from the dependency chain described above.
- Without L3: 939 tokens; removes `let category: Int` from the dependency chain described above.
- Without L4: 937 tokens; removes `let sequence: [Int]` from the dependency chain described above.
- Without L5: 945 tokens; removes `}` from the dependency chain described above.
- Without L7: 929 tokens; removes `func evaluate(_ text: String) -> Hand {` from the dependency chain described above.
- Without L8: 896 tokens; removes `let cards = text.split(separator: " ").map { Array($0) }, alphabet = Array("23456789TJQKA")` from the dependency chain described above.
- Without L9: 931 tokens; removes `var counts = [Int: Int]()` from the dependency chain described above.
- Without L10: 902 tokens; removes `for card in cards { counts[alphabet.firstIndex(of: card[0])! + 2, default: 0] += 1 }` from the dependency chain described above.
- Without L11: 906 tokens; removes `let ranks = counts.keys.sorted(), wheel = ranks == [2, 3, 4, 5, 14]` from the dependency chain described above.
- Without L12: 908 tokens; removes `let straight = wheel || (ranks.count == 5 && ranks.last! - ranks.first! == 4)` from the dependency chain described above.
- Without L13: 915 tokens; removes `let flush = cards.allSatisfy { $0[1] == cards[0][1] }` from the dependency chain described above.
- Without L14: 908 tokens; removes `let largest = counts.values.max()!, pairs = counts.values.filter { $0 == 2 }.count` from the dependency chain described above.
- Without L15: 939 tokens; removes `let category: Int` from the dependency chain described above.
- Without L16: 936 tokens; removes `if straight && flush {` from the dependency chain described above.
- Without L17: 939 tokens; removes `category = 8` from the dependency chain described above.
- Without L18: 932 tokens; removes `} else if largest == 4 {` from the dependency chain described above.
- Without L19: 939 tokens; removes `category = 7` from the dependency chain described above.
- Without L20: 924 tokens; removes `} else if largest == 3 && pairs == 1 {` from the dependency chain described above.
- Without L21: 939 tokens; removes `category = 6` from the dependency chain described above.
- Without L22: 936 tokens; removes `} else if flush {` from the dependency chain described above.
- Without L23: 939 tokens; removes `category = 5` from the dependency chain described above.
- Without L24: 936 tokens; removes `} else if straight {` from the dependency chain described above.
- Without L25: 939 tokens; removes `category = 4` from the dependency chain described above.
- Without L26: 932 tokens; removes `} else if largest == 3 {` from the dependency chain described above.
- Without L28: 932 tokens; removes `} else if pairs == 2 {` from the dependency chain described above.
- Without L30: 932 tokens; removes `} else if pairs == 1 {` from the dependency chain described above.
- Without L32: 940 tokens; removes `} else {` from the dependency chain described above.
- Without L34: 944 tokens; removes `}` from the dependency chain described above.
- Without L35: 886 tokens; removes `var sequence = counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 > $1 : counts[$0]! > counts[$1]! }` from the dependency chain described above.
- Without L36: 914 tokens; removes `if wheel && straight { sequence = [5, 4, 3, 2, 1] }` from the dependency chain described above.
- Without L37: 924 tokens; removes `return Hand(text: text, category: category, sequence: sequence)` from the dependency chain described above.
- Without L38: 945 tokens; removes `}` from the dependency chain described above.
- Without L40: 874 tokens; removes `let input = ["9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L41: 880 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"]` from the dependency chain described above.
- Without L42: 903 tokens; removes `let categories = ["high card", "one pair", "two pair", "three of a kind", "straight",` from the dependency chain described above.
- Without L43: 916 tokens; removes `"flush", "full house", "four of a kind", "straight flush"]` from the dependency chain described above.
- Without L44: 923 tokens; removes `let hands = input.map(evaluate).sorted { a, b in` from the dependency chain described above.
- Without L45: 918 tokens; removes `if a.category != b.category { return a.category > b.category }` from the dependency chain described above.
- Without L46: 932 tokens; removes `return b.sequence.lexicographicallyPrecedes(a.sequence)` from the dependency chain described above.
- Without L47: 945 tokens; removes `}` from the dependency chain described above.
- Without L48: 893 tokens; removes `for (i, hand) in hands.enumerated() { print("\(i + 1). \(hand.text): \(categories[hand.category])") }` from the dependency chain described above.
