ShoppingCartItem splits to shopping, cart, item and yields shopping_cart_item, shoppingCartItem, ShoppingCartItem, shopping-cart. Empty leading pieces from the initial capital are discarded. Every identifier constructs fresh normalized words/results, so previous output cannot leak in; camel preserves the first lowercase word and capitalizes only later ones.

The replace/split/where/map chain constructs a fresh lowercase list. cap is the local capitalization helper; words.first and skip(1) divide camel roles and joins form the other conventions.

Fresh word construction, empty-part rejection and the four join/capitalization expressions establish all forms. Retaining prior identifier text or a whole library splitter implementation would not add evidence.
