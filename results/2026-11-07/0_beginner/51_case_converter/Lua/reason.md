ShoppingCartItem splits to shopping, cart, item and yields shopping_cart_item, shoppingCartItem, ShoppingCartItem, shopping-cart. Empty leading pieces from the initial capital are discarded. Every identifier constructs fresh normalized words/results, so previous output cannot leak in; camel preserves the first lowercase word and capitalizes only later ones.

gsub inserts spaces before capitals and %S+ discards empty gaps after lowercasing. Fresh words/capitals tables begin each iteration; capitalize builds the later/title forms and table.concat has explicit separators.

Fresh word construction, empty-part rejection and the four join/capitalization expressions establish all forms. Retaining prior identifier text or a whole library splitter implementation would not add evidence.
