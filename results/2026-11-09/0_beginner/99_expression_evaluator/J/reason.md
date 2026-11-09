# Task B: 99_expression_evaluator / J

The prior assignments leave height=7. Parsing the RHS begins with term 100 / (...); factor enters parentheses, and the nested expression computes height-7 =0 from the existing table. The division guard reports division by zero before the outer expression can evaluate its +bonus term, so no bonus lookup occurs. Assignment is committed only after successful RHS evaluation; the error exits first, preserving the previous height. The output is `error: division by zero`.

The recursive factor/product/expression verbs share token position but propagate failure before continuing. Main defers names/values append/replacement until its failure check succeeds.

Evidence is from `main.ijs`, L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71,L72,L73,L74,L76,L77,L78,L79,L80,L81,L82,L83,L84,L85,L86,L87,L88,L89,L90,L91,L92,L94,L95,L96,L97,L98,L99,L100,L103,L104.

- L24: `unary =: 3 : 0`
- L25: `token =. >position{tokens`
- L26: `position =: >:position`
- L27: `if. token-:'-' do. (-unary'') return. end.`
- L28: `if. token-:'(' do.`
- L29: `value =. expression''`
- L30: `if. #failure do. 0 return. end.`
- L31: `position =: >:position`
- L32: `value return.`
- L33: `end.`
- L34: `if. ({.token)e.'0123456789' do. (0".token) return. end.`
- L35: `index =. names i.<token`
- L36: `if. index=#names do.`
- L37: `failure =: 'undefined variable ',token`
- L38: `0 return.`
- L39: `end.`
- L40: `index{values`
- L41: `)`
- L42: `product =: 3 : 0`
- L43: `value =. unary''`
- L44: `while. (0=#failure)*.position<#tokens do.`
- L45: `operation =. >position{tokens`
- L46: `if. -. (operation-:'*')+.operation-:'/' do. break. end.`
- L47: `position =: >:position`
- L48: `right =. unary''`
- L49: `if. #failure do. 0 return. end.`
- L50: `if. operation-:'*' do. value =. value*right`
- L51: `else.`
- L52: `if. right=0 do.`
- L53: `failure =: 'division by zero'`
- L54: `0 return.`
- L55: `end.`
- L56: `value =. (*value)*(*right)*<.(|value)%|right`
- L57: `end.`
- L58: `end.`
- L59: `value`
- L60: `)`
- L61: `expression =: 3 : 0`
- L62: `value =. product''`
- L63: `while. (0=#failure)*.position<#tokens do.`
- L64: `operation =. >position{tokens`
- L65: `if. -. (operation-:'+')+.operation-:'-' do. break. end.`
- L66: `position =: >:position`
- L67: `right =. product''`
- L68: `if. #failure do. 0 return. end.`
- L69: `if. operation-:'+' do. value =. value+right`
- L70: `else. value =. value-right`
- L71: `end.`
- L72: `end.`
- L73: `value`
- L74: `)`
- L76: `lines =. 'width = 12';'height = width - 5';'area = width * height';'(area + 6) / 4';'shift = -area / 8 + 3';'height = 100 / (height - 7) + bonus';'volume = area * depth';'width = (width+3)*-(2-4)';'width * shift - height'`
- L77: `names =: 0$<''`
- L78: `values =: i.0`
- L79: `for_line. lines do.`
- L80: `tokens =: tokenize >line`
- L81: `position =: 0`
- L82: `target =. ''`
- L83: `if. (#tokens)>1 do.`
- L84: `if. '='-:>1{tokens do.`
- L85: `target =. >0{tokens`
- L86: `position =: 2`
- L87: `end.`
- L88: `end.`
- L89: `failure =: ''`
- L90: `value =. expression''`
- L91: `if. #failure do. smoutput 'error: ',failure`
- L92: `else.`
- L94: `if. #target do.`
- L95: `index =. names i.<target`
- L96: `if. index=#names do.`
- L97: `names =: names,<target`
- L98: `values =: values,value`
- L99: `else. values =: value index}values`
- L100: `end.`
- L103: `end.`
- L104: `end.`

Minimization: The parser binding/precedence path, zero guard, deferred assignment and error-to-output path are necessary. Prior width/height statements establish the table state; unrelated later input expressions and unused error cases are omitted where complete-line granularity allows. The selected complete original lines, in source order, cost 878 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 928, and the complete source costs 1188. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
