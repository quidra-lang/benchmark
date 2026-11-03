# Task B selection: 96_poker_hand_rank / Ruby

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.rb`. Selected original locations: L1,L2,L3,L4,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L35,L36,L37,L38,L39,L40,L41,L42,L43.

- L1: `hands = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  '9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  '3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  'high card', 'one pair', 'two pair', 'three of a kind', 'straight',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `ranked = hands.map do |hand|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  cards = hand.split` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  counts = cards.map { |card| '23456789TJQKA'.index(card[0]) + 2 }.tally` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  ranks = counts.keys.sort` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  wheel = ranks == [2, 3, 4, 5, 14]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  straight = ranks.length == 5 && (ranks[-1] - ranks[0] == 4 || wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  flush = cards.map { |card| card[1] }.uniq.length == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  pattern = counts.values.sort.reverse` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  strength = if straight && flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `               8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `             elsif pattern[0] == 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `               7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `             elsif pattern == [3, 2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `               6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `             elsif flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `               5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `             elsif straight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `               4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `             end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `  sequence = counts.keys.sort_by { |rank| [-counts[rank], -rank] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `  sequence = [5, 4, 3, 2, 1] if wheel && straight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `  [strength, sequence, hand]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `ranked.sort_by! { |strength, sequence, _| [-strength, *sequence.map { |rank| -rank }] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `ranked.each_with_index do |(strength, _, hand), i|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `  puts "#{i + 1}. #{hand}: #{categories[strength]}"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **643 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 623 tokens. The contiguous original span L1–L43 costs 757 tokens; the complete original source costs 757 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 637 tokens; removes `hands = [` from the dependency chain described above.
- Without L2: 576 tokens; removes `'9C 9D 5H QH 2C', '4D AH 3C 5S 2H', 'KS 8S 2S JS 6S', '7H 7D KC 7S KD',` from the dependency chain described above.
- Without L3: 577 tokens; removes `'3H 6C 4S 2D 5C', 'JD TC 4H 8C AS', 'QC 6D QS 3S 6H', '9H KH 9S 8H 3D'` from the dependency chain described above.
- Without L4: 641 tokens; removes `]` from the dependency chain described above.
- Without L5: 637 tokens; removes `categories = [` from the dependency chain described above.
- Without L6: 605 tokens; removes `'high card', 'one pair', 'two pair', 'three of a kind', 'straight',` from the dependency chain described above.
- Without L8: 641 tokens; removes `]` from the dependency chain described above.
- Without L9: 629 tokens; removes `ranked = hands.map do |hand|` from the dependency chain described above.
- Without L10: 634 tokens; removes `cards = hand.split` from the dependency chain described above.
- Without L11: 601 tokens; removes `counts = cards.map { |card| '23456789TJQKA'.index(card[0]) + 2 }.tally` from the dependency chain described above.
- Without L12: 632 tokens; removes `ranks = counts.keys.sort` from the dependency chain described above.
- Without L13: 617 tokens; removes `wheel = ranks == [2, 3, 4, 5, 14]` from the dependency chain described above.
- Without L14: 605 tokens; removes `straight = ranks.length == 5 && (ranks[-1] - ranks[0] == 4 || wheel)` from the dependency chain described above.
- Without L15: 614 tokens; removes `flush = cards.map { |card| card[1] }.uniq.length == 1` from the dependency chain described above.
- Without L16: 630 tokens; removes `pattern = counts.values.sort.reverse` from the dependency chain described above.
- Without L17: 630 tokens; removes `strength = if straight && flush` from the dependency chain described above.
- Without L18: 636 tokens; removes `8` from the dependency chain described above.
- Without L19: 628 tokens; removes `elsif pattern[0] == 4` from the dependency chain described above.
- Without L20: 636 tokens; removes `7` from the dependency chain described above.
- Without L21: 626 tokens; removes `elsif pattern == [3, 2]` from the dependency chain described above.
- Without L22: 636 tokens; removes `6` from the dependency chain described above.
- Without L23: 635 tokens; removes `elsif flush` from the dependency chain described above.
- Without L24: 636 tokens; removes `5` from the dependency chain described above.
- Without L25: 635 tokens; removes `elsif straight` from the dependency chain described above.
- Without L26: 636 tokens; removes `4` from the dependency chain described above.
- Without L35: 637 tokens; removes `end` from the dependency chain described above.
- Without L36: 610 tokens; removes `sequence = counts.keys.sort_by { |rank| [-counts[rank], -rank] }` from the dependency chain described above.
- Without L37: 614 tokens; removes `sequence = [5, 4, 3, 2, 1] if wheel && straight` from the dependency chain described above.
- Without L38: 632 tokens; removes `[strength, sequence, hand]` from the dependency chain described above.
- Without L39: 641 tokens; removes `end` from the dependency chain described above.
- Without L40: 600 tokens; removes `ranked.sort_by! { |strength, sequence, _| [-strength, *sequence.map { |rank| -rank }] }` from the dependency chain described above.
- Without L41: 618 tokens; removes `ranked.each_with_index do |(strength, _, hand), i|` from the dependency chain described above.
- Without L42: 616 tokens; removes `puts "#{i + 1}. #{hand}: #{categories[strength]}"` from the dependency chain described above.
- Without L43: 641 tokens; removes `end` from the dependency chain described above.
