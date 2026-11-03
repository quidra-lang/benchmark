# Task B selection: 96_poker_hand_rank / Julia

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.jl`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L29,L30,L31,L32,L33,L34,L35,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L52,L54,L57,L61,L62,L63,L64,L65.

- L1: `function describe_hand(original)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    cards = split(original)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    alphabet = "23456789TJQKA"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    ranks = [findfirst(==(card[1]), alphabet)+1 for card in cards]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    frequencies = [count(==(rank), ranks) for rank = 2:14]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    distinct = [rank for rank = 2:14 if frequencies[rank-1] > 0]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    wheel = distinct == [2, 3, 4, 5, 14]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    straight = length(distinct) == 5 && (distinct[end]-distinct[1] == 4 || wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    flush = all(card[2] == cards[1][2] for card in cards)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    counts = sort([frequencies[rank-1] for rank in distinct]; rev = true)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    if straight && flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        strength = 9` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    elseif counts[1] == 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        strength = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    elseif counts == [3, 2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        strength = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    elseif flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        strength = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    elseif straight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        strength = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `    categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        "high card",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        "one pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        "two pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        "three of a kind",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    ]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `    sequence =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        wheel && straight ? [5, 4, 3, 2, 1] :` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        sort(distinct; by = rank -> (-frequencies[rank-1], -rank))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    return (` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        original = original,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        strength = strength,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        sequence = sequence,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        category = categories[strength],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `hands = describe_hand.([` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    "4D AH 3C 5S 2H",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    "3H 6C 4S 2D 5C",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `sort!(hands; by = hand -> (-hand.strength, Tuple(-rank for rank in hand.sequence)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `for (position, hand) in enumerate(hands)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `    println(position, ". ", hand.original, ": ", hand.category)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **647 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 620 tokens. The contiguous original span L1–L65 costs 865 tokens; the complete original source costs 865 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 638 tokens; removes `function describe_hand(original)` from the dependency chain described above.
- Without L2: 637 tokens; removes `cards = split(original)` from the dependency chain described above.
- Without L3: 630 tokens; removes `alphabet = "23456789TJQKA"` from the dependency chain described above.
- Without L4: 616 tokens; removes `ranks = [findfirst(==(card[1]), alphabet)+1 for card in cards]` from the dependency chain described above.
- Without L5: 618 tokens; removes `frequencies = [count(==(rank), ranks) for rank = 2:14]` from the dependency chain described above.
- Without L6: 614 tokens; removes `distinct = [rank for rank = 2:14 if frequencies[rank-1] > 0]` from the dependency chain described above.
- Without L7: 621 tokens; removes `wheel = distinct == [2, 3, 4, 5, 14]` from the dependency chain described above.
- Without L8: 611 tokens; removes `straight = length(distinct) == 5 && (distinct[end]-distinct[1] == 4 || wheel)` from the dependency chain described above.
- Without L9: 616 tokens; removes `flush = all(card[2] == cards[1][2] for card in cards)` from the dependency chain described above.
- Without L10: 615 tokens; removes `counts = sort([frequencies[rank-1] for rank in distinct]; rev = true)` from the dependency chain described above.
- Without L11: 638 tokens; removes `if straight && flush` from the dependency chain described above.
- Without L12: 639 tokens; removes `strength = 9` from the dependency chain described above.
- Without L13: 635 tokens; removes `elseif counts[1] == 4` from the dependency chain described above.
- Without L14: 639 tokens; removes `strength = 8` from the dependency chain described above.
- Without L15: 633 tokens; removes `elseif counts == [3, 2]` from the dependency chain described above.
- Without L16: 639 tokens; removes `strength = 7` from the dependency chain described above.
- Without L17: 642 tokens; removes `elseif flush` from the dependency chain described above.
- Without L18: 639 tokens; removes `strength = 6` from the dependency chain described above.
- Without L19: 642 tokens; removes `elseif straight` from the dependency chain described above.
- Without L20: 639 tokens; removes `strength = 5` from the dependency chain described above.
- Without L29: 644 tokens; removes `end` from the dependency chain described above.
- Without L30: 640 tokens; removes `categories = [` from the dependency chain described above.
- Without L31: 638 tokens; removes `"high card",` from the dependency chain described above.
- Without L32: 638 tokens; removes `"one pair",` from the dependency chain described above.
- Without L33: 638 tokens; removes `"two pair",` from the dependency chain described above.
- Without L34: 634 tokens; removes `"three of a kind",` from the dependency chain described above.
- Without L35: 640 tokens; removes `"straight",` from the dependency chain described above.
- Without L40: 644 tokens; removes `]` from the dependency chain described above.
- Without L41: 642 tokens; removes `sequence =` from the dependency chain described above.
- Without L42: 619 tokens; removes `wheel && straight ? [5, 4, 3, 2, 1] :` from the dependency chain described above.
- Without L43: 617 tokens; removes `sort(distinct; by = rank -> (-frequencies[rank-1], -rank))` from the dependency chain described above.
- Without L44: 642 tokens; removes `return (` from the dependency chain described above.
- Without L45: 638 tokens; removes `original = original,` from the dependency chain described above.
- Without L46: 638 tokens; removes `strength = strength,` from the dependency chain described above.
- Without L47: 638 tokens; removes `sequence = sequence,` from the dependency chain described above.
- Without L48: 635 tokens; removes `category = categories[strength],` from the dependency chain described above.
- Without L49: 644 tokens; removes `)` from the dependency chain described above.
- Without L50: 645 tokens; removes `end` from the dependency chain described above.
- Without L52: 636 tokens; removes `hands = describe_hand.([` from the dependency chain described above.
- Without L54: 629 tokens; removes `"4D AH 3C 5S 2H",` from the dependency chain described above.
- Without L57: 628 tokens; removes `"3H 6C 4S 2D 5C",` from the dependency chain described above.
- Without L61: 644 tokens; removes `])` from the dependency chain described above.
- Without L62: 608 tokens; removes `sort!(hands; by = hand -> (-hand.strength, Tuple(-rank for rank in hand.sequence)))` from the dependency chain described above.
- Without L63: 631 tokens; removes `for (position, hand) in enumerate(hands)` from the dependency chain described above.
- Without L64: 619 tokens; removes `println(position, ". ", hand.original, ": ", hand.category)` from the dependency chain described above.
- Without L65: 645 tokens; removes `end` from the dependency chain described above.
