# Task B: 75_query_string_parse / J

Decode both key and value before comparing against the values already stored for that decoded key. Change the append so an exactly equal decoded value is ignored, while a new decoded value is appended to that key's ordered list. In the second query, page already holds ["2","3"]; appending &page=%32 decodes to another "2" and must leave ["2","3"]. Keep empty decoded values as legitimate values, also deduplicated; continue sorting keys only at output.

The custom percent/plus decoder runs on both pieces before keys/values are stored. Add a per-key decoded-value membership check before append, and keep the later key sort/quoting.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L38,L39,L40,L41,L42,L43,L44.

- L1: `split =: 4 : 0`
- L2: `<;._1 x,y`
- L3: `)`
- L4: `decode =: 3 : 0`
- L5: `result =. ''`
- L6: `i =. 0`
- L7: `while. i<#y do.`
- L8: `char =. i{y`
- L9: `if. char='+' do.`
- L10: `result =. result,' '`
- L11: `i =. i+1`
- L12: `elseif. char='%' do.`
- L13: `digits =. '0123456789abcdef' i. tolower (i+1 2){y`
- L14: `value =. (16*0{digits)+1{digits`
- L15: `result =. result,value{a.`
- L16: `i =. i+3`
- L17: `else.`
- L18: `result =. result,char`
- L19: `i =. i+1`
- L20: `end.`
- L21: `end.`
- L22: `result`
- L25: `queries =. 'name=Alice+Smith&age=30&city=New%20York';'q=c%2B%2B+tutorial&page=2&sort=desc&page=3';'msg=50%25+off%21&debug&lang=en&ref=&lang=ja';'redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips'`
- L26: `for_index. i.4 do.`
- L27: `keys =. values =. 0$<''`
- L28: `for_box. '&' split >index{queries do.`
- L29: `item =. >box`
- L30: `separator =. item i.'='`
- L31: `key =. decode separator{.item`
- L32: `value =. ''`
- L33: `if. separator<#item do. value =. decode (separator+1)}.item end.`
- L34: `keys =. keys,<key`
- L35: `values =. values,<value`
- L36: `end.`
- L38: `for_key. /:~ ~.keys do.`
- L39: `quoted =. 0$<''`
- L40: `for_i. I.keys=key do.`
- L41: `quoted =. quoted,<'"',(>i{values),'"'`
- L42: `end.`
- L43: `joined =. 2}. ; (<', ') ,&.> quoted`
- L44: `smoutput '  ',(>key),': ',joined`

Minimization: Decoder behavior, pair splitting, decoded grouping, accumulation and sorted-key rendering are required. Original-message fallback or unrelated query cases cannot establish deduplication after normalization. The selected complete original lines, in source order, cost 572 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 603, and the complete source costs 616. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
