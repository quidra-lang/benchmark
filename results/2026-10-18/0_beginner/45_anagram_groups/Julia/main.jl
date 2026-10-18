function main()
    groups = Vector{String}[]
    indices = Dict{String,Int}()
    for word in ["listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones"]
        signature = join(sort(collect(word)))
        if !haskey(indices,signature)
            push!(groups,String[])
            indices[signature] = length(groups)
        end
        push!(groups[indices[signature]],word)
    end
    for group in groups
        println(join(group," "))
    end
end
main()
