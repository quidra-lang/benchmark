# Task B selection: 96_poker_hand_rank / Dart

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.dart`. Selected original locations: L1,L2,L3,L4,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L52,L53,L54,L57,L59,L62,L66,L67,L68,L69,L70,L71,L72,L73,L74,L75,L76,L77,L78,L79,L80,L81,L82,L87,L89,L90.

- L1: `class Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  final String original;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  final int category;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  final List<int> sequence;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  Hand(this.original, this.category, this.sequence);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `Hand evaluate(String original) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  final cards = original.split(' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  final counts = List.filled(15, 0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  int rank(String c) => '23456789TJQKA'.indexOf(c) + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  for (final card in cards) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    counts[rank(card[0])]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `  final flush = cards.every((c) => c[1] == cards.first[1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  final ascending = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    for (var r = 2; r <= 14; r++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      if (counts[r] > 0) r,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `  final wheel =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      ascending.length == 5 && [14, 2, 3, 4, 5].every((r) => counts[r] == 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  final straight =` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `      ascending.length == 5 && (wheel || ascending.last - ascending.first == 4);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  final pairs = counts.where((c) => c == 2).length;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  final triple = counts.contains(3);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `  final four = counts.contains(4);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `  final sequence = ascending` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    ..sort((a, b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `      final c = counts[b].compareTo(counts[a]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `      return c != 0 ? c : b.compareTo(a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  if (wheel) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    sequence.clear();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    sequence.addAll([5, 4, 3, 2, 1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `  final category = straight && flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `      ? 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `      : four` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `      ? 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `      : triple && pairs == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `      ? 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `      : flush` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `      ? 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `      : straight` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `      ? 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `      : 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `  return Hand(original, category, sequence);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `  const inputs = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    '4D AH 3C 5S 2H',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `    '3H 6C 4S 2D 5C',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L67: `  final hands = inputs.map(evaluate).toList()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `    ..sort((a, b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `      var c = b.category.compareTo(a.category);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `      if (c != 0) return c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `      for (var i = 0; i < a.sequence.length; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `        c = b.sequence[i].compareTo(a.sequence[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `        if (c != 0) return c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L75: `      return 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L76: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L77: `  const categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L78: `    'high card',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `    'one pair',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `    'two pair',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `    'three of a kind',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `    'straight',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L89: `    final hand = hands[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L90: `    print('${i + 1}. ${hand.original}: ${categories[hand.category]}');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **934 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 842 tokens. The contiguous original span L1–L90 costs 1153 tokens; the complete original source costs 1158 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 928 tokens; removes `class Hand {` from the dependency chain described above.
- Without L2: 926 tokens; removes `final String original;` from the dependency chain described above.
- Without L3: 926 tokens; removes `final int category;` from the dependency chain described above.
- Without L4: 923 tokens; removes `final List<int> sequence;` from the dependency chain described above.
- Without L5: 915 tokens; removes `Hand(this.original, this.category, this.sequence);` from the dependency chain described above.
- Without L6: 932 tokens; removes `}` from the dependency chain described above.
- Without L8: 923 tokens; removes `Hand evaluate(String original) {` from the dependency chain described above.
- Without L9: 917 tokens; removes `final cards = original.split(' ');` from the dependency chain described above.
- Without L10: 915 tokens; removes `final counts = List.filled(15, 0);` from the dependency chain described above.
- Without L11: 899 tokens; removes `int rank(String c) => '23456789TJQKA'.indexOf(c) + 2;` from the dependency chain described above.
- Without L12: 919 tokens; removes `for (final card in cards) {` from the dependency chain described above.
- Without L13: 920 tokens; removes `counts[rank(card[0])]++;` from the dependency chain described above.
- Without L14: 931 tokens; removes `}` from the dependency chain described above.
- Without L15: 901 tokens; removes `final flush = cards.every((c) => c[1] == cards.first[1]);` from the dependency chain described above.
- Without L16: 925 tokens; removes `final ascending = [` from the dependency chain described above.
- Without L17: 909 tokens; removes `for (var r = 2; r <= 14; r++)` from the dependency chain described above.
- Without L18: 916 tokens; removes `if (counts[r] > 0) r,` from the dependency chain described above.
- Without L19: 930 tokens; removes `];` from the dependency chain described above.
- Without L20: 927 tokens; removes `final wheel =` from the dependency chain described above.
- Without L21: 887 tokens; removes `ascending.length == 5 && [14, 2, 3, 4, 5].every((r) => counts[r] == 1);` from the dependency chain described above.
- Without L22: 927 tokens; removes `final straight =` from the dependency chain described above.
- Without L23: 901 tokens; removes `ascending.length == 5 && (wheel || ascending.last - ascending.first == 4);` from the dependency chain described above.
- Without L24: 907 tokens; removes `final pairs = counts.where((c) => c == 2).length;` from the dependency chain described above.
- Without L25: 919 tokens; removes `final triple = counts.contains(3);` from the dependency chain described above.
- Without L26: 919 tokens; removes `final four = counts.contains(4);` from the dependency chain described above.
- Without L27: 925 tokens; removes `final sequence = ascending` from the dependency chain described above.
- Without L28: 921 tokens; removes `..sort((a, b) {` from the dependency chain described above.
- Without L29: 912 tokens; removes `final c = counts[b].compareTo(counts[a]);` from the dependency chain described above.
- Without L30: 909 tokens; removes `return c != 0 ? c : b.compareTo(a);` from the dependency chain described above.
- Without L31: 929 tokens; removes `});` from the dependency chain described above.
- Without L32: 925 tokens; removes `if (wheel) {` from the dependency chain described above.
- Without L33: 926 tokens; removes `sequence.clear();` from the dependency chain described above.
- Without L34: 910 tokens; removes `sequence.addAll([5, 4, 3, 2, 1]);` from the dependency chain described above.
- Without L35: 931 tokens; removes `}` from the dependency chain described above.
- Without L36: 921 tokens; removes `final category = straight && flush` from the dependency chain described above.
- Without L37: 928 tokens; removes `? 8` from the dependency chain described above.
- Without L38: 928 tokens; removes `: four` from the dependency chain described above.
- Without L39: 928 tokens; removes `? 7` from the dependency chain described above.
- Without L40: 920 tokens; removes `: triple && pairs == 1` from the dependency chain described above.
- Without L41: 928 tokens; removes `? 6` from the dependency chain described above.
- Without L42: 928 tokens; removes `: flush` from the dependency chain described above.
- Without L43: 928 tokens; removes `? 5` from the dependency chain described above.
- Without L44: 928 tokens; removes `: straight` from the dependency chain described above.
- Without L45: 928 tokens; removes `? 4` from the dependency chain described above.
- Without L52: 927 tokens; removes `: 0;` from the dependency chain described above.
- Without L53: 919 tokens; removes `return Hand(original, category, sequence);` from the dependency chain described above.
- Without L54: 932 tokens; removes `}` from the dependency chain described above.
- Without L57: 925 tokens; removes `const inputs = [` from the dependency chain described above.
- Without L59: 916 tokens; removes `'4D AH 3C 5S 2H',` from the dependency chain described above.
- Without L62: 915 tokens; removes `'3H 6C 4S 2D 5C',` from the dependency chain described above.
- Without L66: 930 tokens; removes `];` from the dependency chain described above.
- Without L67: 915 tokens; removes `final hands = inputs.map(evaluate).toList()` from the dependency chain described above.
- Without L68: 921 tokens; removes `..sort((a, b) {` from the dependency chain described above.
- Without L69: 913 tokens; removes `var c = b.category.compareTo(a.category);` from the dependency chain described above.
- Without L70: 917 tokens; removes `if (c != 0) return c;` from the dependency chain described above.
- Without L71: 903 tokens; removes `for (var i = 0; i < a.sequence.length; i++) {` from the dependency chain described above.
- Without L72: 910 tokens; removes `c = b.sequence[i].compareTo(a.sequence[i]);` from the dependency chain described above.
- Without L73: 917 tokens; removes `if (c != 0) return c;` from the dependency chain described above.
- Without L74: 930 tokens; removes `}` from the dependency chain described above.
- Without L75: 927 tokens; removes `return 0;` from the dependency chain described above.
- Without L76: 929 tokens; removes `});` from the dependency chain described above.
- Without L77: 925 tokens; removes `const categories = [` from the dependency chain described above.
- Without L78: 926 tokens; removes `'high card',` from the dependency chain described above.
- Without L79: 926 tokens; removes `'one pair',` from the dependency chain described above.
- Without L80: 926 tokens; removes `'two pair',` from the dependency chain described above.
- Without L81: 922 tokens; removes `'three of a kind',` from the dependency chain described above.
- Without L82: 928 tokens; removes `'straight',` from the dependency chain described above.
- Without L87: 930 tokens; removes `];` from the dependency chain described above.
- Without L89: 921 tokens; removes `final hand = hands[i];` from the dependency chain described above.
- Without L90: 901 tokens; removes `print('${i + 1}. ${hand.original}: ${categories[hand.category]}');` from the dependency chain described above.
