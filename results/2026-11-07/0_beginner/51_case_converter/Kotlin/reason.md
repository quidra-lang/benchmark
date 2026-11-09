# Task B selection: 51_case_converter / Kotlin

ShoppingCartItem splits at capitals, drops empty parts and lowercases to shopping,cart,item. Fresh words/capitals/camel values are created per identifier; camel keeps the first word lowercase and joins later capitalized words. Results are shopping_cart_item, shoppingCartItem, ShoppingCartItem and shopping-cart-item. No prior identifier buffer is reused.

The question supplies the identifier; the per-identifier loop, normalization and all four constructions are sufficient. The other input identifiers and import wrappers add no dependency.

Selected complete source lines in `main.kt`: 6, 7, 8, 9, 10, 11. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
