struct AwkValue
    kind::Symbol
    text::String
    numeric::Int
end
const UNINITIALIZED = AwkValue(:uninitialized,"",0)
const WHITESPACE = Set([' ','\t','\n'])
const AwkArray = Dict{String,AwkValue}
const AwkVariable = Union{AwkValue,AwkArray}
number(value) = AwkValue(:number,"",Int(value))
string_value(value) = AwkValue(:string,value,0)
function numeric_prefix(text)
    index,sign,value = 1,1,0
    while index <= length(text) && text[index] in WHITESPACE
        index += 1
    end
    if index <= length(text) && text[index] in ('+','-')
        sign = text[index] == '-' ? -1 : 1
        index += 1
    end
    while index <= length(text) && digit(text[index])
        value = 10*value+Int(text[index])-Int('0')
        index += 1
    end
    sign*value
end
function input_value(text)
    trimmed = strip(text,collect(WHITESPACE))
    beginning = !isempty(trimmed) && trimmed[1] in ('+','-') ? 2 : 1
    numeric = beginning <= length(trimmed) && all(digit,trimmed[beginning:end])
    numeric ? AwkValue(:strnum,text,numeric_prefix(trimmed)) : string_value(text)
end
to_number(value) = value.kind == :string ? numeric_prefix(value.text) : value.numeric
to_string(value) = value.kind == :number ? string(value.numeric) : value.kind == :uninitialized ? "" : value.text
truth(value) = value.kind == :string ? !isempty(value.text) : value.numeric != 0
function compare_values(first,second)
    if first.kind != :string && second.kind != :string
        return cmp(to_number(first),to_number(second))
    end
    cmp(to_string(first),to_string(second))
end
function subscript_order(text)
    digits = startswith(text,"-") ? text[2:end] : text
    integer_form = text == "0" || (!isempty(digits) && '1' <= digits[1] <= '9' && all(digit,digits))
    integer_form ? (0,parse(Int,text),"") : (1,0,text)
end
function split_pieces(text,separator)
    isempty(text) && return String[]
    isempty(separator) && return string.(collect(text))
    separator != " " && return String.(split(text,separator;keepempty=true))
    pieces = String[]
    beginning = 0
    for index in 1:length(text)
        if text[index] in WHITESPACE
            if beginning != 0
                push!(pieces,text[beginning:index-1])
                beginning = 0
            end
        elseif beginning == 0
            beginning = index
        end
    end
    beginning != 0 && push!(pieces,text[beginning:end])
    pieces
end
mutable struct AwkRecord
    special::Function
    zero::AwkValue
    fields::Vector{AwkValue}
end
AwkRecord(special) = AwkRecord(special,string_value(""),AwkValue[])
function set_record!(record,text)
    record.zero = input_value(text)
    record.fields = input_value.(split_pieces(text,to_string(record.special("FS"))))
end
function read_field(record,index)
    index == 0 ? record.zero : index <= length(record.fields) ? record.fields[index] : UNINITIALIZED
end
function rebuild_record!(record)
    record.zero = input_value(join(to_string.(record.fields),to_string(record.special("OFS"))))
end
function write_field!(record,index,value)
    if index == 0
        set_record!(record,to_string(value))
        return
    end
    while length(record.fields) < index
        push!(record.fields,string_value(""))
    end
    record.fields[index] = value
    rebuild_record!(record)
end
function resize_fields!(record,size)
    size < length(record.fields) && resize!(record.fields,size)
    while length(record.fields) < size
        push!(record.fields,string_value(""))
    end
    rebuild_record!(record)
end
function quoted_value(text)
    pieces = ["\""]
    escapes = Dict('"'=>"\\\"",'\\'=>"\\\\",'\n'=>"\\n",'\t'=>"\\t")
    for character in text
        push!(pieces,haskey(escapes,character) ? escapes[character] : 32 <= Int(character) <= 126 ? string(character) : "\\" * string(Int(character);base=8,pad=3))
    end
    push!(pieces,"\"")
    join(pieces)
end
function describe_value(value)
    value.kind == :number && return string(value.numeric)
    value.kind == :uninitialized && return "(uninitialized)"
    quoted_value(value.text) * (value.kind == :strnum ? " (strnum)" : "")
end
