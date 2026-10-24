using Base64

const WIRE_TYPES = Dict(
    "uint32" => 0, "uint64" => 0, "sint32" => 0, "sint64" => 0, "bool" => 0,
    "fixed32" => 5, "sfixed32" => 5, "fixed64" => 1, "string" => 2, "bytes" => 2,
)
const INTEGER_RANGES = Dict(
    "uint32" => (0, 4294967295), "uint64" => (0, 9007199254740991),
    "sint32" => (-2147483648, 2147483647),
    "sint64" => (-4503599627370496, 4503599627370495),
    "fixed32" => (0, 4294967295), "sfixed32" => (-2147483648, 2147483647),
    "fixed64" => (0, 9007199254740991),
)
const WIRE_NAMES = Dict(0 => "varint", 1 => "i64", 2 => "len", 5 => "i32")
const WORD_COUNTS = Dict(
    "VARINT" => 2, "ZIGZAG" => 2, "SCHEMA" => 2, "ENCODE" => 3, "SIZE" => 3,
    "DECODE" => 3, "LITERAL" => 3, "JSON" => 3, "CANON" => 3, "EXPLAIN" => 3,
    "GET" => 4, "PATCH" => 5, "CLEAR" => 4, "MERGE" => 4, "DIFF" => 4,
)
const HEX_COUNTS = Dict(
    "DECODE" => 1, "LITERAL" => 1, "JSON" => 1, "CANON" => 1, "EXPLAIN" => 1,
    "GET" => 1, "PATCH" => 1, "CLEAR" => 1, "MERGE" => 2, "DIFF" => 2,
)
const SHAPES = Dict(:integer => :integer, :bool => :boolean, :enum => :name,
                    :string => :string, :bytes => :bytes, :message => :message)
const HEX_DIGITS = "0123456789abcdef"

struct CommandError <: Exception
    reason::String
end
fail(reason) = throw(CommandError(reason))
byte_error(reason, position) = fail("$reason at byte $position")
column_error(reason, column) = fail("$reason at column $column")
is_hex(text) = all(c -> c in HEX_DIGITS, text)
is_digit(c) = '0' <= c <= '9'
is_letter(c) = 'a' <= c <= 'z' || 'A' <= c <= 'Z'
zigzag(n) = n >= 0 ? 2n : -2n - 1
unzigzag(n) = iseven(n) ? n ÷ 2 : -((n + 1) ÷ 2)
hex_text(data) = isempty(data) ? "-" : bytes2hex(data)
bytes_notation(data) = "<" * bytes2hex(data) * ">"

function varint_bytes(n)
    result = UInt8[]
    while n >= 128
        push!(result, UInt8((n % 128) + 128))
        n ÷= 128
    end
    push!(result, UInt8(n))
    return result
end
function parse_hex(text)
    text == "-" && return UInt8[]
    (isempty(text) || isodd(length(text)) || !is_hex(text)) && fail("invalid hex")
    return hex2bytes(text)
end
function quote_bytes(data, prefix)
    io = IOBuffer()
    print(io, '"')
    for b in data
        if b == 0x22
            print(io, "\\\"")
        elseif b == 0x5c
            print(io, "\\\\")
        elseif b == 0x0a
            print(io, "\\n")
        elseif b == 0x09
            print(io, "\\t")
        elseif 0x20 <= b <= 0x7e
            print(io, Char(b))
        else
            print(io, prefix, string(b; base=16, pad=2))
        end
    end
    print(io, '"')
    return String(take!(io))
end

struct EnumType
    numbers::Dict{String,Int}
    names::Dict{Int,String}
end
EnumType() = EnumType(Dict{String,Int}(), Dict{Int,String}())
mutable struct Field
    number::Int
    type_name::String
    name::String
    required::Bool
    repeated::Bool
    packed::Bool
    group::Union{Nothing,String}
    kind::Symbol
    wire::Int
end
struct MessageType
    name::String
    fields::Vector{Field}
    by_number::Dict{Int,Field}
    by_name::Dict{String,Field}
end
MessageType(name) = MessageType(name, Field[], Dict{Int,Field}(), Dict{String,Field}())
struct Schema
    enums::Dict{String,EnumType}
    messages::Dict{String,MessageType}
end
Schema() = Schema(Dict{String,EnumType}(), Dict{String,MessageType}())

