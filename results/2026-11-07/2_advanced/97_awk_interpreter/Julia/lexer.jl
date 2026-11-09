struct SyntaxIssue <: Exception
    position::Tuple{Int,Int}
end

struct AwkToken
    kind::String
    spelling::String
    value::Union{Nothing,Int,String}
    position::Tuple{Int,Int}
end
const KEYWORDS = Set(split("BEGIN END function if else while for do break continue next exit return delete in getline print printf"))
const BUILTINS = Set(split("length substr index split sprintf toupper tolower close int"))
const PAIRS = Set(split("+= -= *= /= %= ^= == <= >= != ++ -- && || >>"))
const SYMBOLS = Set("+-*/%^!><?:=()[]{},;\$")
const ESCAPES = Dict('n'=>'\n','t'=>'\t','\\'=>'\\','"'=>'"','/'=>'/')
letter(character) = 'a' <= character <= 'z' || 'A' <= character <= 'Z'
digit(character) = '0' <= character <= '9'
name_character(character) = letter(character) || digit(character) || character == '_'
function tokenize(source)
    tokens = AwkToken[]
    index,line,column = 1,1,1
    while index <= length(source)
        character = source[index]
        position = (line,column)
        if character == ' '
            index += 1
            column += 1
            continue
        elseif character == '\\' && index < length(source) && source[index+1] == '\n'
            index += 2
            line += 1
            column = 1
            continue
        elseif character == '#'
            while index <= length(source) && source[index] != '\n'
                index += 1
                column += 1
            end
            continue
        elseif character == '\n'
            push!(tokens,AwkToken("newline","\n",nothing,position))
            index += 1
            line += 1
            column = 1
            continue
        end
        finish,value = index+1,nothing
        if digit(character)
            while finish <= length(source) && digit(source[finish])
                finish += 1
            end
            kind,value = "number",parse(Int,source[index:finish-1])
        elseif letter(character) || character == '_'
            while finish <= length(source) && name_character(source[finish])
                finish += 1
            end
            word = source[index:finish-1]
            kind = word in KEYWORDS ? "keyword" : word in BUILTINS ? "builtin" : finish <= length(source) && source[finish] == '(' ? "function_name" : "name"
        elseif character == '"'
            pieces = Char[]
            while finish <= length(source) && source[finish] != '"'
                source[finish] == '\n' && throw(SyntaxIssue(position))
                if source[finish] == '\\'
                    (finish == length(source) || !haskey(ESCAPES,source[finish+1])) && throw(SyntaxIssue((line,column+finish-index)))
                    push!(pieces,ESCAPES[source[finish+1]])
                    finish += 2
                else
                    push!(pieces,source[finish])
                    finish += 1
                end
            end
            finish <= length(source) || throw(SyntaxIssue(position))
            finish += 1
            kind,value = "string",join(pieces)
        elseif finish <= length(source) && source[index:finish] in PAIRS
            finish += 1
            kind = "symbol"
        elseif character in SYMBOLS
            kind = "symbol"
        else
            throw(SyntaxIssue(position))
        end
        push!(tokens,AwkToken(kind,source[index:finish-1],value,position))
        column += finish-index
        index = finish
    end
    push!(tokens,AwkToken("end","",nothing,(count(==('\n'),source)+1,1)))
    tokens
end
