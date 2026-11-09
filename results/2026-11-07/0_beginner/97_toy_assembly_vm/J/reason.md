# Task B: 97_toy_assembly_vm / J

Initialize registers/program counter, parse each of the seventeen instruction strings, resolve operands as register values or integer literals, execute the selected update and advance/jump the counter. Move executed increment behind an opcode-membership decision containing only SET,ADD,SUB,MUL,MOD,JNZ, before their execution; count both taken and non-taken JNZ. Factorial contributes 3 SET +8×(MUL,ADD,SUB,JNZ)=35. Euclid contributes 2 SET +3×(SET,MOD,SET,SET,JNZ)=17. Revised executed=52. PRINT still emits 1,2,6,24,120,720,5040,40320,21, and HALT still terminates; excluding them changes only counting.

The valueof helper handles register/literal lookup, and JNZ explicitly adjusts pc then continue. before the ordinary increment. Keep that control flow when conditioning the counter.

Evidence is from `main.ijs`, L1,L2,L3,L5,L6,L7,L8,L9,L10,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41.

- L1: `split =: 4 : 0`
- L2: `<;._1 x,y`
- L3: `)`
- L5: `valueof =: 3 : 0`
- L6: `index =. 'ABCD'i.{.y`
- L7: `if. (1=#y)*.({.y)e.'ABCD' do. index{registers`
- L8: `else. 0".y`
- L9: `end.`
- L10: `)`
- L12: `program =. 'SET A 1';'SET B 1';'SET D 8';'MUL A B';'PRINT A';'ADD B 1';'SUB D 1';'JNZ D -4';'SET A 1071';'SET B 462';'SET C A';'MOD C B';'SET A B';'SET B C';'JNZ B -4';'PRINT A';'HALT'`
- L13: `registers =: 4$0`
- L14: `pc =. executed =. 0`
- L15: `while. (pc>:0)*.pc<#program do.`
- L16: `fields =. ' ' split >pc{program`
- L17: `operation =. >{.fields`
- L18: `executed =. >:executed`
- L19: `if. operation-:'HALT' do. break. end.`
- L20: `if. operation-:'PRINT' do. smoutput ":valueof >1{fields`
- L21: `elseif. operation-:'JNZ' do.`
- L22: `offset =. 0".>2{fields`
- L23: `if. 0~:valueof >1{fields do. pc =. pc+offset`
- L24: `else. pc =. >:pc`
- L25: `end.`
- L26: `continue.`
- L27: `else.`
- L28: `index =. 'ABCD'i.{.>1{fields`
- L29: `value =. valueof >2{fields`
- L30: `old =. index{registers`
- L31: `if. operation-:'SET' do. result =. value`
- L32: `elseif. operation-:'ADD' do. result =. old+value`
- L33: `elseif. operation-:'SUB' do. result =. old-value`
- L34: `elseif. operation-:'MUL' do. result =. old*value`
- L35: `else. result =. value|old`
- L36: `end.`
- L37: `registers =: result index}registers`
- L38: `end.`
- L39: `pc =. >:pc`
- L40: `end.`
- L41: `smoutput 'executed: ',":executed`

Minimization: The instruction data, resolver, complete dispatch/control flow, counter position and print/summary output are needed for the exact revised count. No unrelated program examples are included. The selected complete original lines, in source order, cost 568 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 579, and the complete source costs 586. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
