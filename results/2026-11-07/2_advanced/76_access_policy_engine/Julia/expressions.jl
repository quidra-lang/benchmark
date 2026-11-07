struct PolicyExpression
    operation::String
    arguments::Vector{Any}
end
ast(op,args...) = PolicyExpression(op,Any[args...])
mutable struct ExpressionParser
    tokens::Vector{String}
    position::Int
end
function expression_tokens(text)
    tokens = String[]
    i = 1
    while i<=length(text)
        if text[i]==' '
            i += 1
            continue
        end
        first = i
        if text[i]=='"'
            i += 1
            while text[i]!='"'
                i += 1
            end
            i += 1
        elseif '0'<=text[i]<='9'
            while i<=length(text) && '0'<=text[i]<='9'
                i += 1
            end
        elseif isletter(text[i])
            while i<=length(text) && (isletter(text[i]) || isdigit(text[i]) || text[i] in "_.")
                i += 1
            end
        elseif i<length(text) && text[i:i+1] in ("==","!=","<=",">=")
            i += 2
        else
            i += 1
        end
        push!(tokens,text[first:i-1])
    end
    tokens
end
peek_token(p) = p.position<=length(p.tokens) ? p.tokens[p.position] : ""
function take_token!(p)
    token = p.tokens[p.position]
    p.position += 1
    token
end
function joined_expression!(p,next_level,operators)
    result = next_level(p)
    while peek_token(p) in operators
        op = take_token!(p)
        result = ast(op,result,next_level(p))
    end
    result
end
disjunction!(p) = joined_expression!(p,conjunction!,["or"])
conjunction!(p) = joined_expression!(p,negation!,["and"])
function negation!(p)
    if peek_token(p)=="not"
        take_token!(p)
        return ast("not",negation!(p))
    end
    comparison!(p)
end
function comparison!(p)
    result = expression_sum!(p)
    if peek_token(p) in ("==","!=","<","<=",">",">=","in")
        op = take_token!(p)
        result = ast(op,result,expression_sum!(p))
    end
    result
end
expression_sum!(p) = joined_expression!(p,expression_product!,["+","-"])
expression_product!(p) = joined_expression!(p,unary!,["*"])
function unary!(p)
    if peek_token(p)=="-"
        take_token!(p)
        return ast("-",unary!(p))
    end
    primary!(p)
end
function primary!(p)
    token = take_token!(p)
    if all(isdigit,token)
        return ast("literal",parse(Int,token))
    elseif startswith(token,"\"")
        return ast("literal",token[2:end-1])
    elseif token in ("true","false")
        return ast("literal",token=="true")
    elseif token=="it"
        return ast("it")
    elseif occursin('.',token)
        return ast("attribute",token)
    elseif token=="("
        result = disjunction!(p)
        take_token!(p)
        return result
    elseif token=="["
        values = String[]
        while peek_token(p)!="]"
            value = take_token!(p)
            push!(values,value[2:end-1])
            peek_token(p)!="]" && take_token!(p)
        end
        take_token!(p)
        return ast("literal",values)
    end
    take_token!(p)
    args = PolicyExpression[]
    while peek_token(p)!=")"
        push!(args,disjunction!(p))
        peek_token(p)!=")" && take_token!(p)
    end
    take_token!(p)
    ast(token,args...)
end
parse_expression(text) = disjunction!(ExpressionParser(expression_tokens(text),1))
