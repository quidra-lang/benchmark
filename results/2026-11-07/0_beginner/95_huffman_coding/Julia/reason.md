# Task B: 95_huffman_coding / Julia

Frequencies are formed from the supplied text, including seven ASCII spaces. The tree repeatedly joins the two least (frequency,smallest-character) subtrees, so changing traversal bit labels does not change tree construction or frequency output order. Replace left 0/right 1 with left 1/right 0 only while assigning code strings. Every code is complemented but keeps its length; ASCII space changes from 110 to 001. Weighted encoded length stays 114 bits and fixed-eight-bit length stays 37×8=296. Code output reads the revised strings while total-bit counting still multiplies each frequency by its unchanged code length.

Tree nodes record left/right identities before visit runs; change only prefix*"0"/prefix*"1" at visit's two recursive calls.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54.

- L2: `text = "she sells sea shells by the sea shore"`
- L3: `frequencies = Dict{Char,Int}()`
- L4: `for symbol in text`
- L5: `frequencies[symbol] = get(frequencies, symbol, 0)+1`
- L6: `end`
- L7: `nodes = NamedTuple[]`
- L8: `for symbol in sort(collect(keys(frequencies)))`
- L9: `push!(`
- L10: `nodes,`
- L11: `(`
- L12: `weight = frequencies[symbol],`
- L13: `smallest = Int(symbol),`
- L14: `symbol = symbol,`
- L15: `left = 0,`
- L16: `right = 0,`
- L17: `),`
- L18: `)`
- L19: `end`
- L20: `trees = collect(eachindex(nodes))`
- L21: `while length(trees) > 1`
- L22: `sort!(trees; by = index -> (nodes[index].weight, nodes[index].smallest))`
- L23: `left = popfirst!(trees)`
- L24: `right = popfirst!(trees)`
- L25: `push!(`
- L26: `nodes,`
- L27: `(`
- L28: `weight = nodes[left].weight+nodes[right].weight,`
- L29: `smallest = min(nodes[left].smallest, nodes[right].smallest),`
- L30: `symbol = nothing,`
- L31: `left = left,`
- L32: `right = right,`
- L33: `),`
- L34: `)`
- L35: `push!(trees, length(nodes))`
- L36: `end`
- L37: `codes = Dict{Char,String}()`
- L38: `function visit(index, prefix)`
- L39: `node = nodes[index]`
- L40: `if node.symbol !== nothing`
- L41: `codes[node.symbol] = prefix`
- L42: `else`
- L43: `visit(node.left, prefix*"0")`
- L44: `visit(node.right, prefix*"1")`
- L45: `end`
- L46: `end`
- L47: `visit(trees[1], "")`
- L48: `bits = 0`
- L49: `for symbol in sort(collect(keys(frequencies)))`
- L50: `println("'", symbol, "' freq=", frequencies[symbol], " code=", codes[symbol])`
- L51: `bits += frequencies[symbol]*length(codes[symbol])`
- L52: `end`
- L53: `println("encoded bits: ", bits)`
- L54: `println("fixed 8-bit: ", length(text)*8)`

Minimization: Input/frequencies, exact tree tie rule/child construction, traversal and both output totals are all needed for this complete change and ASCII-space code. No implementation of the proposed change is made. The selected complete original lines, in source order, cost 634 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 634, and the complete source costs 645. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
