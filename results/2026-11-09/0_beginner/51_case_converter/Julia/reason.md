# Task B: 51_case_converter / Julia

ShoppingCartItem becomes the three lowercase words shopping,cart,item. Outputs are snake `shopping_cart_item`, camel `shoppingCartItem`, pascal `ShoppingCartItem`, kebab `shopping-cart-item`. Empty leading pieces are discarded before selecting the first camel word. State is reinitialized or freshly constructed per identifier, so no preceding identifier text can leak into these values.

replace inserts spaces before uppercase letters, separator normalization replaces underscore/hyphen, split discards empty space parts, and lowercase establishes words. New capitals and joins are built each iteration.

Evidence is from `main.jl`, L1,L4,L8,L9,L10,L11,L12,L13,L14,L15,L16.

- L1: `for identifier in [`
- L4: `"ShoppingCartItem",`
- L8: `]`
- L9: `separated = replace(identifier, r"([A-Z])" => s" \1")`
- L10: `separated = replace(separated, '_'=>' ', '-'=>' ')`
- L11: `words = split(lowercase(separated))`
- L12: `capitals = [uppercasefirst(word) for word in words]`
- L13: `snake = join(words, "_")`
- L14: `camel = words[1] * join(capitals[2:end])`
- L15: `pascal = join(capitals)`
- L16: `kebab = join(words, "-")`

Minimization: The per-identifier boundary, initial/reset state, splitting and four constructions are needed. Other identifier literals and final output formatting do not establish conversion behavior beyond these result values. The selected complete original lines, in source order, cost 172 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 217, and the complete source costs 252. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
