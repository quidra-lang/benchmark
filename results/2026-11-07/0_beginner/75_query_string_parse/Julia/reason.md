# Task B: 75_query_string_parse / Julia

Decode both key and value before comparing against the values already stored for that decoded key. Change the append so an exactly equal decoded value is ignored, while a new decoded value is appended to that key's ordered list. In the second query, page already holds ["2","3"]; appending &page=%32 decodes to another "2" and must leave ["2","3"]. Keep empty decoded values as legitimate values, also deduplicated; continue sorting keys only at output.

get!(params,key,String[]) yields the existing ordered vector after decode; guard push! by exact value membership. Sorted-key iteration and quoted vector rendering remain unchanged.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L8,L10,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L24,L25.

- L1: `decode_component(source) = replace(`
- L2: `source,`
- L3: `r"\+|%[0-9A-Fa-f]{2}" =>`
- L4: `part -> part == "+" ? " " : string(Char(parse(Int, part[2:3]; base = 16))),`
- L5: `)`
- L8: `queries = [`
- L10: `"q=c%2B%2B+tutorial&page=2&sort=desc&page=3",`
- L13: `]`
- L14: `for (number, query) in enumerate(queries)`
- L15: `parameters = Dict{String,Vector{String}}()`
- L16: `for item in split(query, '&')`
- L17: `parts = split(item, '='; limit = 2)`
- L18: `key = decode_component(parts[1])`
- L19: `value = length(parts) == 2 ? decode_component(parts[2]) : ""`
- L20: `push!(get!(parameters, key, String[]), value)`
- L21: `end`
- L23: `for key in sort(collect(keys(parameters)))`
- L24: `quoted = [string('"', value, '"') for value in parameters[key]]`
- L25: `println("  ", key, ": ", join(quoted, ", "))`

Minimization: Decoder behavior, pair splitting, decoded grouping, accumulation and sorted-key rendering are required. Original-message fallback or unrelated query cases cannot establish deduplication after normalization. The selected complete original lines, in source order, cost 364 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 470, and the complete source costs 483. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
