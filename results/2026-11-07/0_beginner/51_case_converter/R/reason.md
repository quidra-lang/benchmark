# Task B: 51_case_converter / R

ShoppingCartItem becomes the three lowercase words shopping,cart,item. Outputs are snake `shopping_cart_item`, camel `shoppingCartItem`, pascal `ShoppingCartItem`, kebab `shopping-cart-item`. Empty leading pieces are discarded before selecting the first camel word. State is reinitialized or freshly constructed per identifier, so no preceding identifier text can leak into these values.

The routine normalizes separators/case boundaries, filters empty split pieces and builds new capitalized words for this identifier. camel uses the first lowercase word plus later capitalized words.

Evidence is from `main.R`, L1,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17.

- L1: `capitalize <- function(word) paste0(toupper(substr(word, 1, 1)), substr(word, 2, nchar(word)))`
- L7: `for (identifier in identifiers) {`
- L8: `separated <- gsub("([A-Z])", " \\1", identifier)`
- L9: `words <- strsplit(tolower(gsub("[_-]", " ", separated)), " +")[[1]]`
- L10: `words <- words[nzchar(words)]`
- L11: `capitals <- capitalize(words)`
- L12: `camel <- paste0(words[1], paste(capitals[-1], collapse = ""))`
- L13: `cat(sprintf(`
- L14: `"%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n",`
- L15: `identifier, paste(words, collapse = "_"), camel, paste(capitals, collapse = ""),`
- L16: `paste(words, collapse = "-")`
- L17: `))`

Minimization: The per-identifier boundary, initial/reset state, splitting and four constructions are needed. Other identifier literals and final output formatting do not establish conversion behavior beyond these result values. The selected complete original lines, in source order, cost 267 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 325, and the complete source costs 327. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
