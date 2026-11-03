# Task B selection: 96_poker_hand_rank / Python

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.py`. Selected original locations: L1,L3,L5,L8,L12,L13,L14,L15,L16,L17,L18,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L51,L52,L53,L54,L55,L56,L57.

- L1: `from collections import Counter` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `hands = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    "4D AH 3C 5S 2H",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    "3H 6C 4S 2D 5C",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    "high card",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    "one pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    "two pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    "three of a kind",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `ranked = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `for hand in hands:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    cards = hand.split()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    counts = Counter("23456789TJQKA".index(card[0]) + 2 for card in cards)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    ranks = sorted(counts)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    wheel = ranks == [2, 3, 4, 5, 14]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    straight = len(ranks) == 5 and (ranks[-1] - ranks[0] == 4 or wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    flush = len({card[1] for card in cards}) == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    pattern = sorted(counts.values(), reverse=True)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    if straight and flush:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        strength = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    elif pattern[0] == 4:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        strength = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    elif pattern == [3, 2]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        strength = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    elif flush:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        strength = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    elif straight:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        strength = 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    sequence = sorted(counts, key=lambda rank: (counts[rank], rank), reverse=True)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    if wheel and straight:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        sequence = [5, 4, 3, 2, 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    ranked.append((strength, sequence, hand))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `ranked.sort(key=lambda record: (record[0], record[1]), reverse=True)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `for position, (strength, _, hand) in enumerate(ranked, 1):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    print(f"{position}. {hand}: {categories[strength]}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **538 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 522 tokens. The contiguous original span L1–L57 costs 755 tokens; the complete original source costs 755 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 530 tokens; removes `from collections import Counter` from the dependency chain described above.
- Without L3: 532 tokens; removes `hands = [` from the dependency chain described above.
- Without L5: 520 tokens; removes `"4D AH 3C 5S 2H",` from the dependency chain described above.
- Without L8: 519 tokens; removes `"3H 6C 4S 2D 5C",` from the dependency chain described above.
- Without L12: 536 tokens; removes `]` from the dependency chain described above.
- Without L13: 532 tokens; removes `categories = [` from the dependency chain described above.
- Without L14: 530 tokens; removes `"high card",` from the dependency chain described above.
- Without L15: 530 tokens; removes `"one pair",` from the dependency chain described above.
- Without L16: 530 tokens; removes `"two pair",` from the dependency chain described above.
- Without L17: 526 tokens; removes `"three of a kind",` from the dependency chain described above.
- Without L18: 532 tokens; removes `"straight",` from the dependency chain described above.
- Without L23: 536 tokens; removes `]` from the dependency chain described above.
- Without L24: 532 tokens; removes `ranked = []` from the dependency chain described above.
- Without L25: 529 tokens; removes `for hand in hands:` from the dependency chain described above.
- Without L26: 527 tokens; removes `cards = hand.split()` from the dependency chain described above.
- Without L27: 498 tokens; removes `counts = Counter("23456789TJQKA".index(card[0]) + 2 for card in cards)` from the dependency chain described above.
- Without L28: 528 tokens; removes `ranks = sorted(counts)` from the dependency chain described above.
- Without L29: 512 tokens; removes `wheel = ranks == [2, 3, 4, 5, 14]` from the dependency chain described above.
- Without L30: 499 tokens; removes `straight = len(ranks) == 5 and (ranks[-1] - ranks[0] == 4 or wheel)` from the dependency chain described above.
- Without L31: 511 tokens; removes `flush = len({card[1] for card in cards}) == 1` from the dependency chain described above.
- Without L32: 519 tokens; removes `pattern = sorted(counts.values(), reverse=True)` from the dependency chain described above.
- Without L33: 528 tokens; removes `if straight and flush:` from the dependency chain described above.
- Without L34: 530 tokens; removes `strength = 8` from the dependency chain described above.
- Without L35: 525 tokens; removes `elif pattern[0] == 4:` from the dependency chain described above.
- Without L36: 530 tokens; removes `strength = 7` from the dependency chain described above.
- Without L37: 524 tokens; removes `elif pattern == [3, 2]:` from the dependency chain described above.
- Without L38: 530 tokens; removes `strength = 6` from the dependency chain described above.
- Without L39: 532 tokens; removes `elif flush:` from the dependency chain described above.
- Without L40: 530 tokens; removes `strength = 5` from the dependency chain described above.
- Without L41: 532 tokens; removes `elif straight:` from the dependency chain described above.
- Without L42: 530 tokens; removes `strength = 4` from the dependency chain described above.
- Without L51: 505 tokens; removes `sequence = sorted(counts, key=lambda rank: (counts[rank], rank), reverse=True)` from the dependency chain described above.
- Without L52: 528 tokens; removes `if wheel and straight:` from the dependency chain described above.
- Without L53: 516 tokens; removes `sequence = [5, 4, 3, 2, 1]` from the dependency chain described above.
- Without L54: 522 tokens; removes `ranked.append((strength, sequence, hand))` from the dependency chain described above.
- Without L55: 508 tokens; removes `ranked.sort(key=lambda record: (record[0], record[1]), reverse=True)` from the dependency chain described above.
- Without L56: 512 tokens; removes `for position, (strength, _, hand) in enumerate(ranked, 1):` from the dependency chain described above.
- Without L57: 516 tokens; removes `print(f"{position}. {hand}: {categories[strength]}")` from the dependency chain described above.
