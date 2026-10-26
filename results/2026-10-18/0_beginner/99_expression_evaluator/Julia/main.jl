function evaluate_tokens(tokens, variables, start)
    position = start
    function factor()
        token = tokens[position]
        position += 1
        if token == "-"
            return -factor()
        elseif token == "("
            value = expression()
            position += 1
            return value
        elseif isdigit(first(token))
            return parse(Int, token)
        end
        haskey(variables, token) || error("undefined variable "*token)
        return variables[token]
    end

    function term()
        value = factor()
        while position <= length(tokens) && tokens[position] in ("*", "/")
            operation = tokens[position]
            position += 1
            right = factor()
            operation == "/" && right == 0 && error("division by zero")
            value = operation == "*" ? value*right : div(value, right)
        end
        return value
    end

    function expression()
        value = term()
        while position <= length(tokens) && tokens[position] in ("+", "-")
            operation = tokens[position]
            position += 1
            right = term()
            value = operation == "+" ? value+right : value-right
        end
        return value
    end
    return expression()
end

function main()
    lines = [
        "width = 12",
        "height = width - 5",
        "area = width * height",
        "(area + 6) / 4",
        "shift = -area / 8 + 3",
        "height = 100 / (height - 7) + bonus",
        "volume = area * depth",
        "width = (width+3)*-(2-4)",
        "width * shift - height",
    ]
    variables = Dict{String,Int}()
    for line in lines
        tokens =
            [String(match.match) for match in eachmatch(r"[0-9]+|[a-z]+|[()+*/=-]", line)]
        assignment = length(tokens) >= 2 && tokens[2] == "="
        try
            value = evaluate_tokens(tokens, variables, assignment ? 3 : 1)
            if assignment
                variables[tokens[1]] = value
                println(tokens[1], " = ", value)
            else
                println(value)
            end
        catch exception
            exception isa ErrorException || rethrow()
            println("error: ", exception.msg)
        end
    end
end

main()
