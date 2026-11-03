function main()
    terms = [1, 1]
    while length(terms) < 30
        push!(terms, terms[end-1] + terms[end])
    end
    println(join(terms, " "))
    println("sum: ", sum(terms))
end

main()
