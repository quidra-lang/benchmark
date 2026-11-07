# Task B: 82_rpn_calculator / J

Each evaluation starts with an empty stack and no error. Expression 2 pushes -17 and 5, pops right=5 then left=-17, truncates division toward zero to -3 and pushes it. Next 4 and -3 multiply to -12, then subtraction pops right=-12 and left=-3, producing 9; the sole remaining operand is the result. Underflow is checked before pops, zero divisor before division, and final stack length must be one. Each error exits/halts this evaluation before further stack updates.

The custom whitespace split helper is included because tokens feed the stack block; the division expression truncates a signed quotient toward zero, and failure guards break before subsequent token processing.

Evidence is from `main.ijs`, L1,L2,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32.

- L1: `split =: 4 : 0`
- L2: `<;._1 x,y`
- L6: `expressions =. '3 4 + 2 *';'-17 5 / 4 -3 * -';'1 2 + * 3';'15 7 1 1 + - / 3 * 2 1 1 + + -';'4 2 5 * + 1 3 2 * - 5 + /';'2 3 4 + 5';'46341 46339 * -2 /'`
- L7: `for_box. expressions do.`
- L8: `expression =. >box`
- L9: `stack =. i.0`
- L10: `failure =. ''`
- L11: `for_tokenbox. ' ' split expression do.`
- L12: `token =. >tokenbox`
- L13: `operator =. ((#token)=1)*.({.token)e.'+-*/'`
- L14: `if. operator do.`
- L15: `if. (#stack)<2 do. failure =. 'stack underflow' break. end.`
- L16: `b =. {:stack`
- L17: `a =. _2{stack`
- L18: `stack =. _2}.stack`
- L19: `if. token-:'+' do. value =. a+b`
- L20: `elseif. token-:'-' do. value =. a-b`
- L21: `elseif. token-:'*' do. value =. a*b`
- L22: `elseif. b=0 do. failure =. 'division by zero' break.`
- L23: `else. value =. (*a)*(*b)*<.(|a)%|b`
- L24: `end.`
- L25: `stack =. stack,value`
- L26: `else. stack =. stack,0".token`
- L27: `end.`
- L28: `end.`
- L29: `if. (0=#failure)*.1~:#stack do. failure =. 'leftover operands' end.`
- L30: `if. #failure do. result =. 'error: ',failure`
- L31: `else. result =. , '0' 8!:2 {.stack`
- L32: `end.`

Minimization: The actual second-expression literal and its iteration binding/evaluator call are necessary to derive the -17,5 sequence from source rather than Task A requirements. Other expressions are omitted unless they share that physical source line. The evaluator entry, stack updates and guarded error/result operations establish the requested trace and error boundaries; unrelated program wrappers are excluded. Complete source lines remain verbatim and in order. No Task A program was built or executed.
