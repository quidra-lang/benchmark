# Task B selection: 96_poker_hand_rank / C#

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `Program.cs`. Selected original locations: L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L27,L28,L29,L30,L32,L33,L34,L35,L36,L37,L38,L41,L42.

- L7: `static (string text, int category, int[] sequence) Evaluate(string text)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `    string[] cards = text.Split(' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    var counts = cards.GroupBy(card => "23456789TJQKA".IndexOf(card[0]) + 2)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        .ToDictionary(group => group.Key, group => group.Count());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    int[] ranks = counts.Keys.Order().ToArray();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    bool wheel = ranks.SequenceEqual(new[] { 2, 3, 4, 5, 14 });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    bool straight = wheel || (ranks.Length == 5 && ranks[^1] - ranks[0] == 4);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    bool flush = cards.All(card => card[1] == cards[0][1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    int largest = counts.Values.Max(), pairs = counts.Values.Count(count => count == 2);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    int category;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    if (straight && flush) category = 8;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    else if (largest == 4) category = 7;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    else if (largest == 3 && pairs == 1) category = 6;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    else if (flush) category = 5;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    else if (straight) category = 4;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    var sequence = counts.Keys.OrderByDescending(rank => counts[rank]).ThenByDescending(rank => rank).ToArray();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    if (wheel && straight) sequence = new[] { 5, 4, 3, 2, 1 };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    return (text, category, sequence);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `string[] input = { "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D" };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `string[] categories = { "high card", "one pair", "two pair", "three of a kind", "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    "flush", "full house", "four of a kind", "straight flush" };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `var hands = input.Select(Evaluate).ToList();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `hands.Sort((a, b) => a.category != b.category ? b.category.CompareTo(a.category) :` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    b.sequence.AsSpan().SequenceCompareTo(a.sequence));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    var hand = hands[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    Console.WriteLine($"{i + 1}. {hand.text}: {categories[hand.category]}");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **832 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 795 tokens. The contiguous original span L7–L42 costs 930 tokens; the complete original source costs 968 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 806 tokens; removes `static (string text, int category, int[] sequence) Evaluate(string text)` from the dependency chain described above.
- Without L8: 830 tokens; removes `{` from the dependency chain described above.
- Without L9: 814 tokens; removes `string[] cards = text.Split(' ');` from the dependency chain described above.
- Without L10: 790 tokens; removes `var counts = cards.GroupBy(card => "23456789TJQKA".IndexOf(card[0]) + 2)` from the dependency chain described above.
- Without L11: 805 tokens; removes `.ToDictionary(group => group.Key, group => group.Count());` from the dependency chain described above.
- Without L12: 810 tokens; removes `int[] ranks = counts.Keys.Order().ToArray();` from the dependency chain described above.
- Without L13: 796 tokens; removes `bool wheel = ranks.SequenceEqual(new[] { 2, 3, 4, 5, 14 });` from the dependency chain described above.
- Without L14: 791 tokens; removes `bool straight = wheel || (ranks.Length == 5 && ranks[^1] - ranks[0] == 4);` from the dependency chain described above.
- Without L15: 800 tokens; removes `bool flush = cards.All(card => card[1] == cards[0][1]);` from the dependency chain described above.
- Without L16: 794 tokens; removes `int largest = counts.Values.Max(), pairs = counts.Values.Count(count => count == 2);` from the dependency chain described above.
- Without L17: 826 tokens; removes `int category;` from the dependency chain described above.
- Without L18: 814 tokens; removes `if (straight && flush) category = 8;` from the dependency chain described above.
- Without L19: 812 tokens; removes `else if (largest == 4) category = 7;` from the dependency chain described above.
- Without L20: 804 tokens; removes `else if (largest == 3 && pairs == 1) category = 6;` from the dependency chain described above.
- Without L21: 816 tokens; removes `else if (flush) category = 5;` from the dependency chain described above.
- Without L22: 816 tokens; removes `else if (straight) category = 4;` from the dependency chain described above.
- Without L27: 790 tokens; removes `var sequence = counts.Keys.OrderByDescending(rank => counts[rank]).ThenByDescending(rank => rank).ToArray();` from the dependency chain described above.
- Without L28: 795 tokens; removes `if (wheel && straight) sequence = new[] { 5, 4, 3, 2, 1 };` from the dependency chain described above.
- Without L29: 818 tokens; removes `return (text, category, sequence);` from the dependency chain described above.
- Without L30: 830 tokens; removes `}` from the dependency chain described above.
- Without L32: 757 tokens; removes `string[] input = { "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L33: 763 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D" };` from the dependency chain described above.
- Without L34: 786 tokens; removes `string[] categories = { "high card", "one pair", "two pair", "three of a kind", "straight",` from the dependency chain described above.
- Without L35: 799 tokens; removes `"flush", "full house", "four of a kind", "straight flush" };` from the dependency chain described above.
- Without L36: 813 tokens; removes `var hands = input.Select(Evaluate).ToList();` from the dependency chain described above.
- Without L37: 793 tokens; removes `hands.Sort((a, b) => a.category != b.category ? b.category.CompareTo(a.category) :` from the dependency chain described above.
- Without L38: 811 tokens; removes `b.sequence.AsSpan().SequenceCompareTo(a.sequence));` from the dependency chain described above.
- Without L41: 819 tokens; removes `var hand = hands[i];` from the dependency chain described above.
- Without L42: 798 tokens; removes `Console.WriteLine($"{i + 1}. {hand.text}: {categories[hand.category]}");` from the dependency chain described above.