function read_schema(io)
    schema = Schema()
    current = ""
    while true
        words = String.(split(readline(io), ' '))
        words == ["END", "SCHEMA"] && break
        if words[1] == "ENUM"
            current = words[2]
            schema.enums[current] = EnumType()
        elseif words[1] == "MESSAGE"
            current = words[2]
            schema.messages[current] = MessageType(current)
        elseif words[1] == "VALUE"
            name, number = words[2], parse(Int, words[3])
            schema.enums[current].numbers[name] = number
            schema.enums[current].names[number] = name
        elseif words[1] == "FIELD"
            options = words[5:end]
            required = options == ["REQUIRED"]
            repeated = !isempty(options) && options[1] == "REPEATED"
            packed = options == ["REPEATED", "PACKED"]
            group = !isempty(options) && options[1] == "ONEOF" ? options[2] : nothing
            f = Field(parse(Int, words[2]), words[3], words[4], required, repeated,
                      packed, group, :unresolved, -1)
            typ = schema.messages[current]
            push!(typ.fields, f)
            typ.by_number[f.number] = f
            typ.by_name[f.name] = f
        end
    end
    for typ in values(schema.messages)
        sort!(typ.fields; by=f -> f.number)
        for f in typ.fields
            if haskey(WIRE_TYPES, f.type_name)
                f.wire = WIRE_TYPES[f.type_name]
                f.kind = haskey(INTEGER_RANGES, f.type_name) ? :integer : Symbol(f.type_name)
            elseif haskey(schema.enums, f.type_name)
                f.wire, f.kind = 0, :enum
            else
                f.wire, f.kind = 2, :message
            end
        end
    end
    return schema
end

struct UnknownField
    number::Int
    wire::Int
    raw::Union{Int,Vector{UInt8}}
end
unknown_notation(u) = u.wire == 0 ? string(u.raw) : bytes_notation(u.raw)
mutable struct Message
    typ::MessageType
    values::Dict{Int,Any}
    unknown::Vector{UnknownField}
end
Message(typ) = Message(typ, Dict{Int,Any}(), UnknownField[])
hasfieldvalue(m, f) = haskey(m.values, f.number)
function field_values(m, f)
    hasfieldvalue(m, f) || return Any[]
    return f.repeated ? m.values[f.number] : Any[m.values[f.number]]
end
function set_items!(m, f, items)
    if isempty(items)
        delete!(m.values, f.number)
    else
        m.values[f.number] = items
    end
end
function remove_group!(m, f)
    isnothing(f.group) && return
    for other in m.typ.fields
        if other.number != f.number && other.group == f.group
            delete!(m.values, other.number)
        end
    end
end
function apply_values!(m, f, items)
    remove_group!(m, f)
    if f.repeated
        set_items!(m, f, vcat(field_values(m, f), items))
    elseif f.kind == :message && hasfieldvalue(m, f)
        merge_message!(m.values[f.number], items[1])
    else
        m.values[f.number] = items[1]
    end
end
function merge_message!(target, source)
    for f in source.typ.fields
        hasfieldvalue(source, f) && apply_values!(target, f, field_values(source, f))
    end
    append!(target.unknown, source.unknown)
end
function check_required(m, prefix="")
    for f in m.typ.fields
        f.required && !hasfieldvalue(m, f) && fail("missing required field $prefix$(f.name)")
        if f.kind == :message
            for (i, value) in enumerate(field_values(m, f))
                suffix = f.repeated ? "[$(i - 1)]" : ""
                check_required(value, "$prefix$(f.name)$suffix.")
            end
        end
    end
end

function element_bytes(f, value)
    if f.wire == 2
        payload = f.kind == :message ? encode_message(value) : value
        return vcat(varint_bytes(length(payload)), payload)
    elseif f.wire in (1, 5)
        n = value < 0 ? value + 4294967296 : value
        size = f.wire == 1 ? 8 : 4
        return UInt8[(n >> (8i)) & 0xff for i in 0:size-1]
    elseif f.kind == :bool
        return varint_bytes(value ? 1 : 0)
    else
        return varint_bytes(f.type_name in ("sint32", "sint64") ? zigzag(value) : value)
    end
end
function field_records(f, items)
    result = UInt8[]
    if f.packed
        payload = UInt8[]
        for item in items
            append!(payload, element_bytes(f, item))
        end
        append!(result, varint_bytes(8 * f.number + 2))
        append!(result, varint_bytes(length(payload)))
        append!(result, payload)
    else
        tag = varint_bytes(8 * f.number + f.wire)
        for item in items
            append!(result, tag)
            append!(result, element_bytes(f, item))
        end
    end
    return result
