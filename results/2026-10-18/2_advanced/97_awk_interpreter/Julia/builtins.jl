struct RuntimeIssue <: Exception
    position::Tuple{Int,Int}
    message::String
end
function format_output(arguments,position)
    format = to_string(arguments[1])
    pieces = String[]
    index,argument_index = 1,2
    while index <= length(format)
        if format[index] != '%'
            push!(pieces,string(format[index]))
            index += 1
            continue
        end
        index += 1
        if index <= length(format) && format[index] == '%'
            push!(pieces,"%")
            index += 1
            continue
        end
        flags = Set{Char}()
        while index <= length(format) && format[index] in ('-','0')
            push!(flags,format[index])
            index += 1
        end
        beginning = index
        while index <= length(format) && digit(format[index])
            index += 1
        end
        width = beginning < index ? parse(Int,format[beginning:index-1]) : 0
        precision = nothing
        if index <= length(format) && format[index] == '.'
            index += 1
            beginning = index
            while index <= length(format) && digit(format[index])
                index += 1
            end
            precision = beginning < index ? parse(Int,format[beginning:index-1]) : 0
        end
        (index > length(format) || !(format[index] in ('d','i','s','c','x','o'))) && throw(RuntimeIssue(position,"invalid format"))
        conversion = format[index]
        index += 1
        argument_index <= length(arguments) || throw(RuntimeIssue(position,"not enough arguments"))
        value = arguments[argument_index]
        argument_index += 1
        numeric = conversion in ('d','i','x','o')
        if numeric
            integer = to_number(value)
            base = conversion in ('d','i') ? 10 : conversion == 'x' ? 16 : 8
            digits = string(abs(integer);base=base)
            if precision !== nothing
                digits = precision == 0 && integer == 0 ? "" : lpad(digits,precision,'0')
            end
            body = (integer < 0 ? "-" : "") * digits
        elseif conversion == 's'
            body = to_string(value)
            precision !== nothing && (body = body[1:min(length(body),precision)])
        elseif value.kind in (:number,:strnum)
            code = to_number(value)
            (code == 10 || 32 <= code <= 126) || throw(RuntimeIssue(position,"invalid character code"))
            body = string(Char(code))
        else
            text = to_string(value)
            body = isempty(text) ? "" : text[1:1]
        end
        missing = width-length(body)
        if missing > 0
            if '-' in flags
                body *= " "^missing
            elseif numeric && '0' in flags && precision === nothing
                body = startswith(body,"-") ? "-" * "0"^missing * body[2:end] : "0"^missing * body
            else
                body = " "^missing * body
            end
        end
        push!(pieces,body)
    end
    join(pieces)
end
function invoke_builtin(name,arguments,position)
    name == "sprintf" && return string_value(format_output(arguments,position))
    name == "int" && return number(to_number(arguments[1]))
    text = to_string(arguments[1])
    if name == "substr"
        beginning = to_number(arguments[2])
        finish = length(arguments) == 3 ? beginning+to_number(arguments[3]) : length(text)+1
        beginning,finish = max(beginning,1),min(finish,length(text)+1)
        return string_value(finish > beginning ? text[beginning:finish-1] : "")
    elseif name == "index"
        sought = to_string(arguments[2])
        found = isempty(sought) ? nothing : findfirst(sought,text)
        return number(found === nothing ? 0 : first(found))
    elseif name == "toupper"
        return string_value(join('a' <= character <= 'z' ? Char(Int(character)-32) : character for character in text))
    end
    string_value(join('A' <= character <= 'Z' ? Char(Int(character)+32) : character for character in text))
end
