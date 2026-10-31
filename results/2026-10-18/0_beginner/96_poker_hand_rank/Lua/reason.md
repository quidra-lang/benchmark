# Task B selection: 96_poker_hand_rank / Lua

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L45,L46,L47,L48,L49,L50,L51,L52,L55,L56,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71.

- L1: `local categories = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    "high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    "four of a kind", "straight flush",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `local function describe(original)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    local alphabet, frequencies, suits = "23456789TJQKA", {}, {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    for card in original:gmatch("%S+") do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        local rank = alphabet:find(card:sub(1, 1), 1, true) + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        frequencies[rank] = (frequencies[rank] or 0) + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        suits[card:sub(2, 2)] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    local distinct, counts, suit_count = {}, {}, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    for rank = 2, 14 do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        if frequencies[rank] then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            distinct[#distinct + 1] = rank` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            counts[#counts + 1] = frequencies[rank]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `    for _ in pairs(suits) do suit_count = suit_count + 1 end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    local wheel = #distinct == 5 and distinct[1] == 2 and distinct[2] == 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        and distinct[3] == 4 and distinct[4] == 5 and distinct[5] == 14` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    local straight = #distinct == 5 and (distinct[5] - distinct[1] == 4 or wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    local flush = suit_count == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    table.sort(counts, function(a, b) return a > b end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    local strength` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    if straight and flush then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        strength = 9` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    elseif counts[1] == 4 then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        strength = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    elseif counts[1] == 3 and counts[2] == 2 then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        strength = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    elseif flush then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        strength = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    elseif straight then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        strength = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `    table.sort(distinct, function(a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        if frequencies[a] ~= frequencies[b] then return frequencies[a] > frequencies[b] end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        return a > b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    if wheel and straight then distinct = {5, 4, 3, 2, 1} end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    return {original = original, strength = strength, sequence = distinct, category = categories[strength]}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L55: `local originals = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `    "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD", "3H 6C 4S 2D 5C",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L59: `for _, original in ipairs(originals) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    hands[#hands + 1] = describe(original)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L62: `table.sort(hands, function(a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `    if a.strength ~= b.strength then return a.strength > b.strength end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `    for i = 1, #a.sequence do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `        if a.sequence[i] ~= b.sequence[i] then return a.sequence[i] > b.sequence[i] end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L67: `    return false` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `for position, hand in ipairs(hands) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `    io.write(string.format("%d. %s: %s\n", position, hand.original, hand.category))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **1043 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1001 tokens. The contiguous original span L1–L71 costs 1191 tokens; the complete original source costs 1191 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 1035 tokens; removes `local categories = {` from the dependency chain described above.
- Without L2: 993 tokens; removes `"high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` from the dependency chain described above.
- Without L3: 1024 tokens; removes `"four of a kind", "straight flush",` from the dependency chain described above.
- Without L4: 1041 tokens; removes `}` from the dependency chain described above.
- Without L6: 1034 tokens; removes `local function describe(original)` from the dependency chain described above.
- Without L7: 1010 tokens; removes `local alphabet, frequencies, suits = "23456789TJQKA", {}, {}` from the dependency chain described above.
- Without L8: 1023 tokens; removes `for card in original:gmatch("%S+") do` from the dependency chain described above.
- Without L9: 1010 tokens; removes `local rank = alphabet:find(card:sub(1, 1), 1, true) + 1` from the dependency chain described above.
- Without L10: 1019 tokens; removes `frequencies[rank] = (frequencies[rank] or 0) + 1` from the dependency chain described above.
- Without L11: 1024 tokens; removes `suits[card:sub(2, 2)] = true` from the dependency chain described above.
- Without L12: 1040 tokens; removes `end` from the dependency chain described above.
- Without L13: 1018 tokens; removes `local distinct, counts, suit_count = {}, {}, 0` from the dependency chain described above.
- Without L14: 1028 tokens; removes `for rank = 2, 14 do` from the dependency chain described above.
- Without L15: 1032 tokens; removes `if frequencies[rank] then` from the dependency chain described above.
- Without L16: 1026 tokens; removes `distinct[#distinct + 1] = rank` from the dependency chain described above.
- Without L17: 1023 tokens; removes `counts[#counts + 1] = frequencies[rank]` from the dependency chain described above.
- Without L18: 1039 tokens; removes `end` from the dependency chain described above.
- Without L19: 1040 tokens; removes `end` from the dependency chain described above.
- Without L20: 1013 tokens; removes `for _ in pairs(suits) do suit_count = suit_count + 1 end` from the dependency chain described above.
- Without L21: 1007 tokens; removes `local wheel = #distinct == 5 and distinct[1] == 2 and distinct[2] == 3` from the dependency chain described above.
- Without L22: 1007 tokens; removes `and distinct[3] == 4 and distinct[4] == 5 and distinct[5] == 14` from the dependency chain described above.
- Without L23: 1005 tokens; removes `local straight = #distinct == 5 and (distinct[5] - distinct[1] == 4 or wheel)` from the dependency chain described above.
- Without L24: 1028 tokens; removes `local flush = suit_count == 1` from the dependency chain described above.
- Without L25: 1016 tokens; removes `table.sort(counts, function(a, b) return a > b end)` from the dependency chain described above.
- Without L26: 1038 tokens; removes `local strength` from the dependency chain described above.
- Without L27: 1032 tokens; removes `if straight and flush then` from the dependency chain described above.
- Without L28: 1035 tokens; removes `strength = 9` from the dependency chain described above.
- Without L29: 1029 tokens; removes `elseif counts[1] == 4 then` from the dependency chain described above.
- Without L30: 1035 tokens; removes `strength = 8` from the dependency chain described above.
- Without L31: 1018 tokens; removes `elseif counts[1] == 3 and counts[2] == 2 then` from the dependency chain described above.
- Without L32: 1035 tokens; removes `strength = 7` from the dependency chain described above.
- Without L33: 1036 tokens; removes `elseif flush then` from the dependency chain described above.
- Without L34: 1035 tokens; removes `strength = 6` from the dependency chain described above.
- Without L35: 1036 tokens; removes `elseif straight then` from the dependency chain described above.
- Without L36: 1035 tokens; removes `strength = 5` from the dependency chain described above.
- Without L45: 1040 tokens; removes `end` from the dependency chain described above.
- Without L46: 1027 tokens; removes `table.sort(distinct, function(a, b)` from the dependency chain described above.
- Without L47: 1009 tokens; removes `if frequencies[a] ~= frequencies[b] then return frequencies[a] > frequencies[b] end` from the dependency chain described above.
- Without L48: 1033 tokens; removes `return a > b` from the dependency chain described above.
- Without L49: 1039 tokens; removes `end)` from the dependency chain described above.
- Without L50: 1010 tokens; removes `if wheel and straight then distinct = {5, 4, 3, 2, 1} end` from the dependency chain described above.
- Without L51: 1008 tokens; removes `return {original = original, strength = strength, sequence = distinct, category = categories[strength]}` from the dependency chain described above.
- Without L52: 1041 tokens; removes `end` from the dependency chain described above.
- Without L55: 1035 tokens; removes `local originals = {` from the dependency chain described above.
- Without L56: 958 tokens; removes `"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD", "3H 6C 4S 2D 5C",` from the dependency chain described above.
- Without L58: 1041 tokens; removes `}` from the dependency chain described above.
- Without L59: 1027 tokens; removes `for _, original in ipairs(originals) do` from the dependency chain described above.
- Without L60: 1025 tokens; removes `hands[#hands + 1] = describe(original)` from the dependency chain described above.
- Without L61: 1041 tokens; removes `end` from the dependency chain described above.
- Without L62: 1028 tokens; removes `table.sort(hands, function(a, b)` from the dependency chain described above.
- Without L63: 1014 tokens; removes `if a.strength ~= b.strength then return a.strength > b.strength end` from the dependency chain described above.
- Without L64: 1026 tokens; removes `for i = 1, #a.sequence do` from the dependency chain described above.
- Without L65: 1001 tokens; removes `if a.sequence[i] ~= b.sequence[i] then return a.sequence[i] > b.sequence[i] end` from the dependency chain described above.
- Without L66: 1040 tokens; removes `end` from the dependency chain described above.
- Without L67: 1038 tokens; removes `return false` from the dependency chain described above.
- Without L68: 1040 tokens; removes `end)` from the dependency chain described above.
- Without L69: 1027 tokens; removes `for position, hand in ipairs(hands) do` from the dependency chain described above.
- Without L70: 1006 tokens; removes `io.write(string.format("%d. %s: %s\n", position, hand.original, hand.category))` from the dependency chain described above.
- Without L71: 1041 tokens; removes `end` from the dependency chain described above.