end
function encode_message(m)
    result = UInt8[]
    for f in m.typ.fields
        hasfieldvalue(m, f) && append!(result, field_records(f, field_values(m, f)))
    end
    for u in m.unknown
        append!(result, varint_bytes(8 * u.number + u.wire))
        if u.wire == 0
            append!(result, varint_bytes(u.raw))
        else
            u.wire == 2 && append!(result, varint_bytes(length(u.raw)))
            append!(result, u.raw)
        end
    end
    return result
end

function value_notation(schema, f, value)
    f.kind == :message && return message_notation(schema, value)
    f.kind == :enum && return schema.enums[f.type_name].names[value]
    f.kind == :bool && return value ? "true" : "false"
    f.kind == :string && return quote_bytes(value, "\\x")
    f.kind == :bytes && return bytes_notation(value)
    return string(value)
end
list_notation(s, f, items) = "[" * join((value_notation(s, f, v) for v in items), ", ") * "]"
function message_notation(schema, m)
    items = String[]
    for f in m.typ.fields
        hasfieldvalue(m, f) || continue
        vs = field_values(m, f)
        text = f.repeated ? list_notation(schema, f, vs) : value_notation(schema, f, vs[1])
        push!(items, "$(f.name): $text")
    end
    return "{" * join(items, ", ") * "}"
end
function json_value(schema, f, value)
    f.kind == :message && return json_message(schema, value)
    f.kind == :enum && return "\"" * schema.enums[f.type_name].names[value] * "\""
    f.kind == :bool && return value ? "true" : "false"
    f.kind == :string && return quote_bytes(value, "\\u00")
    f.kind == :bytes && return "\"" * base64encode(value) * "\""
    f.type_name in ("uint64", "sint64", "fixed64") && return "\"$value\""
    return string(value)
end
function json_message(schema, m)
    items = String[]
    for f in m.typ.fields
        hasfieldvalue(m, f) || continue
        parts = split(f.name, '_')
        key = parts[1] * join(uppercasefirst.(parts[2:end]))
        vs = [json_value(schema, f, v) for v in field_values(m, f)]
        text = f.repeated ? "[" * join(vs, ',') * "]" : vs[1]
        push!(items, "\"$key\":$text")
    end
    return "{" * join(items, ',') * "}"
end

mutable struct Reader
    schema::Schema
    data::Vector{UInt8}
    explaining::Bool
    lines::Vector{String}
end
function read_varint(r, start, finish)
    value = 0
    for i in 0:7
        position = start + i
        position >= finish && byte_error("truncated varint", start)
        b = Int(r.data[position + 1])
        value |= (b & 127) << (7i)
        if b < 128
            value >= 9007199254740992 && byte_error("varint too large", start)
            return value, position + 1
        end
        i == 7 && byte_error("varint too long", start)
    end
    error("unreachable")
end
function read_fixed(r, start, finish, wire)
    size = wire == 1 ? 8 : 4
    finish - start < size && byte_error("truncated $(WIRE_NAMES[wire])", start)
    return r.data[start+1:start+size], start + size
end
function little_number(data)
    value = UInt64(0)
    for (i, b) in enumerate(data)
        value |= UInt64(b) << (8(i - 1))
    end
    return value
end
function scalar_value(schema, f, number, position)
    if f.kind == :bool
        number > 1 && byte_error("value out of range", position)
        return number == 1
    elseif f.kind == :enum
        haskey(schema.enums[f.type_name].names, number) || byte_error("unknown enum number", position)
        return Int(number)
    end
    if f.type_name == "fixed64"
        number > UInt64(9007199254740991) && byte_error("value out of range", position)
    end
    value = Int(number)
    if f.type_name in ("sint32", "sint64")
        value = unzigzag(value)
    elseif f.type_name == "sfixed32" && value >= 2147483648
        value -= 4294967296
    end
    low, high = INTEGER_RANGES[f.type_name]
    low <= value <= high || byte_error("value out of range", position)
    return value
