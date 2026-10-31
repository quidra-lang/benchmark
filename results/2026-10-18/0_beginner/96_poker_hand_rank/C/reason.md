# Task B selection: 96_poker_hand_rank / C

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.c`. Selected original locations: L5,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L50,L51,L52,L53,L54,L55,L56,L58,L61,L62,L63,L64,L66,L67,L68,L69,L70.

- L5: `typedef struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    const char *text;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    int category, key[5], length;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `} Hand;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `Hand evaluate(const char *text) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    const char *ranks = "23456789TJQKA";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    int counts[15] = {0}, flush = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    for (int i = 0; i < 5; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        int rank = (int)(strchr(ranks, text[i * 3]) - ranks) + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        counts[rank]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if (text[i * 3 + 1] != text[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            flush = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    Hand h = {text, 0, {0}, 0};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    int maximum = 0, pairs = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    for (int r = 14; r >= 2; r--)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        if (counts[r]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            h.key[h.length++] = r;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            if (counts[r] > maximum)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `                maximum = counts[r];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            if (counts[r] == 2)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `                pairs++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    int wheel = h.length == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    int straight = h.length == 5 && (h.key[0] - h.key[4] == 4 || wheel);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    h.category = straight && flush ? 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `               : maximum == 4 ? 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `               : maximum == 3 && pairs == 1 ? 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `               : flush ? 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `               : straight ? 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `               : pairs == 1 ? 1 : 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    h.length = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    for (int count = 4; count >= 1; count--)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        for (int rank = 14; rank >= 2; rank--)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `            if (counts[rank] == count)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                h.key[h.length++] = rank;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    if (wheel && straight)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        for (int i = 0; i < 5; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `            h.key[i] = 5 - i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    return h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `int compare(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    const Hand *x = a, *y = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    if (x->category != y->category)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        return y->category - x->category;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    for (int i = 0; i < 5; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        if (x->key[i] != y->key[i])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `            return y->key[i] - x->key[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L61: `    const char *input[] = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `    const char *categories[] = {"high card", "one pair", "two pair", "three of a kind", "straight", "flush",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `        "full house", "four of a kind", "straight flush"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    for (int i = 0; i < 8; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `        hands[i] = evaluate(input[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `    qsort(hands, 8, sizeof(Hand), compare);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `    for (int i = 0; i < 8; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `        printf("%d. %s: %s\n", i + 1, hands[i].text, categories[hands[i].category]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1221 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1149 tokens. The contiguous original span L5–L70 costs 1282 tokens; the complete original source costs 1318 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 1215 tokens; removes `typedef struct {` from the dependency chain described above.
- Without L6: 1212 tokens; removes `const char *text;` from the dependency chain described above.
- Without L7: 1206 tokens; removes `int category, key[5], length;` from the dependency chain described above.
- Without L8: 1216 tokens; removes `} Hand;` from the dependency chain described above.
- Without L10: 1207 tokens; removes `Hand evaluate(const char *text) {` from the dependency chain described above.
- Without L11: 1198 tokens; removes `const char *ranks = "23456789TJQKA";` from the dependency chain described above.
- Without L12: 1198 tokens; removes `int counts[15] = {0}, flush = 1;` from the dependency chain described above.
- Without L13: 1195 tokens; removes `for (int i = 0; i < 5; i++) {` from the dependency chain described above.
- Without L14: 1184 tokens; removes `int rank = (int)(strchr(ranks, text[i * 3]) - ranks) + 2;` from the dependency chain described above.
- Without L15: 1212 tokens; removes `counts[rank]++;` from the dependency chain described above.
- Without L16: 1195 tokens; removes `if (text[i * 3 + 1] != text[1])` from the dependency chain described above.
- Without L17: 1211 tokens; removes `flush = 0;` from the dependency chain described above.
- Without L18: 1218 tokens; removes `}` from the dependency chain described above.
- Without L19: 1198 tokens; removes `Hand h = {text, 0, {0}, 0};` from the dependency chain described above.
- Without L20: 1204 tokens; removes `int maximum = 0, pairs = 0;` from the dependency chain described above.
- Without L21: 1196 tokens; removes `for (int r = 14; r >= 2; r--)` from the dependency chain described above.
- Without L22: 1208 tokens; removes `if (counts[r]) {` from the dependency chain described above.
- Without L23: 1203 tokens; removes `h.key[h.length++] = r;` from the dependency chain described above.
- Without L24: 1205 tokens; removes `if (counts[r] > maximum)` from the dependency chain described above.
- Without L25: 1207 tokens; removes `maximum = counts[r];` from the dependency chain described above.
- Without L26: 1205 tokens; removes `if (counts[r] == 2)` from the dependency chain described above.
- Without L27: 1213 tokens; removes `pairs++;` from the dependency chain described above.
- Without L28: 1217 tokens; removes `}` from the dependency chain described above.
- Without L29: 1169 tokens; removes `int wheel = h.length == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];` from the dependency chain described above.
- Without L30: 1177 tokens; removes `int straight = h.length == 5 && (h.key[0] - h.key[4] == 4 || wheel);` from the dependency chain described above.
- Without L31: 1204 tokens; removes `h.category = straight && flush ? 8` from the dependency chain described above.
- Without L32: 1204 tokens; removes `: maximum == 4 ? 7` from the dependency chain described above.
- Without L33: 1196 tokens; removes `: maximum == 3 && pairs == 1 ? 6` from the dependency chain described above.
- Without L34: 1208 tokens; removes `: flush ? 5` from the dependency chain described above.
- Without L35: 1208 tokens; removes `: straight ? 4` from the dependency chain described above.
- Without L38: 1199 tokens; removes `: pairs == 1 ? 1 : 0;` from the dependency chain described above.
- Without L39: 1211 tokens; removes `h.length = 0;` from the dependency chain described above.
- Without L40: 1197 tokens; removes `for (int count = 4; count >= 1; count--)` from the dependency chain described above.
- Without L41: 1195 tokens; removes `for (int rank = 14; rank >= 2; rank--)` from the dependency chain described above.
- Without L42: 1205 tokens; removes `if (counts[rank] == count)` from the dependency chain described above.
- Without L43: 1202 tokens; removes `h.key[h.length++] = rank;` from the dependency chain described above.
- Without L44: 1210 tokens; removes `if (wheel && straight)` from the dependency chain described above.
- Without L45: 1196 tokens; removes `for (int i = 0; i < 5; i++)` from the dependency chain described above.
- Without L46: 1202 tokens; removes `h.key[i] = 5 - i;` from the dependency chain described above.
- Without L47: 1215 tokens; removes `return h;` from the dependency chain described above.
- Without L48: 1219 tokens; removes `}` from the dependency chain described above.
- Without L50: 1199 tokens; removes `int compare(const void *a, const void *b) {` from the dependency chain described above.
- Without L51: 1200 tokens; removes `const Hand *x = a, *y = b;` from the dependency chain described above.
- Without L52: 1206 tokens; removes `if (x->category != y->category)` from the dependency chain described above.
- Without L53: 1206 tokens; removes `return y->category - x->category;` from the dependency chain described above.
- Without L54: 1197 tokens; removes `for (int i = 0; i < 5; i++)` from the dependency chain described above.
- Without L55: 1199 tokens; removes `if (x->key[i] != y->key[i])` from the dependency chain described above.
- Without L56: 1199 tokens; removes `return y->key[i] - x->key[i];` from the dependency chain described above.
- Without L58: 1219 tokens; removes `}` from the dependency chain described above.
- Without L61: 1143 tokens; removes `const char *input[] = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L62: 1152 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` from the dependency chain described above.
- Without L63: 1167 tokens; removes `const char *categories[] = {"high card", "one pair", "two pair", "three of a kind", "straight", "flush",` from the dependency chain described above.
- Without L64: 1193 tokens; removes `"full house", "four of a kind", "straight flush"};` from the dependency chain described above.
- Without L66: 1197 tokens; removes `for (int i = 0; i < 8; i++)` from the dependency chain described above.
- Without L67: 1203 tokens; removes `hands[i] = evaluate(input[i]);` from the dependency chain described above.
- Without L68: 1202 tokens; removes `qsort(hands, 8, sizeof(Hand), compare);` from the dependency chain described above.
- Without L69: 1197 tokens; removes `for (int i = 0; i < 8; i++)` from the dependency chain described above.
- Without L70: 1178 tokens; removes `printf("%d. %s: %s\n", i + 1, hands[i].text, categories[hands[i].category]);` from the dependency chain described above.
