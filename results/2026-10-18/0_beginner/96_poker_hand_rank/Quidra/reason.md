# Task B selection: 96_poker_hand_rank / Quidra

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.qui`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L48,L49,L50,L51,L52,L53,L54,L55,L56,L58,L59,L60,L61,L62,L63,L65,L66,L67,L68,L69,L70,L72,L73,L74,L75,L76,L77,L78,L79,L80,L81,L82.

- L1: `int[] score(string hand)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    string ranks = "23456789TJQKA"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    string[] cards = hand.split(" ")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    int[] counts = array(15, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    bool is_flush = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    for string card = cards[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        match ranks.find(card[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `            nat position` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `                counts[int(position) + 2] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        if card[1] != cards[0][1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            is_flush = false` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    int distinct = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    int low = 15` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    int high = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    int pairs = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    int largest = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    for 2 <= int rank <= 14` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        if counts[rank] > 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            distinct += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            if rank < low` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `                low = rank` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            high = rank` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        if counts[rank] == 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            pairs += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        if counts[rank] > largest` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            largest = counts[rank]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    bool wheel = counts[14] == 1 and counts[2] == 1 and counts[3] == 1 and counts[4] == 1 and counts[5] == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    bool straight = distinct == 5 and (high - low == 4 or wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    int category = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    if straight and is_flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        category = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    elif largest == 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        category = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    elif largest == 3 and pairs == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        category = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    elif is_flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        category = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    elif straight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        category = 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    int[] key = [category]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    if straight and wheel` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        key = key.concat([5, 4, 3, 2, 1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `        for 4 >= int count >= 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `            for 14 >= int rank >= 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `                if counts[rank] == count` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `                    key = key.append(rank)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `    return key` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `bool stronger(int[] first, int[] second)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    nat count = if len(first) < len(second) then len(first) else len(second)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    for nat i < count` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        if first[i] != second[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `            return first[i] > second[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `    return len(first) > len(second)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `string[] hands = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L69: `string[] categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `    "high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L73: `int[][] keys = [for string hand = hands[] then score(hand)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `bool[] used = array(8, fill = false)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L75: `for 1 <= int position <= 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L76: `    int best = -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L77: `    for 0 <= int i < 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `        if not used[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `            if best == -1 or stronger(keys[i], keys[best])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `                best = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `    used[best] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `    print("{position}. {hands[best]}: {categories[keys[best][0]]}{NL}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1126 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1113 tokens. The contiguous original span L1–L82 costs 1209 tokens; the complete original source costs 1209 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 1116 tokens; removes `int[] score(string hand)` from the dependency chain described above.
- Without L2: 1107 tokens; removes `string ranks = "23456789TJQKA"` from the dependency chain described above.
- Without L3: 1109 tokens; removes `string[] cards = hand.split(" ")` from the dependency chain described above.
- Without L4: 1105 tokens; removes `int[] counts = array(15, fill = 0)` from the dependency chain described above.
- Without L5: 1115 tokens; removes `bool is_flush = true` from the dependency chain described above.
- Without L6: 1114 tokens; removes `for string card = cards[]` from the dependency chain described above.
- Without L7: 1112 tokens; removes `match ranks.find(card[0])` from the dependency chain described above.
- Without L8: 1119 tokens; removes `nat position` from the dependency chain described above.
- Without L9: 1106 tokens; removes `counts[int(position) + 2] += 1` from the dependency chain described above.
- Without L12: 1107 tokens; removes `if card[1] != cards[0][1]` from the dependency chain described above.
- Without L13: 1115 tokens; removes `is_flush = false` from the dependency chain described above.
- Without L14: 1117 tokens; removes `int distinct = 0` from the dependency chain described above.
- Without L15: 1116 tokens; removes `int low = 15` from the dependency chain described above.
- Without L16: 1117 tokens; removes `int high = 0` from the dependency chain described above.
- Without L17: 1117 tokens; removes `int pairs = 0` from the dependency chain described above.
- Without L18: 1117 tokens; removes `int largest = 0` from the dependency chain described above.
- Without L19: 1110 tokens; removes `for 2 <= int rank <= 14` from the dependency chain described above.
- Without L20: 1113 tokens; removes `if counts[rank] > 0` from the dependency chain described above.
- Without L21: 1117 tokens; removes `distinct += 1` from the dependency chain described above.
- Without L22: 1115 tokens; removes `if rank < low` from the dependency chain described above.
- Without L23: 1116 tokens; removes `low = rank` from the dependency chain described above.
- Without L24: 1117 tokens; removes `high = rank` from the dependency chain described above.
- Without L25: 1113 tokens; removes `if counts[rank] == 2` from the dependency chain described above.
- Without L26: 1117 tokens; removes `pairs += 1` from the dependency chain described above.
- Without L27: 1113 tokens; removes `if counts[rank] > largest` from the dependency chain described above.
- Without L28: 1114 tokens; removes `largest = counts[rank]` from the dependency chain described above.
- Without L29: 1065 tokens; removes `bool wheel = counts[14] == 1 and counts[2] == 1 and counts[3] == 1 and counts[4] == 1 and counts[5] == 1` from the dependency chain described above.
- Without L30: 1095 tokens; removes `bool straight = distinct == 5 and (high - low == 4 or wheel)` from the dependency chain described above.
- Without L31: 1117 tokens; removes `int category = 0` from the dependency chain described above.
- Without L32: 1115 tokens; removes `if straight and is_flush` from the dependency chain described above.
- Without L33: 1118 tokens; removes `category = 8` from the dependency chain described above.
- Without L34: 1117 tokens; removes `elif largest == 4` from the dependency chain described above.
- Without L35: 1118 tokens; removes `category = 7` from the dependency chain described above.
- Without L36: 1109 tokens; removes `elif largest == 3 and pairs == 1` from the dependency chain described above.
- Without L37: 1118 tokens; removes `category = 6` from the dependency chain described above.
- Without L38: 1119 tokens; removes `elif is_flush` from the dependency chain described above.
- Without L39: 1118 tokens; removes `category = 5` from the dependency chain described above.
- Without L40: 1121 tokens; removes `elif straight` from the dependency chain described above.
- Without L41: 1118 tokens; removes `category = 4` from the dependency chain described above.
- Without L48: 1114 tokens; removes `int[] key = [category]` from the dependency chain described above.
- Without L49: 1117 tokens; removes `if straight and wheel` from the dependency chain described above.
- Without L50: 1099 tokens; removes `key = key.concat([5, 4, 3, 2, 1])` from the dependency chain described above.
- Without L51: 1123 tokens; removes `else` from the dependency chain described above.
- Without L52: 1110 tokens; removes `for 4 >= int count >= 1` from the dependency chain described above.
- Without L53: 1108 tokens; removes `for 14 >= int rank >= 2` from the dependency chain described above.
- Without L54: 1111 tokens; removes `if counts[rank] == count` from the dependency chain described above.
- Without L55: 1110 tokens; removes `key = key.append(rank)` from the dependency chain described above.
- Without L56: 1121 tokens; removes `return key` from the dependency chain described above.
- Without L58: 1110 tokens; removes `bool stronger(int[] first, int[] second)` from the dependency chain described above.
- Without L59: 1091 tokens; removes `nat count = if len(first) < len(second) then len(first) else len(second)` from the dependency chain described above.
- Without L60: 1115 tokens; removes `for nat i < count` from the dependency chain described above.
- Without L61: 1110 tokens; removes `if first[i] != second[i]` from the dependency chain described above.
- Without L62: 1109 tokens; removes `return first[i] > second[i]` from the dependency chain described above.
- Without L63: 1111 tokens; removes `return len(first) > len(second)` from the dependency chain described above.
- Without L65: 1117 tokens; removes `string[] hands = [` from the dependency chain described above.
- Without L66: 1059 tokens; removes `"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L67: 1059 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",` from the dependency chain described above.
- Without L68: 1124 tokens; removes `]` from the dependency chain described above.
- Without L69: 1117 tokens; removes `string[] categories = [` from the dependency chain described above.
- Without L70: 1076 tokens; removes `"high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` from the dependency chain described above.
- Without L72: 1124 tokens; removes `]` from the dependency chain described above.
- Without L73: 1098 tokens; removes `int[][] keys = [for string hand = hands[] then score(hand)]` from the dependency chain described above.
- Without L74: 1107 tokens; removes `bool[] used = array(8, fill = false)` from the dependency chain described above.
- Without L75: 1112 tokens; removes `for 1 <= int position <= 8` from the dependency chain described above.
- Without L76: 1116 tokens; removes `int best = -1` from the dependency chain described above.
- Without L77: 1111 tokens; removes `for 0 <= int i < 8` from the dependency chain described above.
- Without L78: 1115 tokens; removes `if not used[i]` from the dependency chain described above.
- Without L79: 1098 tokens; removes `if best == -1 or stronger(keys[i], keys[best])` from the dependency chain described above.
- Without L80: 1116 tokens; removes `best = i` from the dependency chain described above.
- Without L81: 1116 tokens; removes `used[best] = true` from the dependency chain described above.
- Without L82: 1094 tokens; removes `print("{position}. {hands[best]}: {categories[keys[best][0]]}{NL}")` from the dependency chain described above.
