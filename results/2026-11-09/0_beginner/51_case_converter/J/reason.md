# Task B: 51_case_converter / J

ShoppingCartItem becomes the three lowercase words shopping,cart,item. Outputs are snake `shopping_cart_item`, camel `shoppingCartItem`, pascal `ShoppingCartItem`, kebab `shopping-cart-item`. Empty leading pieces are discarded before selecting the first camel word. State is reinitialized or freshly constructed per identifier, so no preceding identifier text can leak into these values.

words/current reset inside the per-identifier loop; the uppercase boundary flushes current only when nonempty. cap uppercases just a word's first character; camel leaves the first lowercase word unchanged.

Evidence is from `main.ijs`, L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24.

- L1: `cap =: 3 : 0`
- L2: `(toupper {.y),}.y`
- L3: `)`
- L6: `for_box. identifiers do.`
- L7: `identifier =. >box`
- L8: `words =. 0$<''`
- L9: `current =. ''`
- L10: `for_char. identifier do.`
- L11: `if. char e.'_-' do.`
- L12: `if. #current do. words =. words,<current end.`
- L13: `current =. ''`
- L14: `elseif. char e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.`
- L15: `if. #current do. words =. words,<current end.`
- L16: `current =. tolower char`
- L17: `else. current =. current,char`
- L18: `end.`
- L19: `end.`
- L20: `if. #current do. words =. words,<current end.`
- L21: `snake =. }. ; (<'_') ,&.> words`
- L22: `kebab =. }. ; (<'-') ,&.> words`
- L23: `pascal =. ;cap&.>words`
- L24: `camel =. (>0{words),;cap&.>}.words`

Minimization: The per-identifier boundary, initial/reset state, splitting and four constructions are needed. Other identifier literals and final output formatting do not establish conversion behavior beyond these result values. The selected complete original lines, in source order, cost 268 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 324, and the complete source costs 375. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