end
function convert_value(r, f, raw, position)
    if f.kind == :string
        for (i, b) in enumerate(raw)
            b >= 0x80 && byte_error("invalid string", position + i - 1)
        end
        return raw
    elseif f.kind == :bytes
        return raw
    end
    number = f.wire == 0 ? raw : little_number(raw)
    return scalar_value(r.schema, f, number, position)
end
function packed_values(r, f, start, finish)
    values = Any[]
    position = start
    while position < finish
        element_start = position
        if f.wire == 0
            number, position = read_varint(r, position, finish)
        else
            raw, position = read_fixed(r, position, finish, f.wire)
            number = little_number(raw)
        end
        push!(values, scalar_value(r.schema, f, number, element_start))
    end
    return values
end
function read_message(r, typ, start, finish, depth)
    m = Message(typ)
    position = start
    while position < finish
        position = read_record!(r, m, position, finish, depth)
    end
    return m
end
function read_record!(r, m, start, finish, depth)
    tag, position = read_varint(r, start, finish)
    number, wire = tag ÷ 8, tag % 8
    number == 0 && byte_error("invalid field number", start)
    haskey(WIRE_NAMES, wire) || byte_error("invalid wire type", start)
    f = get(m.typ.by_number, number, nothing)
    packed = !isnothing(f) && f.repeated && f.wire != 2 && wire == 2
    if !isnothing(f) && wire != f.wire && !packed
        byte_error("wire type mismatch", start)
    end
    value_start = position
    if wire == 0
        raw, position = read_varint(r, position, finish)
    elseif wire == 2
        q = position
        payload_length, value_start = read_varint(r, position, finish)
        value_start + payload_length > finish && byte_error("length past end", q)
        position = value_start + payload_length
        raw = r.data[value_start+1:position]
    else
        raw, position = read_fixed(r, position, finish, wire)
    end
    name = isnothing(f) ? "?" : f.name
    header = "$(repeat("  ", depth))$start $number $name $(WIRE_NAMES[wire])"
    wire == 2 && (header *= " $(length(raw))")
    if isnothing(f)
        u = UnknownField(number, wire, raw)
        push!(m.unknown, u)
        r.explaining && push!(r.lines, "$header $(unknown_notation(u))")
        return position
    end
    if f.kind == :message
        r.explaining && push!(r.lines, header)
        values = Any[read_message(r, r.schema.messages[f.type_name], value_start, position, depth + 1)]
    elseif packed
        values = packed_values(r, f, value_start, position)
        if r.explaining
            suffix = join((" " * value_notation(r.schema, f, v) for v in values))
            push!(r.lines, "$header packed$suffix")
        end
    else
        values = Any[convert_value(r, f, raw, value_start)]
        r.explaining && push!(r.lines, "$header $(value_notation(r.schema, f, values[1]))")
    end
    !r.explaining && apply_values!(m, f, values)
    return position
end
function decode(schema, typ, data)
    r = Reader(schema, data, false, String[])
    m = read_message(r, typ, 0, length(data), 0)
    check_required(m)
    return m
end

struct Token
    kind::Symbol
    column::Int
    text::String
    value::Any
end
Token(kind, column; text="", value=nothing) = Token(kind, column, text, value)
function shape(t)
    if t.kind == :symbol
        return t.text == "{" ? :message : t.text == "[" ? :list : nothing
    elseif t.kind == :name
        return t.text in ("true", "false") ? :boolean : :name
    end
    return t.kind == :end ? nothing : t.kind
