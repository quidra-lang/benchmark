# Task B: 75_query_string_parse / R

Decode both key and value before comparing against the values already stored for that decoded key. Change the append so an exactly equal decoded value is ignored, while a new decoded value is appended to that key's ordered list. In the second query, page already holds ["2","3"]; appending &page=%32 decodes to another "2" and must leave ["2","3"]. Keep empty decoded values as legitimate values, also deduplicated; continue sorting keys only at output.

decode precedes the params[[key]] append. Guard that append by exact membership in the key's existing character vector, retaining the current later sort(names(params)).

Evidence is from `main.R`, L1,L3,L5,L8,L9,L10,L11,L12,L13,L14,L15,L16,L18,L19,L20.

- L1: `decode_component <- function(source) utils::URLdecode(gsub("+", " ", source, fixed = TRUE))`
- L3: `queries <- c(`
- L5: `"q=c%2B%2B+tutorial&page=2&sort=desc&page=3",`
- L8: `)`
- L9: `for (number in seq_along(queries)) {`
- L10: `parameters <- list()`
- L11: `for (item in strsplit(queries[number], "&", fixed = TRUE)[[1]]) {`
- L12: `position <- regexpr("=", item, fixed = TRUE)[1]`
- L13: `key <- decode_component(if (position < 0) item else substr(item, 1, position - 1))`
- L14: `value <- if (position < 0) "" else decode_component(substring(item, position + 1))`
- L15: `parameters[[key]] <- c(parameters[[key]], value)`
- L16: `}`
- L18: `for (key in sort(names(parameters), method = "radix")) {`
- L19: `quoted <- paste0('"', parameters[[key]], '"')`
- L20: `cat("  ", key, ": ", paste(quoted, collapse = ", "), "\n", sep = "")`

Minimization: Decoder behavior, pair splitting, decoded grouping, accumulation and sorted-key rendering are required. Original-message fallback or unrelated query cases cannot establish deduplication after normalization. The selected complete original lines, in source order, cost 353 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 451, and the complete source costs 456. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
