# Task B selection: 96_poker_hand_rank / R

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.R`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L25,L27,L29,L30,L31,L32,L34,L35,L36,L37,L38,L39,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52.

- L1: `describe_hand <- function(original) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  cards <- strsplit(original, " ", fixed = TRUE)[[1]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  alphabet <- strsplit("23456789TJQKA", "", fixed = TRUE)[[1]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  ranks <- match(substr(cards, 1, 1), alphabet) + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  frequencies <- tabulate(ranks, nbins = 14)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  distinct <- which(frequencies > 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  wheel <- identical(distinct, c(2L, 3L, 4L, 5L, 14L))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  straight <- length(distinct) == 5 && (max(distinct) - min(distinct) == 4 || wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  flush <- length(unique(substr(cards, 2, 2))) == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  counts <- sort(frequencies[distinct], decreasing = TRUE)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  if (straight && flush) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    strength <- 9` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  } else if (counts[1] == 4) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    strength <- 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  } else if (identical(counts, c(3L, 2L))) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    strength <- 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  } else if (flush) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    strength <- 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  } else if (straight) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    strength <- 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  } else if (counts[1] == 3) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  } else if (identical(counts, c(2L, 2L, 1L))) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  } else if (counts[1] == 2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `  } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `  sequence <- if (wheel && straight) c(5, 4, 3, 2, 1) else distinct[order(-frequencies[distinct], -distinct)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `  categories <- c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    "high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `  )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `  list(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    original = original, strength = strength, sequence = c(sequence, rep(0, 5 - length(sequence))),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    category = categories[strength]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `  )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `originals <- c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `  "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `  "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `hands <- lapply(originals, describe_hand)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `strengths <- vapply(hands, function(hand) hand$strength, numeric(1))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `ties <- do.call(rbind, lapply(hands, function(hand) hand$sequence))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `ordered <- order(-strengths, -ties[, 1], -ties[, 2], -ties[, 3], -ties[, 4], -ties[, 5])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `for (position in seq_along(ordered)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `  hand <- hands[[ordered[position]]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `  cat(sprintf("%d. %s: %s\n", position, hand$original, hand$category))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **949 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 849 tokens. The contiguous original span L1–L52 costs 996 tokens; the complete original source costs 996 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 936 tokens; removes `describe_hand <- function(original) {` from the dependency chain described above.
- Without L2: 924 tokens; removes `cards <- strsplit(original, " ", fixed = TRUE)[[1]]` from the dependency chain described above.
- Without L3: 915 tokens; removes `alphabet <- strsplit("23456789TJQKA", "", fixed = TRUE)[[1]]` from the dependency chain described above.
- Without L4: 923 tokens; removes `ranks <- match(substr(cards, 1, 1), alphabet) + 1` from the dependency chain described above.
- Without L5: 931 tokens; removes `frequencies <- tabulate(ranks, nbins = 14)` from the dependency chain described above.
- Without L6: 935 tokens; removes `distinct <- which(frequencies > 0)` from the dependency chain described above.
- Without L7: 915 tokens; removes `wheel <- identical(distinct, c(2L, 3L, 4L, 5L, 14L))` from the dependency chain described above.
- Without L8: 911 tokens; removes `straight <- length(distinct) == 5 && (max(distinct) - min(distinct) == 4 || wheel)` from the dependency chain described above.
- Without L9: 923 tokens; removes `flush <- length(unique(substr(cards, 2, 2))) == 1` from the dependency chain described above.
- Without L10: 929 tokens; removes `counts <- sort(frequencies[distinct], decreasing = TRUE)` from the dependency chain described above.
- Without L11: 936 tokens; removes `if (straight && flush) {` from the dependency chain described above.
- Without L12: 942 tokens; removes `strength <- 9` from the dependency chain described above.
- Without L13: 929 tokens; removes `} else if (counts[1] == 4) {` from the dependency chain described above.
- Without L14: 942 tokens; removes `strength <- 8` from the dependency chain described above.
- Without L15: 922 tokens; removes `} else if (identical(counts, c(3L, 2L))) {` from the dependency chain described above.
- Without L16: 942 tokens; removes `strength <- 7` from the dependency chain described above.
- Without L17: 936 tokens; removes `} else if (flush) {` from the dependency chain described above.
- Without L18: 942 tokens; removes `strength <- 6` from the dependency chain described above.
- Without L19: 936 tokens; removes `} else if (straight) {` from the dependency chain described above.
- Without L20: 942 tokens; removes `strength <- 5` from the dependency chain described above.
- Without L21: 929 tokens; removes `} else if (counts[1] == 3) {` from the dependency chain described above.
- Without L23: 918 tokens; removes `} else if (identical(counts, c(2L, 2L, 1L))) {` from the dependency chain described above.
- Without L25: 929 tokens; removes `} else if (counts[1] == 2) {` from the dependency chain described above.
- Without L27: 942 tokens; removes `} else {` from the dependency chain described above.
- Without L29: 946 tokens; removes `}` from the dependency chain described above.
- Without L30: 899 tokens; removes `sequence <- if (wheel && straight) c(5, 4, 3, 2, 1) else distinct[order(-frequencies[distinct], -distinct)]` from the dependency chain described above.
- Without L31: 941 tokens; removes `categories <- c(` from the dependency chain described above.
- Without L32: 899 tokens; removes `"high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",` from the dependency chain described above.
- Without L34: 946 tokens; removes `)` from the dependency chain described above.
- Without L35: 945 tokens; removes `list(` from the dependency chain described above.
- Without L36: 908 tokens; removes `original = original, strength = strength, sequence = c(sequence, rep(0, 5 - length(sequence))),` from the dependency chain described above.
- Without L37: 939 tokens; removes `category = categories[strength]` from the dependency chain described above.
- Without L38: 946 tokens; removes `)` from the dependency chain described above.
- Without L39: 947 tokens; removes `}` from the dependency chain described above.
- Without L41: 942 tokens; removes `originals <- c(` from the dependency chain described above.
- Without L42: 882 tokens; removes `"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L43: 883 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"` from the dependency chain described above.
- Without L44: 947 tokens; removes `)` from the dependency chain described above.
- Without L45: 935 tokens; removes `hands <- lapply(originals, describe_hand)` from the dependency chain described above.
- Without L46: 924 tokens; removes `strengths <- vapply(hands, function(hand) hand$strength, numeric(1))` from the dependency chain described above.
- Without L47: 922 tokens; removes `ties <- do.call(rbind, lapply(hands, function(hand) hand$sequence))` from the dependency chain described above.
- Without L48: 894 tokens; removes `ordered <- order(-strengths, -ties[, 1], -ties[, 2], -ties[, 3], -ties[, 4], -ties[, 5])` from the dependency chain described above.
- Without L49: 932 tokens; removes `for (position in seq_along(ordered)) {` from the dependency chain described above.
- Without L50: 936 tokens; removes `hand <- hands[[ordered[position]]]` from the dependency chain described above.
- Without L51: 916 tokens; removes `cat(sprintf("%d. %s: %s\n", position, hand$original, hand$category))` from the dependency chain described above.
- Without L52: 947 tokens; removes `}` from the dependency chain described above.
