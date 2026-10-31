const ToyPosition = Tuple{Int,Int}
struct ToyToken
    kind::String
    spelling::String
    position::ToyPosition
end
const KEYWORDS = Set(split("int bool void true false if else while for break continue return print read"))
const PAIRS = Set(["<=",">=","==","!=","&&","||"])
const SYMBOLS = Set("+-*/%<>=!(){}[],;")
struct CompileError <: Exception
    kind::String
    position::ToyPosition
    message::String
end
letter(c) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
digit(c) = '0' <= c <= '9'
function tokenize(lines)
    source = join([text for (number,text) in lines],"\n") * "\n"
    line,column,index = lines[1][1],1,1
    tokens = ToyToken[]
    while index <= length(source)
        character,start = source[index],(line,column)
        if character == ' '
            index += 1
            column += 1
            continue
        elseif character == '\n'
            index += 1
            line += 1
            column = 1
            continue
        end
        pair = source[index:min(index+1,length(source))]
        if pair == "//"
            last = findnext(==('\n'),source,index)
            column += last-index
            index = last
            continue
        elseif pair == "/*"
            last = findnext("*/",source,index+2)
            last === nothing && throw(CompileError("lexical",start,"unterminated comment"))
            stop = last.stop+1
            comment = source[index:stop-1]
            newlines = count(==('\n'),comment)
            if newlines > 0
                line += newlines
                column = length(comment)-findlast(==('\n'),comment)+1
            else
                column += length(comment)
            end
            index = stop
            continue
        end
        stop = index+1
        if letter(character) || character == '_'
            while stop <= length(source) && (letter(source[stop]) || digit(source[stop]) || source[stop] == '_')
                stop += 1
            end
            spelling = String(source[index:stop-1])
            kind = spelling in KEYWORDS ? "keyword" : "identifier"
        elseif digit(character)
            while stop <= length(source) && digit(source[stop])
                stop += 1
            end
            spelling = String(source[index:stop-1])
            parse(Int64,spelling) <= 2147483647 || throw(CompileError("lexical",start,"integer literal too large"))
            kind = "integer"
        elseif pair in PAIRS
            stop += 1
            spelling,kind = String(pair),"symbol"
        elseif character in SYMBOLS
            spelling,kind = string(character),"symbol"
        else
            throw(CompileError("lexical",start,"unexpected character '$character'"))
        end
        push!(tokens,ToyToken(kind,spelling,start))
        column += stop-index
        index = stop
    end
    last_number,last_text = lines[end]
    push!(tokens,ToyToken("end","",(last_number,length(last_text)+1)))
    tokens
end
