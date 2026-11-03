const BUILTINS = ["__LINE__","__FILE__","__COUNTER__"]
const VARIADIC_NAME = "__VA_ARGS__"
const VARIADIC_ERROR = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro"
struct DefinitionError <: Exception
    message::String
end
mutable struct MacroDefinition
    name::String
    parameters::Union{Nothing,Vector{String}}
    variadic::Bool
    replacement::Vector{PPToken}
    position::Tuple{String,Int}
    main_file::Bool
    expanded::Int
    tested::Int
end
function signature(definition)
    definition.parameters === nothing && return definition.name
    parameters = copy(definition.parameters)
    definition.variadic && (parameters[end] = "...")
    definition.name * "(" * join(parameters,", ") * ")"
end
function identical_definition(first,second)
    first.parameters == second.parameters && first.variadic == second.variadic &&
        [(t.spelling,t.space) for t in first.replacement] == [(t.spelling,t.space) for t in second.replacement]
end
function check_macro_name(tokens,directive)
    isempty(tokens) && return "no macro name given in #$directive directive"
    tokens[1].kind == "identifier" || return "macro names must be identifiers"
    name = tokens[1].spelling
    name == "defined" && return "\"defined\" cannot be used as a macro name"
    if name in BUILTINS
        operation = directive == "define" ? "redefine" : "undefine"
        return "cannot $operation builtin macro \"$name\""
    end
    nothing
end
function parse_definition(tokens,position,main_file)
    error = check_macro_name(tokens,"define")
    error === nothing || throw(DefinitionError(error))
    name = tokens[1].spelling
    name == VARIADIC_NAME && throw(DefinitionError(VARIADIC_ERROR))
    parameters,variadic,index = nothing,false,2
    if length(tokens) > 1 && tokens[2].spelling == "(" && !tokens[2].space
        parameters,index = String[],3
        index > length(tokens) && throw(DefinitionError("missing ')' in macro parameter list"))
        if tokens[index].spelling == ")"
            index += 1
        else
            while true
                index > length(tokens) && throw(DefinitionError("missing ')' in macro parameter list"))
                token = tokens[index]
                if token.spelling == "..."
                    push!(parameters,VARIADIC_NAME)
                    variadic = true
                elseif token.kind == "identifier"
                    token.spelling == VARIADIC_NAME && throw(DefinitionError(VARIADIC_ERROR))
                    token.spelling in parameters && throw(DefinitionError("duplicate macro parameter \"$(token.spelling)\""))
                    push!(parameters,token.spelling)
                else
                    throw(DefinitionError("expected parameter name, found \"$(token.spelling)\""))
                end
                index += 1
                index > length(tokens) && throw(DefinitionError("missing ')' in macro parameter list"))
                following = tokens[index].spelling
                index += 1
                following == ")" && break
                variadic && throw(DefinitionError("expected ')' after \"...\", found \"$following\""))
                following == "," || throw(DefinitionError("expected ',' or ')', found \"$following\""))
            end
        end
    end
    replacement = copy(tokens[index:end])
    if !isempty(replacement)
        replacement[1] = token_with(replacement[1];space=false)
        (replacement[1].spelling == "##" || replacement[end].spelling == "##") && throw(DefinitionError("'##' cannot appear at either end of a macro expansion"))
    end
    for (index,token) in enumerate(replacement)
        token.kind == "identifier" && token.spelling == VARIADIC_NAME && !variadic && throw(DefinitionError(VARIADIC_ERROR))
        if token.spelling == "#" && parameters !== nothing
            if index == length(replacement) || replacement[index+1].kind != "identifier" || !(replacement[index+1].spelling in parameters)
                throw(DefinitionError("'#' is not followed by a macro parameter"))
            end
        end
    end
    MacroDefinition(name,parameters,variadic,replacement,position,main_file,0,0)
end
