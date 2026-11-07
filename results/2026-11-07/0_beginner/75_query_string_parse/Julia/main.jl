decode_component(source) = replace(
    source,
    r"\+|%[0-9A-Fa-f]{2}" =>
        part -> part == "+" ? " " : string(Char(parse(Int, part[2:3]; base = 16))),
)

function main()
    queries = [
        "name=Alice+Smith&age=30&city=New%20York",
        "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
        "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips",
    ]
    for (number, query) in enumerate(queries)
        parameters = Dict{String,Vector{String}}()
        for item in split(query, '&')
            parts = split(item, '='; limit = 2)
            key = decode_component(parts[1])
            value = length(parts) == 2 ? decode_component(parts[2]) : ""
            push!(get!(parameters, key, String[]), value)
        end
        println("query ", number, ":")
        for key in sort(collect(keys(parameters)))
            quoted = [string('"', value, '"') for value in parameters[key]]
            println("  ", key, ": ", join(quoted, ", "))
        end
    end
end

main()