end
function tokenize(text)
    tokens = Token[]
    n, i = length(text), 1
    while i <= n
        c = text[i]
        if c == ' '
            i += 1
        elseif c in "{}[]:,"
            push!(tokens, Token(:symbol, i; text=string(c)))
            i += 1
        elseif c == '"'
            start = i
            i += 1
            data = UInt8[]
            while i <= n && text[i] != '"'
                c = text[i]
                if c != '\\'
                    push!(data, UInt8(c))
                    i += 1
                else
                    i + 1 <= n || column_error("syntax error", start)
                    escape = text[i + 1]
                    if escape in ('"', '\\', 'n', 't')
                        b = escape == 'n' ? 0x0a : escape == 't' ? 0x09 : UInt8(escape)
                        push!(data, b)
                        i += 2
                    elseif escape == 'x' && i + 3 <= n && is_hex(text[i+2:i+3])
                        b = parse(Int, text[i+2:i+3]; base=16)
                        b < 128 || column_error("syntax error", start)
                        push!(data, UInt8(b))
                        i += 4
                    else
                        column_error("syntax error", start)
                    end
                end
            end
            i <= n || column_error("syntax error", start)
            push!(tokens, Token(:string, start; value=data))
            i += 1
        elseif c == '<'
            start = i
            close = findnext('>', text, i + 1)
            isnothing(close) && column_error("syntax error", start)
            digits = text[i+1:close-1]
            (isodd(length(digits)) || !is_hex(digits)) && column_error("syntax error", start)
            push!(tokens, Token(:bytes, start; value=hex2bytes(digits)))
            i = close + 1
        elseif c == '-' || is_digit(c)
            start = i
            c == '-' && (i += 1)
            digits_start = i
            while i <= n && is_digit(text[i])
                i += 1
            end
            i == digits_start && column_error("syntax error", start)
            push!(tokens, Token(:integer, start; value=parse(Int, text[start:i-1])))
        elseif is_letter(c) || c == '_'
            start = i
            i += 1
            while i <= n && (is_letter(text[i]) || is_digit(text[i]) || text[i] == '_')
                i += 1
            end
            push!(tokens, Token(:name, start; text=String(text[start:i-1])))
        else
            column_error("syntax error", i)
        end
    end
    push!(tokens, Token(:end, n + 1))
    return tokens
end
mutable struct LiteralParser
    schema::Schema
    tokens::Vector{Token}
    index::Int
end
LiteralParser(schema, text) = LiteralParser(schema, tokenize(text), 1)
current_token(p) = p.tokens[p.index]
function take_token!(p)
    t = current_token(p)
    p.index += 1
    return t
end
at_symbol(p, sym) = current_token(p).kind == :symbol && current_token(p).text == sym
parser_error(p, reason) = column_error(reason, current_token(p).column)
function expect!(p, sym)
    at_symbol(p, sym) || parser_error(p, "syntax error")
    return take_token!(p)
end
finish_literal(p) = current_token(p).kind == :end || parser_error(p, "syntax error")
function parse_message!(p, typ)
    expect!(p, "{")
    m = Message(typ)
    seen = Set{Int}()
    groups = Set{String}()
    if !at_symbol(p, "}")
        while true
            t = current_token(p)
            t.kind == :name || parser_error(p, "syntax error")
            f = get(typ.by_name, t.text, nothing)
            isnothing(f) && parser_error(p, "unknown field")
            f.number in seen && parser_error(p, "duplicate field")
            !isnothing(f.group) && f.group in groups && parser_error(p, "oneof conflict")
            take_token!(p)
            push!(seen, f.number)
            !isnothing(f.group) && push!(groups, f.group)
            expect!(p, ":")
            if f.repeated
                set_items!(m, f, parse_list!(p, f))
            else
                m.values[f.number] = parse_element!(p, f)
            end
            at_symbol(p, ",") || break
            take_token!(p)
        end
    end
    closing = expect!(p, "}")
    for f in typ.fields
        f.required && f.number ∉ seen && column_error("missing required field $(f.name)", closing.column)
    end
    return m
end
function parse_list!(p, f)
    s = shape(current_token(p))
    isnothing(s) && parser_error(p, "syntax error")
    s == :list || parser_error(p, "type mismatch")
    take_token!(p)
    items = Any[]
    if !at_symbol(p, "]")
        push!(items, parse_element!(p, f))
        while at_symbol(p, ",")
            take_token!(p)
            push!(items, parse_element!(p, f))
        end
    end
    expect!(p, "]")
    return items
end
function parse_element!(p, f)
    t = current_token(p)
    s = shape(t)
    isnothing(s) && parser_error(p, "syntax error")
    s == SHAPES[f.kind] || parser_error(p, "type mismatch")
    s == :message && return parse_message!(p, p.schema.messages[f.type_name])
    take_token!(p)
    if s == :integer
        low, high = INTEGER_RANGES[f.type_name]
        low <= t.value <= high || column_error("out of range", t.column)
        return t.value
    elseif s == :boolean
        return t.text == "true"
    elseif s == :name
        e = p.schema.enums[f.type_name]
        haskey(e.numbers, t.text) || column_error("unknown enum value", t.column)
        return e.numbers[t.text]
    end
    return t.value
end

struct PathSegment
    field::Field
    index::Union{Nothing,Int}
