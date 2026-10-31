struct PPToken
    kind::String
    spelling::String
    line::Int
    space::Bool
    hide::Set{String}
end
PPToken(kind,spelling,line,space) = PPToken(kind,spelling,line,space,Set{String}())
function token_with(token;kind=token.kind,spelling=token.spelling,line=token.line,space=token.space,hide=token.hide)
    PPToken(kind,spelling,line,space,hide)
end
struct LogicalLine
    tokens::Vector{PPToken}
    start::Int
    stop::Int
end
const PUNCTUATORS = split("... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #")
identifier_start(c) = c == '_' || 'a' <= c <= 'z' || 'A' <= c <= 'Z'
digit(c) = '0' <= c <= '9'
function read_token(text,position=1;header=false)
    character = text[position]
    if header && character == '<'
        closing,newline = findnext(==('>'),text,position+1),findnext(==('\n'),text,position+1)
        if closing !== nothing && (newline === nothing || closing < newline)
            return "header",String(text[position:closing]),closing+1
        end
    end
    if identifier_start(character)
        last = position+1
        while last <= length(text) && (identifier_start(text[last]) || digit(text[last]))
            last += 1
        end
        return "identifier",String(text[position:last-1]),last
    elseif digit(character) || (character == '.' && position < length(text) && digit(text[position+1]))
        last = position+1
        while last <= length(text)
            if text[last] in "eEpP" && last < length(text) && text[last+1] in "+-"
                last += 2
            elseif identifier_start(text[last]) || digit(text[last]) || text[last] == '.'
                last += 1
            else
                break
            end
        end
        return "number",String(text[position:last-1]),last
    elseif character in ('"','\'')
        last = position+1
        while last <= length(text) && text[last] != '\n'
            text[last] == character && return (character == '"' ? "string" : "character",String(text[position:last]),last+1)
            last += text[last] == '\\' && last < length(text) && text[last+1] != '\n' ? 2 : 1
        end
    end
    for punctuator in PUNCTUATORS
        if startswith(SubString(text,position),punctuator)
            return "punctuator",punctuator,position+length(punctuator)
        end
    end
    "other",string(character),position+1
end
function splice_lines(text)
    characters,positions = Char[],Int[]
    index,line = 1,1
    while index <= length(text)
        if text[index] == '\\' && index < length(text) && text[index+1] == '\n'
            index += 2
            line += 1
            continue
        end
        push!(characters,text[index])
        push!(positions,line)
        text[index] == '\n' && (line += 1)
        index += 1
    end
    join(characters),positions
end
function scan_tokens(text,positions,start=1)
    lines,tokens = LogicalLine[],PPToken[]
    index,spaced = 1,true
    while index <= length(text)
        pair = text[index:min(index+1,length(text))]
        if text[index] == ' '
            spaced = true
            index += 1
        elseif text[index] == '\n'
            last = positions[index]
            push!(lines,LogicalLine(tokens,start,last))
            tokens,start,spaced = PPToken[],last+1,true
            index += 1
        elseif pair == "/*"
            closing = findnext("*/",text,index+2)
            index = closing === nothing ? length(text)+1 : closing.stop+1
            spaced = true
        elseif pair == "//"
            closing = findnext(==('\n'),text,index+2)
            index = closing === nothing ? length(text)+1 : closing
            spaced = true
        else
            header = length(tokens) == 2 && tokens[1].spelling == "#" && tokens[2].spelling == "include"
            kind,spelling,last = read_token(text,index;header)
            push!(tokens,PPToken(kind,spelling,positions[index],spaced))
            index,spaced = last,false
        end
    end
    isempty(tokens) || push!(lines,LogicalLine(tokens,start,positions[end]))
    lines
end
function lex_source(text)
    spliced,positions = splice_lines(text)
    scan_tokens(spliced,positions)
end
function lex_definition(text,line)
    text *= "\n"
    [token for logical in scan_tokens(text,fill(line,length(text)),line) for token in logical.tokens]
end
function render(tokens)
    join([(index > 1 && token.space ? " " : "") * token.spelling for (index,token) in enumerate(tokens)])
end
function single_token(text)
    (isempty(text) || startswith(text,"//") || startswith(text,"/*")) && return nothing
    kind,spelling,last = read_token(text)
    last == length(text)+1 ? kind : nothing
end
