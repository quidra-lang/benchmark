const KEYWORDS = Set(split("int float bool string void if else while for return break continue true false switch case default"))
const TYPE_NAMES = Set(["int","float","bool","string","void"])
const DOUBLE_SYMBOLS = Set(["<=",">=","==","!=","&&","||","+=","-=","*=","/=","%="])
const SINGLE_SYMBOLS = Set("+-*/%<>=!()[]{},;.?:")
const ASSIGNMENTS = Set(["=","+=","-=","*=","/=","%="])
struct SourceError <: Exception
    line::Int
    column::Int
    message::String
end
source_error(line,column,message) = throw(SourceError(line,column,message))
mutable struct CodeComment
    kind::String
    text::String
    line::Int
    column::Int
    blank::Int
    own_line::Bool
end
mutable struct CodeToken
    kind::String
    text::String
    line::Int
    column::Int
    blank::Int
    index::Int
    leading::Vector{CodeComment}
    trailing::Vector{CodeComment}
    allowed::Bool
    trailing_comma::Bool
    original_trailing::Bool
end
new_token(kind,text,line,column,blank,index) = CodeToken(kind,text,line,column,blank,index,CodeComment[],CodeComment[],false,false,false)
character_at(text,i) = 1 <= i <= length(text) ? text[i] : '\0'
code_letter(c) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
code_digit(c) = '0' <= c <= '9'
trim_spaces(text) = rstrip(c -> c == ' ',text)
function lexical_analysis(lines)
    tokens,comments,items = CodeToken[],CodeComment[],Union{CodeToken,CodeComment}[]
    previous_line = 0
    for (line_number,text) in enumerate(lines)
        column = 1
        while column <= length(text)
            c = text[column]
            if c == ' '
                column += 1
                continue
            end
            first = column
            pair = column < length(text) ? text[column:column+1] : string(c)
            if pair == "//"
                kind,value = "line_comment",trim_spaces(text[column:end])
                column = length(text)+1
            elseif pair == "/*"
                last = findnext("*/",text,column+2)
                last === nothing && source_error(line_number,column,"unterminated comment")
                column = last.stop+1
                kind,value = "block_comment",String(text[first:column-1])
            elseif code_letter(c) || c == '_'
                column += 1
                while code_letter(character_at(text,column)) || code_digit(character_at(text,column)) || character_at(text,column) == '_'
                    column += 1
                end
                value = String(text[first:column-1])
                kind = value in KEYWORDS ? "keyword" : "identifier"
            elseif code_digit(c)
                column += 1
                while code_digit(character_at(text,column))
                    column += 1
                end
                if character_at(text,column) == '.' && code_digit(character_at(text,column+1))
                    column += 2
                    while code_digit(character_at(text,column))
                        column += 1
                    end
                end
                kind,value = "number",String(text[first:column-1])
            elseif c == '"'
                column += 1
                closed = false
                while column <= length(text)
                    if text[column] == '\\'
                        column += 2
                    elseif text[column] == '"'
                        column += 1
                        closed = true
                        break
                    else
                        column += 1
                    end
                end
                closed || source_error(line_number,first,"unterminated string")
                kind,value = "string",String(text[first:column-1])
            elseif pair in DOUBLE_SYMBOLS
                column += 2
                kind,value = "symbol",String(pair)
            elseif c in SINGLE_SYMBOLS
                column += 1
                kind,value = "symbol",string(c)
            else
                source_error(line_number,first,"unexpected character '$c'")
            end
            blank = max(0,line_number-previous_line-1)
            previous_line = line_number
            if endswith(kind,"_comment")
                entry = CodeComment(kind,value,line_number,first,blank,false)
                push!(comments,entry)
            else
                entry = new_token(kind,value,line_number,first,blank,length(tokens)+1)
                push!(tokens,entry)
            end
            push!(items,entry)
        end
    end
    last = new_token("end","",length(lines)+1,1,0,length(tokens)+1)
    last.allowed = true
    push!(tokens,last)
    tokens,comments,items
end
