# Task B: 63_word_search / J

For candidate TIGER from logical row 0,column 0 facing E, the word binding is TIGER, starting coordinates are 0,0 and direction offsets are dr=0,dc=1. At offset k the comparison uses row+dr*k,column+dc*k and word[k], after checking board bounds. These are the routine's actual local bindings; row/column arguments and loop-offset variables do not name unrelated global search state.

The dyadic search verb receives word=x and board=y, initializes r,c, and unpacks direction offsets from steps for its local direction loop.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17.

- L1: `search =: 4 : 0`
- L2: `word =. x`
- L3: `board =. y`
- L4: `steps =. 8 2$0 1 1 1 1 0 1 _1 0 _1 _1 _1 _1 0 _1 1`
- L5: `names =. ;:'E SE S SW W NW N NE'`
- L6: `for_r. i.10 do.`
- L7: `for_c. i.10 do.`
- L8: `for_d. i.8 do.`
- L9: `'dr dc' =. d{steps`
- L10: `matched =. 1`
- L11: `for_k. i.#word do.`
- L12: `row =. r+k*dr`
- L13: `column =. c+k*dc`
- L14: `if. (row<0)+.(row>:10)+.(column<0)+.column>:10 do.`
- L15: `matched =. 0 break.`
- L16: `end.`
- L17: `if. ((<row,column){board)~:k{word do. matched =. 0 break. end.`

Minimization: The function/argument bindings, E offset representation and candidate coordinate/comparison block suffice. Full board data and the whole search traversal are outside this local name-resolution question. The selected complete original lines, in source order, cost 271 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 271, and the complete source costs 451. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
