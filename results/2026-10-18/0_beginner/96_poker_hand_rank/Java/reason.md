# Task B selection: 96_poker_hand_rank / Java

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `Main.java`. Selected original locations: L10,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L38,L40,L42,L44,L45,L46,L47,L48,L49,L50,L51,L54,L55,L56,L57,L59,L60,L61,L62,L63,L65,L66.

- L10: `    record Hand(String text, int category, int[] sequence) {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    static Hand evaluate(String text) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        String[] cards = text.split(" ");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        Map<Integer, Integer> counts = new HashMap<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        for (String card : cards) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            counts.merge("23456789TJQKA".indexOf(card.charAt(0)) + 2, 1, Integer::sum);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `        List<Integer> ranks = new ArrayList<>(counts.keySet());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        Collections.sort(ranks);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        boolean wheel = ranks.equals(List.of(2, 3, 4, 5, 14));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        boolean straight = wheel || (ranks.size() == 5 && ranks.getLast() - ranks.getFirst() == 4);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        boolean flush = Arrays.stream(cards).allMatch(card -> card.charAt(1) == cards[0].charAt(1));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        int largest = Collections.max(counts.values());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        long pairs = counts.values().stream().filter(count -> count == 2).count();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        if (straight && flush) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            category = 8;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        } else if (largest == 4) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            category = 7;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        } else if (largest == 3 && pairs == 1) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            category = 6;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        } else if (flush) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            category = 5;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        } else if (straight) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            category = 4;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        } else if (largest == 3) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        } else if (pairs == 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        } else if (pairs == 1) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `        ranks.sort(Comparator.<Integer>comparingInt(counts::get).reversed()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `                .thenComparing(Comparator.reverseOrder()));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        if (wheel && straight) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            ranks = new ArrayList<>(List.of(5, 4, 3, 2, 1));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `        return new Hand(text, category, ranks.stream().mapToInt(Integer::intValue).toArray());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L54: `        String[] input = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `            "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        String[] categories = {"high card", "one pair", "two pair", "three of a kind", "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `            "flush", "full house", "four of a kind", "straight flush"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        for (String text : input) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `            hands.add(evaluate(text));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L62: `        hands.sort(Comparator.comparingInt(Hand::category).reversed()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `                .thenComparing(Hand::sequence, (a, b) -> Arrays.compare(b, a)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `            Hand hand = hands.get(i);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `            System.out.println((i + 1) + ". " + hand.text() + ": " + categories[hand.category()]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1084 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 945 tokens. The contiguous original span L10–L66 costs 1202 tokens; the complete original source costs 1285 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 1060 tokens; removes `record Hand(String text, int category, int[] sequence) {}` from the dependency chain described above.
- Without L12: 1070 tokens; removes `static Hand evaluate(String text) {` from the dependency chain described above.
- Without L13: 1065 tokens; removes `String[] cards = text.split(" ");` from the dependency chain described above.
- Without L14: 1060 tokens; removes `Map<Integer, Integer> counts = new HashMap<>();` from the dependency chain described above.
- Without L15: 1068 tokens; removes `for (String card : cards) {` from the dependency chain described above.
- Without L16: 1039 tokens; removes `counts.merge("23456789TJQKA".indexOf(card.charAt(0)) + 2, 1, Integer::sum);` from the dependency chain described above.
- Without L17: 1080 tokens; removes `}` from the dependency chain described above.
- Without L18: 1057 tokens; removes `List<Integer> ranks = new ArrayList<>(counts.keySet());` from the dependency chain described above.
- Without L19: 1074 tokens; removes `Collections.sort(ranks);` from the dependency chain described above.
- Without L20: 1050 tokens; removes `boolean wheel = ranks.equals(List.of(2, 3, 4, 5, 14));` from the dependency chain described above.
- Without L21: 1037 tokens; removes `boolean straight = wheel || (ranks.size() == 5 && ranks.getLast() - ranks.getFirst() == 4);` from the dependency chain described above.
- Without L22: 1040 tokens; removes `boolean flush = Arrays.stream(cards).allMatch(card -> card.charAt(1) == cards[0].charAt(1));` from the dependency chain described above.
- Without L23: 1064 tokens; removes `int largest = Collections.max(counts.values());` from the dependency chain described above.
- Without L24: 1048 tokens; removes `long pairs = counts.values().stream().filter(count -> count == 2).count();` from the dependency chain described above.
- Without L26: 1070 tokens; removes `if (straight && flush) {` from the dependency chain described above.
- Without L27: 1074 tokens; removes `category = 8;` from the dependency chain described above.
- Without L28: 1066 tokens; removes `} else if (largest == 4) {` from the dependency chain described above.
- Without L29: 1074 tokens; removes `category = 7;` from the dependency chain described above.
- Without L30: 1058 tokens; removes `} else if (largest == 3 && pairs == 1) {` from the dependency chain described above.
- Without L31: 1074 tokens; removes `category = 6;` from the dependency chain described above.
- Without L32: 1070 tokens; removes `} else if (flush) {` from the dependency chain described above.
- Without L33: 1074 tokens; removes `category = 5;` from the dependency chain described above.
- Without L34: 1070 tokens; removes `} else if (straight) {` from the dependency chain described above.
- Without L35: 1074 tokens; removes `category = 4;` from the dependency chain described above.
- Without L36: 1066 tokens; removes `} else if (largest == 3) {` from the dependency chain described above.
- Without L38: 1066 tokens; removes `} else if (pairs == 2) {` from the dependency chain described above.
- Without L40: 1066 tokens; removes `} else if (pairs == 1) {` from the dependency chain described above.
- Without L42: 1076 tokens; removes `} else {` from the dependency chain described above.
- Without L44: 1080 tokens; removes `}` from the dependency chain described above.
- Without L45: 1062 tokens; removes `ranks.sort(Comparator.<Integer>comparingInt(counts::get).reversed()` from the dependency chain described above.
- Without L46: 1066 tokens; removes `.thenComparing(Comparator.reverseOrder()));` from the dependency chain described above.
- Without L47: 1070 tokens; removes `if (wheel && straight) {` from the dependency chain described above.
- Without L48: 1049 tokens; removes `ranks = new ArrayList<>(List.of(5, 4, 3, 2, 1));` from the dependency chain described above.
- Without L49: 1080 tokens; removes `}` from the dependency chain described above.
- Without L50: 1047 tokens; removes `return new Hand(text, category, ranks.stream().mapToInt(Integer::intValue).toArray());` from the dependency chain described above.
- Without L51: 1081 tokens; removes `}` from the dependency chain described above.
- Without L54: 1008 tokens; removes `String[] input = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L55: 1014 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};` from the dependency chain described above.
- Without L56: 1037 tokens; removes `String[] categories = {"high card", "one pair", "two pair", "three of a kind", "straight",` from the dependency chain described above.
- Without L57: 1050 tokens; removes `"flush", "full house", "four of a kind", "straight flush"};` from the dependency chain described above.
- Without L59: 1068 tokens; removes `for (String text : input) {` from the dependency chain described above.
- Without L60: 1070 tokens; removes `hands.add(evaluate(text));` from the dependency chain described above.
- Without L61: 1080 tokens; removes `}` from the dependency chain described above.
- Without L62: 1064 tokens; removes `hands.sort(Comparator.comparingInt(Hand::category).reversed()` from the dependency chain described above.
- Without L63: 1049 tokens; removes `.thenComparing(Hand::sequence, (a, b) -> Arrays.compare(b, a)));` from the dependency chain described above.
- Without L65: 1067 tokens; removes `Hand hand = hands.get(i);` from the dependency chain described above.
- Without L66: 1032 tokens; removes `System.out.println((i + 1) + ". " + hand.text() + ": " + categories[hand.category()]);` from the dependency chain described above.
