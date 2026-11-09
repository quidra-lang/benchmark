const MLPosition = Tuple{String,Int,Int}
const KEYWORDS = Set(split("let rec and in fun if then else match with true false mod val"))
const SYMBOLS = Set(split(";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |"))
const ESCAPES = Dict('n'=>'\n','t'=>'\t','\\'=>'\\','"'=>'"')
struct MLToken
    kind::String
    spelling::String
    value::Any
    position::MLPosition
end
is_name(token) = token.kind == "identifier" && token.spelling != "_"
letter(c) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
word_character(c) = letter(c) || '0' <= c <= '9' || c == '_'
ml_character(source,index) = 1 <= index <= length(source) ? source[index] : '\0'
function tokenize(source,filename)
    tokens = MLToken[]
    index,line,column = 1,1,1
    while index <= length(source)
        start = index
        position = (filename,line,column)
        character = source[index]
        kind,value = nothing,nothing
        pair = source[index:min(index+1,length(source))]
        if character in (' ','\n')
            index += 1
        elseif pair == "(*"
            closing = findnext("*)",source,index+2)
            if closing === nothing
                kind,value = "invalid","unterminated comment"
                index = length(source)+1
            else
                index = closing.stop+1
            end
        elseif '0' <= character <= '9'
            index += 1
            while '0' <= ml_character(source,index) <= '9'
                index += 1
            end
            digits = lstrip(c -> c == '0',source[start:index-1])
            isempty(digits) && (digits = "0")
            if length(digits) > 10 || (length(digits) == 10 && digits > "2147483647")
                kind,value = "invalid","integer literal too large"
            else
                kind,value = "integer",parse(Int64,digits)
            end
        elseif letter(character) || character == '_'
            index += 1
            while word_character(ml_character(source,index)) || ml_character(source,index) == '\''
                index += 1
            end
            value = String(source[start:index-1])
            kind = value in KEYWORDS ? value : "identifier"
        elseif character == '\'' && 'a' <= ml_character(source,index+1) <= 'z'
            index += 2
            while word_character(ml_character(source,index))
                index += 1
            end
            kind,value = "type_variable",String(source[start:index-1])
        elseif character == '"'
            index += 1
            decoded = IOBuffer()
            invalid_escape = false
            while index <= length(source) && !(source[index] in ('"','\n'))
                if source[index] == '\\' && index < length(source) && source[index+1] != '\n'
                    escape = source[index+1]
                    if haskey(ESCAPES,escape)
                        print(decoded,ESCAPES[escape])
                    else
                        invalid_escape = true
                    end
                    index += 2
                else
                    print(decoded,source[index])
                    index += 1
                end
            end
            if index > length(source) || source[index] == '\n'
                kind,value = "invalid","unterminated string"
            else
                index += 1
                kind,value = invalid_escape ? ("invalid","invalid escape sequence") : ("string",String(take!(decoded)))
            end
        elseif pair in SYMBOLS
            index += 2
            kind,value = String(pair),String(pair)
        elseif string(character) in SYMBOLS
            index += 1
            kind,value = string(character),string(character)
        else
            index += 1
            kind,value = "invalid","illegal character '$character'"
        end
        consumed = source[start:index-1]
        kind === nothing || push!(tokens,MLToken(kind,consumed,value,position))
        newlines = count(==('\n'),consumed)
        if newlines > 0
            line += newlines
            column = length(consumed)-findlast(==('\n'),consumed)+1
        else
            column += length(consumed)
        end
    end
    push!(tokens,MLToken("EOF","",nothing,(filename,count(==('\n'),source)+1,1)))
    tokens
end
