mutable struct WordTrie
    children::Vector{Dict{Char,Int}}
    terminal::BitVector
    words::Int
end
WordTrie() = WordTrie([Dict{Char,Int}()],falses(1),0)
tile_index(letter) = letter=='?' ? 27 : Int(letter)-Int('A')+1
function rack_counts(rack)
    counts = zeros(Int,27)
    for letter in rack
        counts[tile_index(letter)] += 1
    end
    counts
end
function add_word!(trie,word)
    node = 1
    for letter in word
        if !haskey(trie.children[node],letter)
            push!(trie.children,Dict{Char,Int}())
            push!(trie.terminal,false)
            trie.children[node][letter] = length(trie.children)
        end
        node = trie.children[node][letter]
    end
    trie.terminal[node] && return false
    trie.terminal[node] = true
    trie.words += 1
    true
end
function prefix_node(trie,word)
    node = 1
    for letter in word
        node = get(trie.children[node],letter,0)
        node==0 && break
    end
    node
end
function has_word(trie,word)
    node = prefix_node(trie,word)
    node!=0 && trie.terminal[node]
end
function anagrams(trie,rack)
    counts,result = rack_counts(rack),String[]
    function visit(node,word)
        trie.terminal[node] && push!(result,word)
        for letter in sort!(collect(keys(trie.children[node])))
            tile = counts[tile_index(letter)]>0 ? tile_index(letter) : 27
            if counts[tile]>0
                counts[tile] -= 1
                visit(trie.children[node][letter],word*letter)
                counts[tile] += 1
            end
        end
    end
    visit(1,"")
    result
end
