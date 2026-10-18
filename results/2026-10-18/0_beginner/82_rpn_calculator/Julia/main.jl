function evaluate(expression)
    stack = Int[]
    for token in split(expression)
        if token in ["+","-","*","/"]
            length(stack) < 2 && return "error: stack underflow"
            b = pop!(stack)
            a = pop!(stack)
            token == "/" && b == 0 && return "error: division by zero"
            if token == "+"
                value = a+b
            elseif token == "-"
                value = a-b
            elseif token == "*"
                value = a*b
            else
                value = div(a,b)
            end
            push!(stack,value)
        else
            push!(stack,parse(Int,token))
        end
    end
    return length(stack) == 1 ? string(stack[1]) : "error: leftover operands"
end
for expression in ["3 4 + 2 *","-17 5 / 4 -3 * -","1 2 + * 3","15 7 1 1 + - / 3 * 2 1 1 + + -","4 2 5 * + 1 3 2 * - 5 + /","2 3 4 + 5","46341 46339 * -2 /"]
    println(expression," => ",evaluate(expression))
end
