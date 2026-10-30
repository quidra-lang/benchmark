const STARTS = ("if","ifdef","ifndef")
const BRANCHES = ("elif","elifdef","elifndef","else")
function directive_name(tokens)
    length(tokens) >= 2 && tokens[1].spelling == "#" && tokens[2].kind == "identifier" ? tokens[2].spelling : nothing
end
function detect_guard(lines)
    nonempty = [logical.tokens for logical in lines if !isempty(logical.tokens)]
    isempty(nonempty) && return nothing
    first,last = nonempty[1],nonempty[end]
    length(first) == 3 && directive_name(first) == "ifndef" && first[3].kind == "identifier" || return nothing
    length(last) == 2 && directive_name(last) == "endif" || return nothing
    depth = 0
    for (index,tokens) in enumerate(nonempty)
        name = directive_name(tokens)
        name in BRANCHES && depth == 1 && return nothing
        if name in STARTS
            depth += 1
        elseif name == "endif"
            depth -= 1
        end
        depth == 0 && index != length(nonempty) && return nothing
    end
    depth == 0 ? first[3].spelling : nothing
end
mutable struct PPSourceFile
    path::String
    physical_lines::Int
    lines::Vector{LogicalLine}
    guard::Union{Nothing,String}
    once::Bool
    entered::Int
    skipped::Int
    output_lines::Int
    skipped_lines::Int
end
mutable struct IncludeManager
    files::Dict{String,PPSourceFile}
    order::Vector{String}
end
IncludeManager() = IncludeManager(Dict{String,PPSourceFile}(),String[])
function search_header(name,quoted)
    paths = quoted ? [name,"include/" * name] : ["include/" * name]
    for path in paths
        isfile(joinpath("input",path)) && return path
    end
    nothing
end
function load_source!(manager,path)
    if !haskey(manager.files,path)
        contents = read(joinpath("input",path),String)
        lines = lex_source(contents)
        manager.files[path] = PPSourceFile(path,count(==('\n'),contents),lines,detect_guard(lines),false,0,0,0,0)
        push!(manager.order,path)
    end
    manager.files[path]
end