end
whole(seg) = seg.field.repeated && isnothing(seg.index)
item_position(seg) = isnothing(seg.index) ? 1 : seg.index + 1
function parse_path(schema, typ, text)
    segments = PathSegment[]
    parts = split(text, '.'; keepempty=true)
    current = typ
    for (i, part) in enumerate(parts)
        m = match(r"^([a-z][a-z0-9_]*)(?:\[([0-9]{1,6})\])?$", part)
        isnothing(m) && fail("invalid path")
        name = m.captures[1]
        index = isnothing(m.captures[2]) ? nothing : parse(Int, m.captures[2])
        f = get(current.by_name, name, nothing)
        (isnothing(f) || (!isnothing(index) && !f.repeated)) && fail("invalid path")
        push!(segments, PathSegment(f, index))
        if i < length(parts)
            (f.kind != :message || (f.repeated && isnothing(index))) && fail("invalid path")
            current = schema.messages[f.type_name]
        end
    end
    return segments
end
function follow(m, segments)
    for seg in segments
        vs = field_values(m, seg.field)
        i = item_position(seg)
        i > length(vs) && return nothing
        m = vs[i]
    end
    return m
end
function patch_child!(schema, m, seg)
    f = seg.field
    if f.repeated
        vs = field_values(m, f)
        i = item_position(seg)
        i > length(vs) && fail("index out of range")
        return vs[i]
    end
    if !hasfieldvalue(m, f)
        remove_group!(m, f)
        m.values[f.number] = Message(schema.messages[f.type_name])
    end
    return m.values[f.number]
end

function text_contents!(lines, schema, m, depth)
    indent = repeat("  ", depth)
    for f in m.typ.fields
        for value in field_values(m, f)
            if f.kind == :message
                push!(lines, "$indent$(f.name) {")
                text_contents!(lines, schema, value, depth + 1)
                push!(lines, indent * "}")
            else
                push!(lines, "$indent$(f.name): $(value_notation(schema, f, value))")
            end
        end
    end
    for u in m.unknown
        push!(lines, "$indent$(u.number): $(WIRE_NAMES[u.wire]) $(unknown_notation(u))")
    end
end
function text_message(schema, m)
    lines = [m.typ.name * " {"]
    text_contents!(lines, schema, m, 1)
    push!(lines, "}")
    return lines
end
function schema_fields!(lines, schema, typ, chain, depth)
    for f in typ.fields
        kind = f.required ? "required " : f.packed ? "repeated packed " :
               f.repeated ? "repeated " : isnothing(f.group) ? "" : "oneof $(f.group) "
        line = "$(repeat("  ", depth))$(f.number) $(f.name): $kind$(f.type_name)"
        if f.kind == :enum
            names = schema.enums[f.type_name].names
            line *= " (" * join(("$(names[n])=$n" for n in sort!(collect(keys(names)))), ", ") * ")"
        end
        recursive = f.kind == :message && f.type_name in chain
        push!(lines, recursive ? line * " (recursive)" : line)
        if f.kind == :message && !recursive
            schema_fields!(lines, schema, schema.messages[f.type_name], vcat(chain, [f.type_name]), depth + 1)
        end
    end
end
function compare_messages!(lines, schema, a, b, prefix="")
    for f in a.typ.fields
        left, right = field_values(a, f), field_values(b, f)
        for i in 1:max(length(left), length(right))
            path = prefix * f.name * (f.repeated ? "[$(i - 1)]" : "")
            both = i <= length(left) && i <= length(right)
            if both && f.kind == :message
                compare_messages!(lines, schema, left[i], right[i], path * ".")
            elseif !both || left[i] != right[i]
                old = i <= length(left) ? value_notation(schema, f, left[i]) : "(none)"
                new = i <= length(right) ? value_notation(schema, f, right[i]) : "(none)"
                push!(lines, "$path: $old -> $new")
            end
        end
    end
end

