module ScriptLoader

const GLOBALS = ("INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON")
const TEXTS = ("INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT")
const RULES = ("DECOMP", "MEMORY")
const ITEMS = ("REASM", "GOTO", "NEWKEY", "RESTATE")
const DIRECTIVES = (GLOBALS..., "KEY", RULES..., ITEMS...)

isword(text) = !isempty(text) && first(text) != '\'' && last(text) != '\'' && all(c -> 'a' <= c <= 'z' || '0' <= c <= '9' || c == '\'', text)
isnumber(text) = occursin(r"^[0-9]{1,2}$", text)
isreference(text) = ncodeunits(text) == 3 && text[1] == '(' && '0' <= text[2] <= '9' && text[3] == ')'
iselement(text) = text in ("*", "#") || (startswith(text, "@") ? isword(text[2:end]) : isword(text))

struct Diagnostic
    line::Int
    code::String
    message::String
end

struct Substitution
    source::String
    replacement::Vector{String}
    line::Int
end

struct Group
    name::String
    members::Set{String}
    line::Int
end

struct Item
    kind::String
    text::String
    arguments::Vector{String}
    line::Int
    id::Int
end

struct Rule
    kind::String
    pattern::Vector{String}
    line::Int
    id::Int
    items::Vector{Int}
end

struct Keyword
    word::String
    rank::Int
    line::Int
    id::Int
    memories::Vector{Int}
    decomps::Vector{Int}
end

mutable struct Script
    lines::Vector{String}
    texts::Dict{String,Vector{String}}
    quit::Set{String}
    stop::Set{String}
    memsize::Int
    persist::Set{String}
    pres::Vector{Substitution}
    posts::Vector{Substitution}
    pre::Dict{String,Vector{String}}
    post::Dict{String,Vector{String}}
    groups::Vector{Group}
    groupwords::Dict{String,Set{String}}
    keywords::Vector{Keyword}
    keywordmap::Dict{String,Int}
    rules::Vector{Rule}
    items::Vector{Item}
    diagnostics::Vector{Diagnostic}
end

function wellformed(name, args)
    count = length(args)
    name in (TEXTS..., "REASM") && return count >= 1
    name in ("QUIT", "STOP") && return count >= 1 && all(isword, args)
    name == "MEMSIZE" && return count == 1 && isnumber(args[1]) && 1 <= parse(Int, args[1]) <= 20
    name == "PERSIST" && return count == 1 && args[1] in ("cycles", "memory")
    name in ("PRE", "SYNON") && return count >= 2 && all(isword, args)
    name == "POST" && return count >= 2 && isword(args[1])
    name == "KEY" && return count == 2 && isword(args[1]) && isnumber(args[2])
    name in RULES && return count >= 1 && all(iselement, args)
    name == "GOTO" && return count == 1 && isword(args[1])
    name == "NEWKEY" && return count == 0
    return count >= 2 && isword(args[1]) && all(arg -> isword(arg) || isreference(arg), args[2:end])
end

function load(path)
    lines = readlines(path)
    script = Script(lines, Dict(name => String[] for name in TEXTS), Set{String}(), Set{String}(), 3,
        Set{String}(), Substitution[], Substitution[], Dict{String,Vector{String}}(), Dict{String,Vector{String}}(),
        Group[], Dict{String,Set{String}}(), Keyword[], Dict{String,Int}(), Rule[], Item[], Diagnostic[])
    definitions = Dict{String,Int}()
    keyword, rule, ignoring = 0, 0, false
    for (number, line) in enumerate(lines)
        (isempty(line) || startswith(line, "#")) && continue
        pieces = String.(split(line, ' '))
        name, args = first(pieces), pieces[2:end]
        text = join(args, " ")
        if name in (GLOBALS..., "KEY")
            keyword, rule, ignoring = 0, 0, false
        elseif name in (RULES..., ITEMS...)
            ignoring && continue
            name in RULES && (rule = 0)
        end
        code, message = "", ""
        definition = name == "MEMSIZE" ? name : name in ("KEY", "SYNON", "PRE", "POST", "PERSIST") && !isempty(args) ? "$name $(args[1])" : ""
        if name ∉ DIRECTIVES
            code, message = "SYNTAX", "unknown directive $name"
        elseif !wellformed(name, args)
            code, message = "SYNTAX", "bad arguments for $name"
        elseif name in RULES && keyword == 0
            code, message = "ORPHAN", "$name without KEY"
        elseif name == "REASM" && rule == 0
            code, message = "ORPHAN", "REASM without DECOMP or MEMORY"
        elseif name in ("GOTO", "NEWKEY", "RESTATE") && (rule == 0 || script.rules[rule].kind == "MEMORY")
            code, message = "ORPHAN", "$name without DECOMP"
        elseif !isempty(definition) && haskey(definitions, definition)
            code, message = "DUPLICATE", "$definition first defined at line $(definitions[definition])"
            name == "KEY" && (ignoring = true)
        end
        if !isempty(code)
            push!(script.diagnostics, Diagnostic(number, code, message))
            continue
        end
        !isempty(definition) && (definitions[definition] = number)
        if name in TEXTS
            push!(script.texts[name], text)
        elseif name == "QUIT"
            union!(script.quit, args)
        elseif name == "STOP"
            union!(script.stop, args)
        elseif name == "MEMSIZE"
            script.memsize = parse(Int, args[1])
        elseif name == "PERSIST"
            push!(script.persist, args[1])
        elseif name in ("PRE", "POST")
            replacement = args[2:end]
            entry = Substitution(args[1], replacement, number)
            push!(name == "PRE" ? script.pres : script.posts, entry)
            (name == "PRE" ? script.pre : script.post)[args[1]] = replacement
        elseif name == "SYNON"
            members = Set(args)
            push!(script.groups, Group(args[1], members, number))
            script.groupwords[args[1]] = members
        elseif name == "KEY"
            keyword = length(script.keywords) + 1
            push!(script.keywords, Keyword(args[1], parse(Int, args[2]), number, keyword, Int[], Int[]))
            script.keywordmap[args[1]] = keyword
        elseif name in RULES
            rule = length(script.rules) + 1
            push!(script.rules, Rule(name, args, number, rule, Int[]))
            push!(name == "MEMORY" ? script.keywords[keyword].memories : script.keywords[keyword].decomps, rule)
        else
            item = length(script.items) + 1
            push!(script.items, Item(name, text, args, number, item))
            push!(script.rules[rule].items, item)
        end
    end
    return script
end

end
