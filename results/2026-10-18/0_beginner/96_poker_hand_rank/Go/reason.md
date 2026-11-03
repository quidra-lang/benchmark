# Task B selection: 96_poker_hand_rank / Go

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.go`. Selected original locations: L10,L11,L12,L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71,L72,L76,L77,L78,L79,L80,L81,L82,L83,L84,L85,L86,L87,L88,L89,L90,L91,L92.

- L10: `type Hand struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `	text     string` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `	category int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `	key      []int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `func evaluate(text string) Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `	ranks := "23456789TJQKA"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `	counts := [15]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `	flush := true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	for i := 0; i < 5; i++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		rank := strings.IndexByte(ranks, text[i*3]) + 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `		counts[rank]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `		if text[i*3+1] != text[1] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `			flush = false` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `	key := []int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `	maximum, pairs := 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `	for r := 14; r >= 2; r-- {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `		if counts[r] > 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `			key = append(key, r)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `			maximum = max(maximum, counts[r])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `			if counts[r] == 2 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `				pairs++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `			}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `	wheel := len(key) == 5 && counts[14] > 0 && counts[2] > 0 && counts[3] > 0 && counts[4] > 0 && counts[5] > 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `	straight := len(key) == 5 && (key[0]-key[4] == 4 || wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `	category := 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `	switch {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `	case straight && flush:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `		category = 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `	case maximum == 4:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `		category = 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `	case maximum == 3 && pairs == 1:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `		category = 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `	case flush:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `		category = 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `	case straight:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `		category = 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L59: `	sort.Slice(key, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `		a, b := key[i], key[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `		if counts[a] != counts[b] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `			return counts[a] > counts[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L64: `		return a > b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `	if wheel && straight {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `		for i := range key {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `			key[i] = 5 - i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L70: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L71: `	return Hand{text, category, key}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L76: `	input := []string{"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L77: `		"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `	for _, text := range input {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `		hands = append(hands, evaluate(text))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L81: `	sort.Slice(hands, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `		a, b := hands[i], hands[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L83: `		if a.category != b.category {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L84: `			return a.category > b.category` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L85: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L86: `		return slices.Compare(a.key, b.key) > 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L88: `	categories := []string{"high card", "one pair", "two pair", "three of a kind", "straight", "flush",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L89: `		"full house", "four of a kind", "straight flush"}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L90: `	for i, h := range hands {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L91: `		fmt.Printf("%d. %s: %s\n", i+1, h.text, categories[h.category])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L92: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **1088 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 986 tokens. The contiguous original span L10–L92 costs 1162 tokens; the complete original source costs 1196 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 1080 tokens; removes `type Hand struct {` from the dependency chain described above.
- Without L11: 1081 tokens; removes `text     string` from the dependency chain described above.
- Without L12: 1083 tokens; removes `category int` from the dependency chain described above.
- Without L13: 1080 tokens; removes `key      []int` from the dependency chain described above.
- Without L14: 1086 tokens; removes `}` from the dependency chain described above.
- Without L16: 1075 tokens; removes `func evaluate(text string) Hand {` from the dependency chain described above.
- Without L17: 1071 tokens; removes `ranks := "23456789TJQKA"` from the dependency chain described above.
- Without L18: 1075 tokens; removes `counts := [15]int{}` from the dependency chain described above.
- Without L19: 1081 tokens; removes `flush := true` from the dependency chain described above.
- Without L20: 1066 tokens; removes `for i := 0; i < 5; i++ {` from the dependency chain described above.
- Without L21: 1062 tokens; removes `rank := strings.IndexByte(ranks, text[i*3]) + 2` from the dependency chain described above.
- Without L22: 1080 tokens; removes `counts[rank]++` from the dependency chain described above.
- Without L23: 1066 tokens; removes `if text[i*3+1] != text[1] {` from the dependency chain described above.
- Without L24: 1079 tokens; removes `flush = false` from the dependency chain described above.
- Without L25: 1084 tokens; removes `}` from the dependency chain described above.
- Without L26: 1085 tokens; removes `}` from the dependency chain described above.
- Without L27: 1078 tokens; removes `key := []int{}` from the dependency chain described above.
- Without L28: 1075 tokens; removes `maximum, pairs := 0, 0` from the dependency chain described above.
- Without L29: 1065 tokens; removes `for r := 14; r >= 2; r-- {` from the dependency chain described above.
- Without L30: 1073 tokens; removes `if counts[r] > 0 {` from the dependency chain described above.
- Without L31: 1073 tokens; removes `key = append(key, r)` from the dependency chain described above.
- Without L32: 1070 tokens; removes `maximum = max(maximum, counts[r])` from the dependency chain described above.
- Without L33: 1072 tokens; removes `if counts[r] == 2 {` from the dependency chain described above.
- Without L34: 1081 tokens; removes `pairs++` from the dependency chain described above.
- Without L35: 1083 tokens; removes `}` from the dependency chain described above.
- Without L36: 1084 tokens; removes `}` from the dependency chain described above.
- Without L37: 1085 tokens; removes `}` from the dependency chain described above.
- Without L38: 1018 tokens; removes `wheel := len(key) == 5 && counts[14] > 0 && counts[2] > 0 && counts[3] > 0 && counts[4] > 0 && counts[5] > 0` from the dependency chain described above.
- Without L39: 1052 tokens; removes `straight := len(key) == 5 && (key[0]-key[4] == 4 || wheel)` from the dependency chain described above.
- Without L40: 1081 tokens; removes `category := 0` from the dependency chain described above.
- Without L41: 1083 tokens; removes `switch {` from the dependency chain described above.
- Without L42: 1078 tokens; removes `case straight && flush:` from the dependency chain described above.
- Without L43: 1080 tokens; removes `category = 8` from the dependency chain described above.
- Without L44: 1078 tokens; removes `case maximum == 4:` from the dependency chain described above.
- Without L45: 1080 tokens; removes `category = 7` from the dependency chain described above.
- Without L46: 1070 tokens; removes `case maximum == 3 && pairs == 1:` from the dependency chain described above.
- Without L47: 1080 tokens; removes `category = 6` from the dependency chain described above.
- Without L48: 1082 tokens; removes `case flush:` from the dependency chain described above.
- Without L49: 1080 tokens; removes `category = 5` from the dependency chain described above.
- Without L50: 1082 tokens; removes `case straight:` from the dependency chain described above.
- Without L51: 1080 tokens; removes `category = 4` from the dependency chain described above.
- Without L58: 1085 tokens; removes `}` from the dependency chain described above.
- Without L59: 1066 tokens; removes `sort.Slice(key, func(i, j int) bool {` from the dependency chain described above.
- Without L60: 1068 tokens; removes `a, b := key[i], key[j]` from the dependency chain described above.
- Without L61: 1070 tokens; removes `if counts[a] != counts[b] {` from the dependency chain described above.
- Without L62: 1071 tokens; removes `return counts[a] > counts[b]` from the dependency chain described above.
- Without L63: 1084 tokens; removes `}` from the dependency chain described above.
- Without L64: 1078 tokens; removes `return a > b` from the dependency chain described above.
- Without L65: 1084 tokens; removes `})` from the dependency chain described above.
- Without L66: 1077 tokens; removes `if wheel && straight {` from the dependency chain described above.
- Without L67: 1074 tokens; removes `for i := range key {` from the dependency chain described above.
- Without L68: 1072 tokens; removes `key[i] = 5 - i` from the dependency chain described above.
- Without L69: 1084 tokens; removes `}` from the dependency chain described above.
- Without L70: 1085 tokens; removes `}` from the dependency chain described above.
- Without L71: 1074 tokens; removes `return Hand{text, category, key}` from the dependency chain described above.
- Without L72: 1086 tokens; removes `}` from the dependency chain described above.
- Without L76: 1014 tokens; removes `input := []string{"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L77: 1020 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"}` from the dependency chain described above.
- Without L78: 1072 tokens; removes `for _, text := range input {` from the dependency chain described above.
- Without L79: 1071 tokens; removes `hands = append(hands, evaluate(text))` from the dependency chain described above.
- Without L80: 1085 tokens; removes `}` from the dependency chain described above.
- Without L81: 1066 tokens; removes `sort.Slice(hands, func(i, j int) bool {` from the dependency chain described above.
- Without L82: 1068 tokens; removes `a, b := hands[i], hands[j]` from the dependency chain described above.
- Without L83: 1072 tokens; removes `if a.category != b.category {` from the dependency chain described above.
- Without L84: 1073 tokens; removes `return a.category > b.category` from the dependency chain described above.
- Without L85: 1084 tokens; removes `}` from the dependency chain described above.
- Without L86: 1066 tokens; removes `return slices.Compare(a.key, b.key) > 0` from the dependency chain described above.
- Without L87: 1084 tokens; removes `})` from the dependency chain described above.
- Without L88: 1038 tokens; removes `categories := []string{"high card", "one pair", "two pair", "three of a kind", "straight", "flush",` from the dependency chain described above.
- Without L89: 1061 tokens; removes `"full house", "four of a kind", "straight flush"}` from the dependency chain described above.
- Without L90: 1072 tokens; removes `for i, h := range hands {` from the dependency chain described above.
- Without L91: 1050 tokens; removes `fmt.Printf("%d. %s: %s\n", i+1, h.text, categories[h.category])` from the dependency chain described above.
- Without L92: 1085 tokens; removes `}` from the dependency chain described above.
