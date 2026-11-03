# Task B selection: 96_poker_hand_rank / TypeScript

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.ts`. Selected original locations: L1,L2,L3,L4,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41.

- L1: `const hands = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `const categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  "high card", "one pair", "two pair", "three of a kind", "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `const ranked = hands.map(hand => {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  const cards = hand.split(" "), counts = new Map<number, number>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  for (const card of cards) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    const rank = "23456789TJQKA".indexOf(card[0]) + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    counts.set(rank, (counts.get(rank) ?? 0) + 1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `  const ranks = [...counts.keys()].sort((a, b) => a - b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  const wheel = ranks.join(",") === "2,3,4,5,14";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  const straight = ranks.length === 5 && (ranks.at(-1)! - ranks[0] === 4 || wheel);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  const flush = new Set(cards.map(card => card[1])).size === 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  const pattern = [...counts.values()].sort((a, b) => b - a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  let strength;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  if (straight && flush) strength = 8;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  else if (pattern[0] === 4) strength = 7;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  else if (pattern[0] === 3 && pattern[1] === 2) strength = 6;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  else if (flush) strength = 5;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  else if (straight) strength = 4;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  let sequence = [...counts.keys()].sort((a, b) => counts.get(b)! - counts.get(a)! || b - a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `  if (wheel && straight) sequence = [5, 4, 3, 2, 1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  return {strength, sequence, hand};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `ranked.sort((a, b) => {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  if (a.strength !== b.strength) return b.strength - a.strength;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `  for (let i = 0; i < a.sequence.length; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    if (a.sequence[i] !== b.sequence[i]) return b.sequence[i] - a.sequence[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `  return 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `ranked.forEach(({strength, hand}, i) => console.log(`${i + 1}. ${hand}: ${categories[strength]}`));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **891 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 857 tokens. The contiguous original span L1–L41 costs 1011 tokens; the complete original source costs 1011 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 883 tokens; removes `const hands = [` from the dependency chain described above.
- Without L2: 824 tokens; removes `"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L3: 825 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"` from the dependency chain described above.
- Without L4: 888 tokens; removes `];` from the dependency chain described above.
- Without L5: 883 tokens; removes `const categories = [` from the dependency chain described above.
- Without L6: 853 tokens; removes `"high card", "one pair", "two pair", "three of a kind", "straight",` from the dependency chain described above.
- Without L8: 888 tokens; removes `];` from the dependency chain described above.
- Without L9: 875 tokens; removes `const ranked = hands.map(hand => {` from the dependency chain described above.
- Without L10: 857 tokens; removes `const cards = hand.split(" "), counts = new Map<number, number>();` from the dependency chain described above.
- Without L11: 876 tokens; removes `for (const card of cards) {` from the dependency chain described above.
- Without L12: 858 tokens; removes `const rank = "23456789TJQKA".indexOf(card[0]) + 2;` from the dependency chain described above.
- Without L13: 864 tokens; removes `counts.set(rank, (counts.get(rank) ?? 0) + 1);` from the dependency chain described above.
- Without L14: 888 tokens; removes `}` from the dependency chain described above.
- Without L15: 857 tokens; removes `const ranks = [...counts.keys()].sort((a, b) => a - b);` from the dependency chain described above.
- Without L16: 859 tokens; removes `const wheel = ranks.join(",") === "2,3,4,5,14";` from the dependency chain described above.
- Without L17: 847 tokens; removes `const straight = ranks.length === 5 && (ranks.at(-1)! - ranks[0] === 4 || wheel);` from the dependency chain described above.
- Without L18: 858 tokens; removes `const flush = new Set(cards.map(card => card[1])).size === 1;` from the dependency chain described above.
- Without L19: 857 tokens; removes `const pattern = [...counts.values()].sort((a, b) => b - a);` from the dependency chain described above.
- Without L20: 885 tokens; removes `let strength;` from the dependency chain described above.
- Without L21: 873 tokens; removes `if (straight && flush) strength = 8;` from the dependency chain described above.
- Without L22: 868 tokens; removes `else if (pattern[0] === 4) strength = 7;` from the dependency chain described above.
- Without L23: 857 tokens; removes `else if (pattern[0] === 3 && pattern[1] === 2) strength = 6;` from the dependency chain described above.
- Without L24: 875 tokens; removes `else if (flush) strength = 5;` from the dependency chain described above.
- Without L25: 875 tokens; removes `else if (straight) strength = 4;` from the dependency chain described above.
- Without L30: 837 tokens; removes `let sequence = [...counts.keys()].sort((a, b) => counts.get(b)! - counts.get(a)! || b - a);` from the dependency chain described above.
- Without L31: 859 tokens; removes `if (wheel && straight) sequence = [5, 4, 3, 2, 1];` from the dependency chain described above.
- Without L32: 877 tokens; removes `return {strength, sequence, hand};` from the dependency chain described above.
- Without L33: 887 tokens; removes `});` from the dependency chain described above.
- Without L34: 876 tokens; removes `ranked.sort((a, b) => {` from the dependency chain described above.
- Without L35: 863 tokens; removes `if (a.strength !== b.strength) return b.strength - a.strength;` from the dependency chain described above.
- Without L36: 861 tokens; removes `for (let i = 0; i < a.sequence.length; i++) {` from the dependency chain described above.
- Without L37: 851 tokens; removes `if (a.sequence[i] !== b.sequence[i]) return b.sequence[i] - a.sequence[i];` from the dependency chain described above.
- Without L38: 888 tokens; removes `}` from the dependency chain described above.
- Without L39: 885 tokens; removes `return 0;` from the dependency chain described above.
- Without L40: 887 tokens; removes `});` from the dependency chain described above.
- Without L41: 841 tokens; removes `ranked.forEach(({strength, hand}, i) => console.log(`${i + 1}. ${hand}: ${categories[strength]}`));` from the dependency chain described above.
