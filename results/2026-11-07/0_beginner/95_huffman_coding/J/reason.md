# Task B: 95_huffman_coding / J

Frequencies are formed from the supplied text, including seven ASCII spaces. The tree repeatedly joins the two least (frequency,smallest-character) subtrees, so changing traversal bit labels does not change tree construction or frequency output order. Replace left 0/right 1 with left 1/right 0 only while assigning code strings. Every code is complemented but keeps its length; ASCII space changes from 110 to 001. Weighted encoded length stays 114 bits and fixed-eight-bit length stays 37×8=296. Code output reads the revised strings while total-bit counting still multiplies each frequency by its unchanged code length.

The custom smallest/pick and assign routines separate priority selection from bit traversal; change only the recursive bit suffixes in assign.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60.

- L1: `smallest =: 3 : 0`
- L2: `best =. {.y`
- L3: `for_node. }.y do.`
- L4: `if. ((node{weights)<best{weights)+.((node{weights)=best{weights)*.(node{minima)<best{minima do.`
- L5: `best =. node`
- L6: `end.`
- L7: `end.`
- L8: `best`
- L9: `)`
- L10: `assign =: 4 : 0`
- L11: `node =. x`
- L12: `prefix =. y`
- L13: `symbol =. node{symbols`
- L14: `if. symbol>:0 do.`
- L15: `codes =: (<prefix) symbol}codes`
- L16: `else.`
- L17: `(node{left) assign prefix,'0'`
- L18: `(node{right) assign prefix,'1'`
- L19: `end.`
- L20: `i.0 0`
- L23: `text =. 'she sells sea shells by the sea shore'`
- L24: `alphabet =. ' abcdefghijklmnopqrstuvwxyz'`
- L25: `frequencies =. +/"1 alphabet =/text`
- L26: `weights =: minima =: left =: right =: symbols =: i.0`
- L27: `active =. i.0`
- L28: `for_i. I.frequencies>0 do.`
- L29: `active =. active,#weights`
- L30: `weights =: weights,i{frequencies`
- L31: `minima =: minima,i`
- L32: `left =: left,_1`
- L33: `right =: right,_1`
- L34: `symbols =: symbols,i`
- L35: `end.`
- L36: `while. (#active)>1 do.`
- L37: `first =. smallest active`
- L38: `active =. active-.first`
- L39: `second =. smallest active`
- L40: `active =. active-.second`
- L41: `node =. #weights`
- L42: `weights =: weights,(first{weights)+second{weights`
- L43: `minima =: minima,(first{minima)<.second{minima`
- L44: `left =: left,first`
- L45: `right =: right,second`
- L46: `symbols =: symbols,_1`
- L47: `active =. active,node`
- L48: `end.`
- L49: `codes =: 27$<''`
- L50: `({.active) assign ''`
- L51: `bits =. 0`
- L52: `quote =. 39{a.`
- L53: `for_i. I.frequencies>0 do.`
- L54: `code =. >i{codes`
- L55: `frequency =. i{frequencies`
- L56: `bits =. bits+frequency*#code`
- L57: `smoutput quote,(i{alphabet),quote,' freq=',(":frequency),' code=',code`
- L58: `end.`
- L59: `smoutput 'encoded bits: ',":bits`
- L60: `smoutput 'fixed 8-bit: ',":8*#text`

Minimization: Input/frequencies, exact tree tie rule/child construction, traversal and both output totals are all needed for this complete change and ASCII-space code. No implementation of the proposed change is made. The selected complete original lines, in source order, cost 628 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 640, and the complete source costs 647. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
