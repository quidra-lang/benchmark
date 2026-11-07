For ShoppingCartItem, uppercase boundaries split words into shopping, cart, item after lowercase normalization. Per-identifier count/length reset, nonempty-part guard and four zero-terminated empty result arrays prevent an initial empty part or prior identifier text leaking. Snake and kebab join with _/-; camel uses first lowercase word then capitalized later words; Pascal capitalizes all words. Results are `shopping_cart_item`, `shoppingCartItem`, `ShoppingCartItem`, `shopping-cart-item`.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
