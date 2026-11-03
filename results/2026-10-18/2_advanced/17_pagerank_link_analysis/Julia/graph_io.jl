struct Page
    id::Int
    host::String
    title::String
    words::Vector{String}
end

struct Query
    number::Int
    words::Vector{String}
    seeds::Vector{Int}
end

function read_input(directory)
    pages = Page[]
    for line in readlines(joinpath(directory, "pages.csv"))[2:end]
        id, host, title = split(line, ',')
        push!(pages, Page(parse(Int, id), host, title, split(title, ' ')))
    end
    records = [(number + 1, parse.(Int, split(line, ','))...) for (number, line) in enumerate(readlines(joinpath(directory, "links.csv"))[2:end])]
    queries = Query[]
    for (number, line) in enumerate(readlines(joinpath(directory, "queries.txt")))
        words, seeds = split(line, " | ")
        push!(queries, Query(number, split(words, ' '), parse.(Int, split(seeds, ' '))))
    end
    entries = Dict{String,Vector{String}}()
    for line in readlines(joinpath(directory, "params.txt"))
        words = split(line, ' ')
        entries[words[1]] = words[2:end]
    end
    integer(key) = parse(Int, entries[key][1])
    real(key) = parse(Float64, entries[key][1])
    settings = (; damping=real("DAMPING"), iterations=integer("PAGERANK_ITERATIONS"), tolerance=real("TOLERANCE"),
        sweep=parse.(Float64, entries["DAMPING_SWEEP"]), trusted=parse.(Int, entries["TRUSTED"]), spam_top=integer("SPAM_TOP"),
        spam_threshold=real("SPAM_THRESHOLD"), hits_iterations=integer("HITS_ITERATIONS"), top_k=integer("TOP_K"),
        root_limit=integer("ROOT_LIMIT"), neighbor_limit=integer("NEIGHBOR_LIMIT"))
    sort!(pages; by=page -> page.id)
    (; pages, records, queries, settings)
end