function process_command(schema, line)
    words = String.(split(line, ' '; keepempty=true))
    cmd = words[1]
    haskey(WORD_COUNTS, cmd) || fail("unknown command")
    expected = WORD_COUNTS[cmd]
    count = length(words)
    variable = cmd in ("ENCODE", "SIZE", "PATCH")
    (count < expected || (!variable && count != expected)) && fail("wrong number of arguments")
    if cmd == "VARINT" || cmd == "ZIGZAG"
        occursin(r"^-?[0-9]{1,18}$", words[2]) || fail("invalid number")
        n = parse(Int, words[2])
        low, high = cmd == "VARINT" ? INTEGER_RANGES["uint64"] : INTEGER_RANGES["sint64"]
        low <= n <= high || fail("invalid number")
        cmd == "VARINT" && return [hex_text(varint_bytes(n))]
        z = zigzag(n)
        return ["$z $(hex_text(varint_bytes(z)))"]
    end
    haskey(schema.messages, words[2]) || fail("unknown message type")
    typ = schema.messages[words[2]]
    data = [parse_hex(words[2 + i]) for i in 1:get(HEX_COUNTS, cmd, 0)]
    segments = cmd in ("GET", "PATCH", "CLEAR") ? parse_path(schema, typ, words[4]) : PathSegment[]
    if cmd == "SCHEMA"
        lines = [typ.name]
        schema_fields!(lines, schema, typ, [typ.name], 1)
        return lines
    elseif cmd == "ENCODE" || cmd == "SIZE"
        text = split(line, ' '; limit=3, keepempty=true)[3]
        p = LiteralParser(schema, text)
        m = parse_message!(p, typ)
        finish_literal(p)
        bytes = encode_message(m)
        cmd == "ENCODE" && return [hex_text(bytes)]
        parts = [string(length(bytes))]
        for f in typ.fields
            hasfieldvalue(m, f) && push!(parts, "$(f.name)=$(length(field_records(f, field_values(m, f))))")
        end
        return [join(parts, ' ')]
    elseif cmd == "EXPLAIN"
        isempty(data[1]) && return ["(empty)"]
        r = Reader(schema, data[1], true, String[])
        read_message(r, typ, 0, length(data[1]), 0)
        return r.lines
    elseif cmd == "MERGE"
        return text_message(schema, decode(schema, typ, vcat(data[1], data[2])))
    elseif cmd == "DIFF"
        messages = Message[]
        for (bytes, label) in zip(data, ("first", "second"))
            try
                push!(messages, decode(schema, typ, bytes))
            catch err
                err isa CommandError || rethrow()
                fail("$(err.reason) in $label")
            end
        end
        lines = String[]
        compare_messages!(lines, schema, messages[1], messages[2])
        return isempty(lines) ? ["SAME"] : lines
    end
    m = decode(schema, typ, data[1])
    cmd == "DECODE" && return text_message(schema, m)
    cmd == "LITERAL" && return [message_notation(schema, m)]
    cmd == "JSON" && return [json_message(schema, m)]
    cmd == "CANON" && return [hex_text(encode_message(m))]
    lastseg = last(segments)
    f = lastseg.field
    if cmd == "GET"
        target = follow(m, segments[1:end-1])
        vs = isnothing(target) ? Any[] : field_values(target, f)
        whole(lastseg) && return [list_notation(schema, f, vs)]
        i = item_position(lastseg)
        return [i <= length(vs) ? value_notation(schema, f, vs[i]) : "(none)"]
    elseif cmd == "PATCH"
        text = split(line, ' '; limit=5, keepempty=true)[5]
        p = LiteralParser(schema, text)
        value = whole(lastseg) ? parse_list!(p, f) : parse_element!(p, f)
        finish_literal(p)
        target = m
        for seg in segments[1:end-1]
            target = patch_child!(schema, target, seg)
        end
        if whole(lastseg)
            set_items!(target, f, value)
        elseif f.repeated
            vs = field_values(target, f)
            i = item_position(lastseg)
            i > length(vs) && fail("index out of range")
            vs[i] = value
        else
            remove_group!(target, f)
            target.values[f.number] = value
        end
    elseif cmd == "CLEAR"
        target = follow(m, segments[1:end-1])
        if !isnothing(target)
            if isnothing(lastseg.index)
                delete!(target.values, f.number)
            else
                vs = field_values(target, f)
                i = item_position(lastseg)
                if i <= length(vs)
                    deleteat!(vs, i)
                    set_items!(target, f, vs)
                end
            end
        end
    end
    check_required(m)
    return [hex_text(encode_message(m))]
end
function execute(schema, line)
    try
        return process_command(schema, line)
    catch err
        err isa CommandError || rethrow()
        return ["ERROR $(err.reason)"]
    end
end
function main()
    schema = read_schema(stdin)
    n = parse(Int, readline())
    for _ in 1:n
        for line in execute(schema, readline())
            println(line)
        end
    end
end

main()
