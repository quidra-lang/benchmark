# Task B selection: 96_poker_hand_rank / J

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.ijs`. Selected original locations: L1,L2,L3,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L40,L41,L42,L43,L44,L46,L47,L48.

- L1: `split =: 4 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  <;._1 x,y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `score =: 3 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  cards =. ' ' split y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  counts =. 15$0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  suits =. ''` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  for_box. cards do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    card =. >box` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    rank =. 2+'23456789TJQKA'i.{.card` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    counts =. (>:rank{counts) rank}counts` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    suits =. suits,{:card` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `  flush =. *./suits={.suits` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  distinct =. I.counts>0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  wheel =. distinct-:2 3 4 5 14` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  straight =. (5=#distinct)*.((4=({:distinct)-{.distinct)+.wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  largest =. >./counts` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  pairs =. +/counts=2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  category =. 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  if. straight*.flush do. category =. 8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  elseif. largest=4 do. category =. 7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  elseif. (largest=3)*.pairs=1 do. category =. 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  elseif. flush do. category =. 5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `  elseif. straight do. category =. 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `  elseif. largest=3 do. category =. 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `  elseif. pairs=2 do. category =. 2` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  elseif. pairs=1 do. category =. 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `  sequence =. i.0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  if. straight*.wheel do. sequence =. 5 4 3 2 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `  else.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    sequence =. |.distinct` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    sequence =. sequence {~ \:sequence{counts` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `  category,5{.sequence` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `  hands =. '9C 9D 5H QH 2C';'4D AH 3C 5S 2H';'KS 8S 2S JS 6S';'7H 7D KC 7S KD';'3H 6C 4S 2D 5C';'JD TC 4H 8C AS';'QC 6D QS 3S 6H';'9H KH 9S 8H 3D'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `  categories =. 'high card';'one pair';'two pair';'three of a kind';'straight';'flush';'full house';'four of a kind';'straight flush'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `  keys =. 0 6$0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `  for_hand. hands do. keys =. keys,score >hand end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `  order =. \:keys` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    i =. position{order` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    category =. (<i,0){keys` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    smoutput (":>:position),'. ',(>i{hands),': ',>category{categories` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **710 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 697 tokens. The contiguous original span L1–L48 costs 732 tokens; the complete original source costs 742 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 700 tokens; removes `split =: 4 : 0` from the dependency chain described above.
- Without L2: 700 tokens; removes `<;._1 x,y` from the dependency chain described above.
- Without L3: 708 tokens; removes `)` from the dependency chain described above.
- Without L5: 700 tokens; removes `score =: 3 : 0` from the dependency chain described above.
- Without L6: 697 tokens; removes `cards =. ' ' split y` from the dependency chain described above.
- Without L7: 700 tokens; removes `counts =. 15$0` from the dependency chain described above.
- Without L8: 702 tokens; removes `suits =. ''` from the dependency chain described above.
- Without L9: 700 tokens; removes `for_box. cards do.` from the dependency chain described above.
- Without L10: 702 tokens; removes `card =. >box` from the dependency chain described above.
- Without L11: 688 tokens; removes `rank =. 2+'23456789TJQKA'i.{.card` from the dependency chain described above.
- Without L12: 694 tokens; removes `counts =. (>:rank{counts) rank}counts` from the dependency chain described above.
- Without L13: 700 tokens; removes `suits =. suits,{:card` from the dependency chain described above.
- Without L14: 707 tokens; removes `end.` from the dependency chain described above.
- Without L15: 698 tokens; removes `flush =. *./suits={.suits` from the dependency chain described above.
- Without L16: 699 tokens; removes `distinct =. I.counts>0` from the dependency chain described above.
- Without L17: 692 tokens; removes `wheel =. distinct-:2 3 4 5 14` from the dependency chain described above.
- Without L18: 683 tokens; removes `straight =. (5=#distinct)*.((4=({:distinct)-{.distinct)+.wheel)` from the dependency chain described above.
- Without L19: 701 tokens; removes `largest =. >./counts` from the dependency chain described above.
- Without L20: 699 tokens; removes `pairs =. +/counts=2` from the dependency chain described above.
- Without L21: 703 tokens; removes `category =. 0` from the dependency chain described above.
- Without L22: 695 tokens; removes `if. straight*.flush do. category =. 8` from the dependency chain described above.
- Without L23: 695 tokens; removes `elseif. largest=4 do. category =. 7` from the dependency chain described above.
- Without L24: 689 tokens; removes `elseif. (largest=3)*.pairs=1 do. category =. 6` from the dependency chain described above.
- Without L25: 697 tokens; removes `elseif. flush do. category =. 5` from the dependency chain described above.
- Without L26: 697 tokens; removes `elseif. straight do. category =. 4` from the dependency chain described above.
- Without L27: 695 tokens; removes `elseif. largest=3 do. category =. 3` from the dependency chain described above.
- Without L28: 695 tokens; removes `elseif. pairs=2 do. category =. 2` from the dependency chain described above.
- Without L29: 695 tokens; removes `elseif. pairs=1 do. category =. 1` from the dependency chain described above.
- Without L30: 707 tokens; removes `end.` from the dependency chain described above.
- Without L31: 702 tokens; removes `sequence =. i.0` from the dependency chain described above.
- Without L32: 687 tokens; removes `if. straight*.wheel do. sequence =. 5 4 3 2 1` from the dependency chain described above.
- Without L33: 707 tokens; removes `else.` from the dependency chain described above.
- Without L34: 702 tokens; removes `sequence =. |.distinct` from the dependency chain described above.
- Without L35: 695 tokens; removes `sequence =. sequence {~ \:sequence{counts` from the dependency chain described above.
- Without L36: 707 tokens; removes `end.` from the dependency chain described above.
- Without L37: 703 tokens; removes `category,5{.sequence` from the dependency chain described above.
- Without L38: 708 tokens; removes `)` from the dependency chain described above.
- Without L40: 581 tokens; removes `hands =. '9C 9D 5H QH 2C';'4D AH 3C 5S 2H';'KS 8S 2S JS 6S';'7H 7D KC 7S KD';'3H 6C 4S 2D 5C';'JD TC 4H 8C AS';'QC 6D QS 3S 6H';'9H KH 9S 8H 3D'` from the dependency chain described above.
- Without L41: 647 tokens; removes `categories =. 'high card';'one pair';'two pair';'three of a kind';'straight';'flush';'full house';'four of a kind';'straight flush'` from the dependency chain described above.
- Without L42: 699 tokens; removes `keys =. 0 6$0` from the dependency chain described above.
- Without L43: 687 tokens; removes `for_hand. hands do. keys =. keys,score >hand end.` from the dependency chain described above.
- Without L44: 702 tokens; removes `order =. \:keys` from the dependency chain described above.
- Without L46: 701 tokens; removes `i =. position{order` from the dependency chain described above.
- Without L47: 696 tokens; removes `category =. (<i,0){keys` from the dependency chain described above.
- Without L48: 678 tokens; removes `smoutput (":>:position),'. ',(>i{hands),': ',>category{categories` from the dependency chain described above.
