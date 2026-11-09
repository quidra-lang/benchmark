valid_number(token) = length(token) <= 6 && occursin(r"^(?:0|[1-9][0-9]*)$",token)
valid_literal(token) = length(startswith(token,"-") ? token[2:end] : token) <= 6 && occursin(
    r"^(?:0|-?[1-9][0-9]*)$",
    token
)
struct InputError <: Exception
    reason::String
end
function read_dimacs(filename)
    header = nothing
    clauses,partial = Vector{Int}[],Int[]
    for (number,line) in enumerate(readlines(joinpath("input",filename)))
        tokens = split(line)
        (startswith(line,"c") || isempty(tokens)) && continue
        if tokens[1] == "p"
            !isnothing(header) && throw(InputError("duplicate header at line $number"))
            if length(tokens) != 4 || tokens[2] != "cnf" || !valid_number(tokens[3]) || !valid_number(tokens[4])
                throw(InputError("bad header at line $number"))
            end
            header = (parse(Int,tokens[3]),parse(Int,tokens[4]))
            continue
        end
        isnothing(header) && throw(InputError("missing header"))
        for token in tokens
            !valid_literal(token) && throw(InputError("bad token $token at line $number"))
            literal = parse(Int,token)
            abs(literal) > header[1] && throw(InputError("literal out of range $token at line $number"))
            if literal == 0
                push!(clauses,partial)
                partial = Int[]
            else
                push!(partial,literal)
            end
        end
    end
    isnothing(header) && throw(InputError("missing header"))
    !isempty(partial) && throw(InputError("unterminated clause"))
    length(clauses) != header[2] && throw(InputError("clause count mismatch header=$(header[2]) found=$(length(clauses))"))
    header[1],clauses
end
function model_lines(assignment)
    tokens = vcat(
        [string(assignment[variable] ? variable : -variable) for variable in eachindex(assignment)],
        ["0"]
    )
    ["v "*join(tokens[start:min(start+9,length(tokens))],' ') for start in 1:10:length(tokens)]
end
