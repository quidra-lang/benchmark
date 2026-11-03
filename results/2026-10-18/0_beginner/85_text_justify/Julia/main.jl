function main()
    paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."
    lines = Vector{String}[]
    current = String[]
    letters = 0
    for word in split(paragraph)
        if !isempty(current) && letters+length(current)+length(word) > 30
            push!(lines, current)
            current = String[]
            letters = 0
        end
        push!(current, word)
        letters += length(word)
    end
    push!(lines, current)
    for (number, words) in enumerate(lines)
        if number == length(lines) || length(words) == 1
            line = rpad(join(words, " "), 30)
        else
            spaces = 30-sum(length, words)
            base, extra = divrem(spaces, length(words)-1)
            output = IOBuffer()
            for i in eachindex(words)
                print(output, words[i])
                i < length(words) && print(output, repeat(" ", base+(i <= extra)))
            end
            line = String(take!(output))
        end
        println('|', line, '|')
    end
end

main()
