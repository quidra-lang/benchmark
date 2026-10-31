# Task B selection: 96_poker_hand_rank / C++

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.cpp`. Selected original locations: L7,L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L41,L42,L43,L44,L45,L46,L47,L48,L49,L53,L54,L55,L56,L57,L58,L59,L60,L61,L63.

- L7: `struct Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    std::string text;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    int category;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    std::vector<int> key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `Hand evaluate(const std::string &text) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    std::string ranks = "23456789TJQKA";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    std::array<int, 15> counts{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    bool flush = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    for (int i = 0; i < 5; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        int rank = static_cast<int>(ranks.find(text[i * 3])) + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        ++counts[rank];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        if (text[i * 3 + 1] != text[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            flush = false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    Hand h{text, 0, {}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    int maximum = 0, pairs = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    for (int r = 14; r >= 2; r--)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        if (counts[r]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            h.key.push_back(r);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            maximum = std::max(maximum, counts[r]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            if (counts[r] == 2)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                ++pairs;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    bool wheel = h.key.size() == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    bool straight = h.key.size() == 5 && (h.key[0] - h.key[4] == 4 || wheel);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    h.category = straight && flush ? 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `               : maximum == 4 ? 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `               : maximum == 3 && pairs == 1 ? 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `               : flush ? 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `               : straight ? 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `               : pairs == 1 ? 1 : 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    std::sort(h.key.begin(), h.key.end(), [&counts](int a, int b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        return counts[a] != counts[b] ? counts[a] > counts[b] : a > b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    if (wheel && straight)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        for (int i = 0; i < 5; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            h.key[i] = 5 - i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    return h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L53: `    const std::array<std::string, 8> input = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    for (const std::string &text : input)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        hands.push_back(evaluate(text));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    std::sort(hands.begin(), hands.end(), [](const Hand &a, const Hand &b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        return a.category != b.category ? a.category > b.category : a.key > b.key;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    std::array<std::string, 9> categories = {"high card", "one pair", "two pair", "three of a kind",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        "straight", "flush", "full house", "four of a kind", "straight flush"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `        std::cout << i + 1 << ". " << hands[i].text << ": " << categories[hands[i].category] << '\n';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1115 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1065 tokens. The contiguous original span L7–L63 costs 1202 tokens; the complete original source costs 1240 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 1109 tokens; removes `struct Hand {` from the dependency chain described above.
- Without L8: 1107 tokens; removes `std::string text;` from the dependency chain described above.
- Without L9: 1109 tokens; removes `int category;` from the dependency chain described above.
- Without L10: 1104 tokens; removes `std::vector<int> key;` from the dependency chain described above.
- Without L11: 1112 tokens; removes `};` from the dependency chain described above.
- Without L13: 1099 tokens; removes `Hand evaluate(const std::string &text) {` from the dependency chain described above.
- Without L14: 1093 tokens; removes `std::string ranks = "23456789TJQKA";` from the dependency chain described above.
- Without L15: 1098 tokens; removes `std::array<int, 15> counts{};` from the dependency chain described above.
- Without L16: 1105 tokens; removes `bool flush = true;` from the dependency chain described above.
- Without L17: 1089 tokens; removes `for (int i = 0; i < 5; i++) {` from the dependency chain described above.
- Without L18: 1080 tokens; removes `int rank = static_cast<int>(ranks.find(text[i * 3])) + 2;` from the dependency chain described above.
- Without L19: 1106 tokens; removes `++counts[rank];` from the dependency chain described above.
- Without L20: 1089 tokens; removes `if (text[i * 3 + 1] != text[1])` from the dependency chain described above.
- Without L21: 1105 tokens; removes `flush = false;` from the dependency chain described above.
- Without L22: 1112 tokens; removes `}` from the dependency chain described above.
- Without L23: 1099 tokens; removes `Hand h{text, 0, {}};` from the dependency chain described above.
- Without L24: 1098 tokens; removes `int maximum = 0, pairs = 0;` from the dependency chain described above.
- Without L25: 1090 tokens; removes `for (int r = 14; r >= 2; r--)` from the dependency chain described above.
- Without L26: 1102 tokens; removes `if (counts[r]) {` from the dependency chain described above.
- Without L27: 1100 tokens; removes `h.key.push_back(r);` from the dependency chain described above.
- Without L28: 1094 tokens; removes `maximum = std::max(maximum, counts[r]);` from the dependency chain described above.
- Without L29: 1099 tokens; removes `if (counts[r] == 2)` from the dependency chain described above.
- Without L30: 1107 tokens; removes `++pairs;` from the dependency chain described above.
- Without L31: 1111 tokens; removes `}` from the dependency chain described above.
- Without L32: 1059 tokens; removes `bool wheel = h.key.size() == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];` from the dependency chain described above.
- Without L33: 1067 tokens; removes `bool straight = h.key.size() == 5 && (h.key[0] - h.key[4] == 4 || wheel);` from the dependency chain described above.
- Without L34: 1098 tokens; removes `h.category = straight && flush ? 8` from the dependency chain described above.
- Without L35: 1098 tokens; removes `: maximum == 4 ? 7` from the dependency chain described above.
- Without L36: 1090 tokens; removes `: maximum == 3 && pairs == 1 ? 6` from the dependency chain described above.
- Without L37: 1102 tokens; removes `: flush ? 5` from the dependency chain described above.
- Without L38: 1102 tokens; removes `: straight ? 4` from the dependency chain described above.
- Without L41: 1093 tokens; removes `: pairs == 1 ? 1 : 0;` from the dependency chain described above.
- Without L42: 1075 tokens; removes `std::sort(h.key.begin(), h.key.end(), [&counts](int a, int b) {` from the dependency chain described above.
- Without L43: 1076 tokens; removes `return counts[a] != counts[b] ? counts[a] > counts[b] : a > b;` from the dependency chain described above.
- Without L44: 1110 tokens; removes `});` from the dependency chain described above.
- Without L45: 1104 tokens; removes `if (wheel && straight)` from the dependency chain described above.
- Without L46: 1090 tokens; removes `for (int i = 0; i < 5; i++)` from the dependency chain described above.
- Without L47: 1096 tokens; removes `h.key[i] = 5 - i;` from the dependency chain described above.
- Without L48: 1109 tokens; removes `return h;` from the dependency chain described above.
- Without L49: 1113 tokens; removes `}` from the dependency chain described above.
- Without L53: 1029 tokens; removes `const std::array<std::string, 8> input = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L54: 1046 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` from the dependency chain described above.
- Without L55: 1097 tokens; removes `for (const std::string &text : input)` from the dependency chain described above.
- Without L56: 1100 tokens; removes `hands.push_back(evaluate(text));` from the dependency chain described above.
- Without L57: 1076 tokens; removes `std::sort(hands.begin(), hands.end(), [](const Hand &a, const Hand &b) {` from the dependency chain described above.
- Without L58: 1076 tokens; removes `return a.category != b.category ? a.category > b.category : a.key > b.key;` from the dependency chain described above.
- Without L59: 1110 tokens; removes `});` from the dependency chain described above.
- Without L60: 1065 tokens; removes `std::array<std::string, 9> categories = {"high card", "one pair", "two pair", "three of a kind",` from the dependency chain described above.
- Without L61: 1077 tokens; removes `"straight", "flush", "full house", "four of a kind", "straight flush"};` from the dependency chain described above.
- Without L63: 1060 tokens; removes `std::cout << i + 1 << ". " << hands[i].text << ": " << categories[hands[i].category] << '\n';` from the dependency chain described above.
