function main()
    text = "she sells sea shells by the sea shore"
    frequencies = Dict{Char,Int}()
    for symbol in text
        frequencies[symbol] = get(frequencies, symbol, 0)+1
    end
    nodes = NamedTuple[]
    for symbol in sort(collect(keys(frequencies)))
        push!(
            nodes,
            (
                weight = frequencies[symbol],
                smallest = Int(symbol),
                symbol = symbol,
                left = 0,
                right = 0,
            ),
        )
    end
    trees = collect(eachindex(nodes))
    while length(trees) > 1
        sort!(trees; by = index -> (nodes[index].weight, nodes[index].smallest))
        left = popfirst!(trees)
        right = popfirst!(trees)
        push!(
            nodes,
            (
                weight = nodes[left].weight+nodes[right].weight,
                smallest = min(nodes[left].smallest, nodes[right].smallest),
                symbol = nothing,
                left = left,
                right = right,
            ),
        )
        push!(trees, length(nodes))
    end
    codes = Dict{Char,String}()
    function visit(index, prefix)
        node = nodes[index]
        if node.symbol !== nothing
            codes[node.symbol] = prefix
        else
            visit(node.left, prefix*"0")
            visit(node.right, prefix*"1")
        end
    end
    visit(trees[1], "")
    bits = 0
    for symbol in sort(collect(keys(frequencies)))
        println("'", symbol, "' freq=", frequencies[symbol], " code=", codes[symbol])
        bits += frequencies[symbol]*length(codes[symbol])
    end
    println("encoded bits: ", bits)
    println("fixed 8-bit: ", length(text)*8)
end

main()
