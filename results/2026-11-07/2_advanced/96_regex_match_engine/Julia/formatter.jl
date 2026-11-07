function character_display(character)
    code = Int(character)
    33 <= code <= 126 && !(character in ('\\',']','^','-')) && return string(character)
    "\\x" * uppercase(string(code;base=16,pad=2))
end
function set_notation(codes,negated=false)
    ordered = sort(collect(codes))
    pieces,index = String[],1
    while index <= length(ordered)
        last = index
        while last < length(ordered) && ordered[last+1] == ordered[last]+1
            last += 1
        end
        first_display,last_display = character_display(Char(ordered[index])),character_display(Char(ordered[last]))
        run_length = last-index+1
        push!(pieces,run_length == 1 ? first_display : run_length == 2 ? first_display * last_display : first_display * "-" * last_display)
        index = last+1
    end
    "[" * (negated ? "^" : "") * join(pieces) * "]"
end
function instruction_notation(entry)
    entry.op == "CHAR" && return "CHAR " * character_display(entry.character)
    entry.op == "CLASS" && return "CLASS " * set_notation(entry.codes,entry.negated)
    entry.op == "SPLIT" && return "SPLIT $(entry.x), $(entry.y)"
    entry.op == "JMP" && return "JMP $(entry.x)"
    entry.op == "SAVE" && return "SAVE $(entry.slot)"
    entry.op == "ASSERT" && return "ASSERT " * entry.kind
    entry.op == "BACKREF" && return "BACKREF $(entry.group)"
    entry.op == "LOOK" && return "LOOK $(entry.kind) $(entry.x)"
    entry.op
end
quoted(text) = "\"" * replace(text,"\\"=>"\\\\","\""=>"\\\"","\n"=>"\\n","\t"=>"\\t") * "\""
