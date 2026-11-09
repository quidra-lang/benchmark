# Task B: 95_huffman_coding / R

Frequencies are formed from the supplied text, including seven ASCII spaces. The tree repeatedly joins the two least (frequency,smallest-character) subtrees, so changing traversal bit labels does not change tree construction or frequency output order. Replace left 0/right 1 with left 1/right 0 only while assigning code strings. Every code is complemented but keeps its length; ASCII space changes from 110 to 001. Weighted encoded length stays 114 bits and fixed-eight-bit length stays 37×8=296. Code output reads the revised strings while total-bit counting still multiplies each frequency by its unchanged code length.

The node-list priority loop fixes children first; change only the string suffixes in visit, leaving frequency/length aggregation alone.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L24,L25,L26,L27,L28,L29,L30,L31,L33,L34,L35,L36,L37,L38,L39.

- L1: `text <- "she sells sea shells by the sea shore"`
- L2: `frequencies <- table(strsplit(text, "", fixed = TRUE)[[1]])`
- L3: `symbols <- names(frequencies)[order(vapply(names(frequencies), utf8ToInt, integer(1)))]`
- L4: `trees <- lapply(symbols, function(symbol) {`
- L5: `list(weight = as.numeric(frequencies[symbol]), smallest = utf8ToInt(symbol), symbol = symbol)`
- L6: `})`
- L7: `while (length(trees) > 1) {`
- L8: `ordered <- order(`
- L9: `vapply(trees, function(node) node$weight, numeric(1)),`
- L10: `vapply(trees, function(node) node$smallest, integer(1))`
- L11: `)`
- L12: `trees <- trees[ordered]`
- L13: `left <- trees[[1]]`
- L14: `right <- trees[[2]]`
- L15: `trees <- trees[-c(1, 2)]`
- L16: `node <- list(`
- L17: `weight = left$weight + right$weight, smallest = min(left$smallest, right$smallest), left = left,`
- L18: `right = right`
- L19: `)`
- L20: `trees[[length(trees) + 1]] <- node`
- L21: `}`
- L22: `codes <- character(0)`
- L24: `visit <- function(node, prefix) {`
- L25: `if (!is.null(node$symbol)) {`
- L26: `codes[node$symbol] <<- prefix`
- L27: `} else {`
- L28: `visit(node$left, paste0(prefix, "0"))`
- L29: `visit(node$right, paste0(prefix, "1"))`
- L30: `}`
- L31: `}`
- L33: `invisible(visit(trees[[1]], ""))`
- L34: `bits <- 0`
- L35: `for (symbol in symbols) {`
- L36: `cat(sprintf("'%s' freq=%d code=%s\n", symbol, frequencies[symbol], codes[symbol]))`
- L37: `bits <- bits + frequencies[symbol] * nchar(codes[symbol])`
- L38: `}`
- L39: `cat(sprintf("encoded bits: %d\nfixed 8-bit: %d\n", bits, nchar(text) * 8))`

Minimization: Input/frequencies, exact tree tie rule/child construction, traversal and both output totals are all needed for this complete change and ASCII-space code. No implementation of the proposed change is made. The selected complete original lines, in source order, cost 574 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 576, and the complete source costs 576. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
