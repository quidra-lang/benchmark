# Task B selection: 51_case_converter / Python

## Answer requirements

Explain the identifier-conversion operation for ShoppingCartItem, from splitting and discarding empty parts through lowercase word normalization to the four naming forms. Identify each per-identifier initial state or newly constructed value, particularly the first camel word versus later capitalized words, and show why no empty leading part or preceding identifier's text leaks into a result. Derive the four forms from the source.

## Answer and source evidence

ShoppingCartItem normalizes to words shopping,cart,item. The resulting forms are shopping_cart_item, shoppingCartItem, ShoppingCartItem and shopping-cart-item. A fresh words/result construction occurs inside each identifier iteration, so no preceding identifier text survives. The initial capital split has no empty retained word. Camel keeps the first word lowercase and capitalizes later words; Pascal capitalizes every word.

The re.split lookahead may produce an empty leading part, but `if word` removes it. Each word.lower() supplies common lowercase words.

Selected `main.py` lines: 11, 12, 13, 14, 15, 16. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
