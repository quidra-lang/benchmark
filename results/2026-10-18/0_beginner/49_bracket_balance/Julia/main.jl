strings = ["(a + b) * [c - d]","{x = [1, 2, (3 + 4)]}","f(a[i] + g(b)}","(1 + 2)) * 3","if (a < b) { c = d[0]; }","((a + b] * c","[{(x * y) - z}"]
matching = Dict(')' => '(', ']' => '[', '}' => '{')
for text in strings
    stack = Char[]
    error_index = -1
    for (position,c) in enumerate(text)
        if c in ('(','[','{')
            push!(stack,c)
        elseif haskey(matching,c)
            if isempty(stack) || stack[end] != matching[c]
                error_index = position-1
                break
            end
            pop!(stack)
        end
    end
    if error_index < 0 && !isempty(stack)
        error_index = length(text)
    end
    result = error_index < 0 ? "balanced" : string("error at index ",error_index)
    println(text," -> ",result)
end
