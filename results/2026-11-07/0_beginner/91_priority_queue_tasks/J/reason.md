# Task B: 91_priority_queue_tasks / J

Use (priority,ascending task name) for every heap comparison instead of (priority,insertion sequence), including both sift directions and the final repeated removals. The revised run lines are `run: deploy (priority 1)`, `run: test (priority 2)`, `run: email (priority 3)`, `run: review (priority 2)`, `run: build (priority 1)`, `run: lint (priority 3)`. Final output is `remaining: report docs backup cleanup`. Parse priorities as numbers and retain names as text; the remaining list must be drained under the same comparator, not sorted by the old insertion rule.

Change before to compare task names on equal priorities, exposing names to that helper or storing name in each heap entry. Both push and pop call before, so their ordering stays coordinated.

Evidence is from `main.ijs`, L1,L2,L3,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58.

- L1: `split =: 4 : 0`
- L2: `<;._1 x,y`
- L3: `)`
- L5: `before =: 4 : 0`
- L6: `((x{priorities)<y{priorities)+.((x{priorities)=y{priorities)*.x<y`
- L7: `)`
- L8: `push =: 3 : 0`
- L9: `heap =: heap,y`
- L10: `index =. <:#heap`
- L11: `while. index>0 do.`
- L12: `parent =. <.(index-1)%2`
- L13: `if. -. (index{heap) before parent{heap do. break. end.`
- L14: `pair =. index,parent`
- L15: `heap =: (|.pair{heap) pair}heap`
- L16: `index =. parent`
- L17: `end.`
- L18: `i.0 0`
- L19: `)`
- L20: `pop =: 3 : 0`
- L21: `result =. {.heap`
- L22: `last =. {:heap`
- L23: `heap =: }:heap`
- L24: `if. 0=#heap do. result return. end.`
- L25: `heap =: last (0)}heap`
- L26: `index =. 0`
- L27: `while. ((2*index)+1)<#heap do.`
- L28: `child =. 1+2*index`
- L29: `if. (child+1)<#heap do.`
- L30: `if. ((child+1){heap) before child{heap do. child =. >:child end.`
- L31: `end.`
- L32: `if. -. (child{heap) before index{heap do. break. end.`
- L33: `pair =. index,child`
- L34: `heap =: (|.pair{heap) pair}heap`
- L35: `index =. child`
- L36: `end.`
- L37: `result`
- L38: `)`
- L39: `main =: 3 : 0`
- L40: `operations =. 'add email 3';'add backup 5';'add deploy 1';'run';'add report 3';'add test 2';'add lint 3';'run';'run';'add cleanup 5';'add review 2';'run';'add build 1';'add docs 4';'run';'run'`
- L41: `names =. 0$<''`
- L42: `priorities =: i.0`
- L43: `heap =: i.0`
- L44: `for_box. operations do.`
- L45: `fields =. ' ' split >box`
- L46: `if. 'add'-:>{.fields do.`
- L47: `id =. #names`
- L48: `names =. names,1{fields`
- L49: `priorities =: priorities,0".>2{fields`
- L50: `push id`
- L51: `else.`
- L52: `id =. pop''`
- L53: `smoutput 'run: ',(>id{names),' (priority ',(":id{priorities),')'`
- L54: `end.`
- L55: `end.`
- L56: `remaining =. 0$<''`
- L57: `while. #heap do. remaining =. remaining,(pop''){names end.`
- L58: `smoutput 'remaining: ',}. ; (<' ') ,&.> remaining`

Minimization: The comparator, both custom heap helpers, sixteen operations, parser/entry representation, run output and final drain are needed. This end-to-end dependency covers the substantive program without relying on a generic full-source fallback. The selected complete original lines, in source order, cost 730 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 731, and the complete source costs 738. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
