# Task B: 45_anagram_groups / Julia

Apple has the sorted-letter signature `aelpp`, compared exactly as a whole key. No preceding anagram class has that signature, so it chooses a new group rather than an existing one. This is an absent-signature decision, not a test based on the first character or a partial match.

indices is a Dict from signature to group index. !haskey(indices,signature) creates an empty group and records its new index before push! selects that group.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L17,L18,L19,L20,L21,L22,L23.

- L2: `groups = Vector{String}[]`
- L3: `indices = Dict{String,Int}()`
- L4: `for word in [`
- L5: `"listen",`
- L6: `"stone",`
- L7: `"night",`
- L8: `"silent",`
- L9: `"notes",`
- L10: `"apple",`
- L17: `]`
- L18: `signature = join(sort(collect(word)))`
- L19: `if !haskey(indices, signature)`
- L20: `push!(groups, String[])`
- L21: `indices[signature] = length(groups)`
- L22: `end`
- L23: `push!(groups[indices[signature]], word)`

Minimization: The key representation and actual absent-class/group-selection operation are needed. Prior words are included only where necessary to establish apple is a new signature; output ordering and formatting are outside scope. The selected complete original lines, in source order, cost 156 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 198, and the complete source costs 239. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
