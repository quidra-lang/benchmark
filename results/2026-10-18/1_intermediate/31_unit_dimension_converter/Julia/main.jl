const Fraction = Rational{Int64}
const Dimension = NTuple{7,Int64}
const ONE = Int64(1) // Int64(1)
const ZERO = Int64(0) // Int64(1)
const DIMENSIONLESS = ntuple(_ -> Int64(0), 7)
const BASE_NAMES = ("kg", "m", "s", "A", "K", "mol", "cd")

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))

struct Quantity
    value::Fraction
    dimension::Dimension
end
Quantity(value::Fraction = ONE) = Quantity(value, DIMENSIONLESS)

function fraction_text(value::Fraction)
    n, d = numerator(value), denominator(value)
    d == 1 ? string(n) : "$n/$d"
end
function decimal_text(value::Fraction)
    n, d = abs(numerator(value)), denominator(value)
    whole = div(n, d)
    tail = div(rem(n, d) * 1_000_000, d)
    string(value < ZERO ? "-" : "", whole, '.', lpad(string(tail), 6, '0'))
end
notation(value::Fraction, unit::AbstractString) = "$(fraction_text(value)) $unit ($(decimal_text(value)))"

function scalar_power(value::Fraction, exponent::Integer)
    factor = exponent < 0 ? ONE / value : value
    result = ONE
    for _ in 1:abs(exponent)
        result *= factor
    end
    result
end
function parse_number(text::AbstractString)::Fraction
    occursin(r"^-?[0-9]+([./][0-9]+)?$", text) || fail("BAD NUMBER $text")
    negative = startswith(text, "-")
    body = negative ? text[2:end] : text
    value = if occursin('/', body)
        parts = split(body, '/')
        divisor = parse(Int64, parts[2]; base = 10)
        divisor != 0 || fail("BAD NUMBER $text")
        parse(Int64, parts[1]; base = 10) // divisor
    elseif occursin('.', body)
        parts = split(body, '.')
        divisor = Int64(1)
        for _ in 1:length(parts[2])
            divisor *= 10
        end
        (parse(Int64, parts[1]; base = 10) * divisor + parse(Int64, parts[2]; base = 10)) // divisor
    else
        parse(Int64, body; base = 10) // Int64(1)
    end
    negative ? -value : value
end
function checked_exponent(text::AbstractString)
    value = parse(Int64, text; base = 10)
    value in (-3, -2, -1, 1, 2, 3) || fail("BAD EXPONENT $text")
    value
end
function check_name(name::String, variable::Bool = false)
    if !occursin(r"^[A-Za-z]{1,12}$", name) || (variable && name in ("abs", "sqrt", "min", "max"))
        fail("BAD NAME $name")
    end
end
combine(a::Dimension, b::Dimension, sign::Int64 = Int64(1)) = ntuple(i -> a[i] + sign * b[i], 7)
scaled(dimension::Dimension, multiplier::Int64) = ntuple(i -> dimension[i] * multiplier, 7)
function dimension_text(dimension::Dimension)
    terms = String[]
    for i in eachindex(dimension)
        exponent = dimension[i]
        exponent == 0 && continue
        push!(terms, exponent == 1 ? BASE_NAMES[i] : "$(BASE_NAMES[i])^$exponent")
    end
    isempty(terms) ? "1" : join(terms, ' ')
end
function match_dimensions(first::Dimension, second::Dimension)
    first == second || fail("DIMENSION MISMATCH $(dimension_text(first)) vs $(dimension_text(second))")
end
const KINDS = Pair{String,Dimension}[
    "dimensionless" => (0,0,0,0,0,0,0), "length" => (0,1,0,0,0,0,0), "mass" => (1,0,0,0,0,0,0),
    "time" => (0,0,1,0,0,0,0), "current" => (0,0,0,1,0,0,0), "temperature" => (0,0,0,0,1,0,0),
    "amount" => (0,0,0,0,0,1,0), "luminous_intensity" => (0,0,0,0,0,0,1), "area" => (0,2,0,0,0,0,0),
    "volume" => (0,3,0,0,0,0,0), "speed" => (0,1,-1,0,0,0,0), "acceleration" => (0,1,-2,0,0,0,0),
    "density" => (1,-3,0,0,0,0,0), "momentum" => (1,1,-1,0,0,0,0), "force" => (1,1,-2,0,0,0,0),
    "energy" => (1,2,-2,0,0,0,0), "power" => (1,2,-3,0,0,0,0), "pressure" => (1,-1,-2,0,0,0,0),
    "frequency" => (0,0,-1,0,0,0,0), "charge" => (0,0,1,1,0,0,0), "voltage" => (1,2,-3,-1,0,0,0),
    "resistance" => (1,2,-3,-2,0,0,0), "conductance" => (-1,-2,3,2,0,0,0), "capacitance" => (-1,-2,4,2,0,0,0),
    "magnetic_flux" => (1,2,-2,-1,0,0,0), "flux_density" => (1,0,-2,-1,0,0,0), "inductance" => (1,2,-2,-2,0,0,0),
    "illuminance" => (0,-2,0,0,0,0,1), "catalytic_activity" => (0,0,-1,0,0,1,0),
]
function kind_dimension(name::String)::Union{Dimension,Nothing}
    for (label, dimension) in KINDS
        label == name && return dimension
    end
    nothing
end
function kind_name(dimension::Dimension)
    for (name, known) in KINDS
        dimension == known && return name
    end
    "-"
end

struct Definition
    value::Fraction
    expression::String
end
struct UnitEntry
    symbol::String
    quantity::Quantity
    prefixable::Bool
    definition::Union{Definition,Nothing}
end
mutable struct Database
    units::Vector{UnitEntry}
    variables::Dict{String,Quantity}
end
function new_database()
    rows = [
        ("m",1,1,"length",true), ("g",1,1000,"mass",true), ("s",1,1,"time",true),
        ("A",1,1,"current",true), ("K",1,1,"temperature",true), ("mol",1,1,"amount",true),
        ("cd",1,1,"luminous_intensity",true), ("N",1,1,"force",true), ("J",1,1,"energy",true),
        ("W",1,1,"power",true), ("Pa",1,1,"pressure",true), ("Hz",1,1,"frequency",true),
        ("C",1,1,"charge",true), ("V",1,1,"voltage",true), ("ohm",1,1,"resistance",true),
        ("S",1,1,"conductance",true), ("F",1,1,"capacitance",true), ("Wb",1,1,"magnetic_flux",true),
        ("T",1,1,"flux_density",true), ("H",1,1,"inductance",true), ("lx",1,1,"illuminance",true),
        ("kat",1,1,"catalytic_activity",true), ("L",1,1000,"volume",true), ("t",1000,1,"mass",false),
        ("min",60,1,"time",false), ("h",3600,1,"time",false), ("day",86400,1,"time",false),
        ("in",127,5000,"length",false), ("ft",381,1250,"length",false), ("yd",1143,1250,"length",false),
        ("mi",201168,125,"length",false), ("nmi",1852,1,"length",false), ("ha",10000,1,"area",false),
        ("kn",463,900,"speed",false), ("bar",100000,1,"pressure",true), ("atm",101325,1,"pressure",false),
        ("Torr",20265,152,"pressure",false), ("cal",523,125,"energy",true), ("Wh",3600,1,"energy",true),
        ("Ah",3600,1,"charge",true), ("dC",1,1,"temperature",false), ("dF",5,9,"temperature",false),
    ]
    units = UnitEntry[]
    for (symbol, n, d, kind, prefixable) in rows
        dimension = kind_dimension(kind)::Dimension
        push!(units, UnitEntry(symbol, Quantity(Int64(n) // Int64(d), dimension), prefixable, nothing))
    end
    Database(units, Dict{String,Quantity}())
end
const PREFIXES = ["G" => 1_000_000_000//1, "M" => 1_000_000//1, "k" => 1000//1,
                  "h" => 100//1, "da" => 10//1, "d" => 1//10, "c" => 1//100,
                  "m" => 1//1000, "u" => 1//1_000_000, "n" => 1//1_000_000_000]
function resolve(database::Database, name::String)::Union{Quantity,Nothing}
    for unit in database.units
        unit.symbol == name && return unit.quantity
    end
    for (prefix, factor) in PREFIXES
        startswith(name, prefix) || continue
        rest = name[length(prefix)+1:end]
        for unit in @view database.units[1:42]
            if unit.prefixable && unit.symbol == rest
                return Quantity(factor * unit.quantity.value, unit.quantity.dimension)
            end
        end
    end
    nothing
end
function simplified(database::Database, dimension::Dimension)
    for unit in database.units
        unit.quantity.value == ONE && unit.quantity.dimension == dimension && return unit.symbol
    end
    dimension_text(dimension)
end
function selected_units(database::Database, dimension::Dimension)
    result = filter(unit -> unit.quantity.dimension == dimension, database.units)
    sort!(result; by = unit -> (unit.quantity.value, unit.symbol))
end

@enum TokenKind NAME_TOKEN NUMBER_TOKEN UNIT_TOKEN SYMBOL_TOKEN INVALID_TOKEN END_TOKEN
struct Token
    kind::TokenKind
    text::String
    position::Int
end
mutable struct Parser
    source::String
    tokens::Vector{Token}
    position::Int
end
letter(c::Char) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
digit(c::Char) = '0' <= c <= '9'
function tokenize(source::String, quantity_mode::Bool)
    characters = collect(source)
    tokens = Token[]
    count = length(characters)
    position = 1
    while position <= count
        start = position
        character = characters[position]
        position += 1
        kind = INVALID_TOKEN
        if letter(character)
            kind = NAME_TOKEN
            while position <= count && letter(characters[position])
                position += 1
            end
        elseif digit(character)
            kind = NUMBER_TOKEN
            while position <= count && digit(characters[position])
                position += 1
            end
            if quantity_mode && position < count && characters[position] == '.' && digit(characters[position+1])
                position += 1
                while position <= count && digit(characters[position])
                    position += 1
                end
            end
        elseif quantity_mode && character == '['
            closing = position
            while closing <= count && characters[closing] != ']'
                closing += 1
            end
            if position < closing <= count
                kind = UNIT_TOKEN
                position = closing + 1
            end
        elseif character in (quantity_mode ? "+-*/^()," : "*/^()-")
            kind = SYMBOL_TOKEN
        end
        push!(tokens, Token(kind, source[start:position-1], start))
    end
    push!(tokens, Token(END_TOKEN, "", count + 1))
    Parser(source, tokens, 1)
end
current(parser::Parser) = parser.tokens[parser.position]
function syntax_error(parser::Parser)
    token = current(parser)
    position = token.kind == END_TOKEN ? "END" : string(token.position)
    fail("SYNTAX $(parser.source) AT $position")
end
function take_token!(parser::Parser, text::String)
    current(parser).text == text || return false
    parser.position += 1
    true
end
expect!(parser::Parser, text::String) = take_token!(parser, text) || syntax_error(parser)
function parse_exponent!(parser::Parser)
    sign = take_token!(parser, "-") ? "-" : ""
    token = current(parser)
    token.kind == NUMBER_TOKEN && !occursin('.', token.text) || syntax_error(parser)
    parser.position += 1
    sign * token.text
end

abstract type UnitExpr end
struct UnitName <: UnitExpr
    name::String
end
struct UnitNumber <: UnitExpr
    value::Int64
end
struct UnitPower <: UnitExpr
    child::UnitExpr
    exponent::String
end
struct UnitProduct <: UnitExpr
    terms::Vector{Pair{Char,UnitExpr}}
end
function unit_term!(parser::Parser)::UnitExpr
    token = current(parser)
    result = if token.kind == NAME_TOKEN
        parser.position += 1
        UnitName(token.text)
    elseif token.kind == NUMBER_TOKEN && first(token.text) != '0'
        parser.position += 1
        UnitNumber(parse(Int64, token.text; base = 10))
    elseif take_token!(parser, "(")
        inner = unit_expression!(parser)
        expect!(parser, ")")
        inner
    else
        syntax_error(parser)
    end
    take_token!(parser, "^") ? UnitPower(result, parse_exponent!(parser)) : result
end
function unit_expression!(parser::Parser)
    terms = Pair{Char,UnitExpr}['*' => unit_term!(parser)]
    while current(parser).text in ("*", "/")
        operation = first(current(parser).text)
        parser.position += 1
        push!(terms, operation => unit_term!(parser))
    end
    UnitProduct(terms)
end
function validate_unit(database::Database, tree::UnitExpr)
    if tree isa UnitName
        isnothing(resolve(database, tree.name)) && fail("UNKNOWN UNIT $(tree.name)")
    elseif tree isa UnitPower
        validate_unit(database, tree.child)
        checked_exponent(tree.exponent)
    elseif tree isa UnitProduct
        for (_, term) in tree.terms
            validate_unit(database, term)
        end
    end
    nothing
end
evaluate_unit(database::Database, tree::UnitName) = resolve(database, tree.name)::Quantity
evaluate_unit(::Database, tree::UnitNumber) = Quantity(tree.value // Int64(1))
function evaluate_unit(database::Database, tree::UnitPower)
    value = evaluate_unit(database, tree.child)
    exponent = parse(Int64, tree.exponent; base = 10)
    Quantity(scalar_power(value.value, exponent), scaled(value.dimension, exponent))
end
function evaluate_unit(database::Database, tree::UnitProduct)
    result = Quantity()
    for (operation, term) in tree.terms
        right = evaluate_unit(database, term)
        result = operation == '*' ? Quantity(result.value * right.value, combine(result.dimension, right.dimension)) :
                                   Quantity(result.value / right.value, combine(result.dimension, right.dimension, Int64(-1)))
    end
    result
end
function parse_unit(database::Database, source::String)
    parser = tokenize(source, false)
    tree = unit_expression!(parser)
    current(parser).kind == END_TOKEN || syntax_error(parser)
    validate_unit(database, tree)
    tree
end
unit_value(database::Database, source::String) = evaluate_unit(database, parse_unit(database, source))

mutable struct Reduced
    coefficient::Fraction
    names::Vector{String}
    powers::Vector{Int64}
end
reduce_unit(tree::UnitName) = Reduced(ONE, [tree.name], Int64[1])
reduce_unit(tree::UnitNumber) = Reduced(tree.value // Int64(1), String[], Int64[])
function reduce_unit(tree::UnitPower)
    result = reduce_unit(tree.child)
    exponent = parse(Int64, tree.exponent; base = 10)
    result.coefficient = scalar_power(result.coefficient, exponent)
    result.powers .*= exponent
    result
end
function reduce_unit(tree::UnitProduct)
    result = Reduced(ONE, String[], Int64[])
    for (operation, term) in tree.terms
        right = reduce_unit(term)
        sign = operation == '*' ? Int64(1) : Int64(-1)
        result.coefficient = sign == 1 ? result.coefficient * right.coefficient : result.coefficient / right.coefficient
        for i in eachindex(right.names)
            index = findfirst(==(right.names[i]), result.names)
            if isnothing(index)
                push!(result.names, right.names[i])
                push!(result.powers, sign * right.powers[i])
            else
                result.powers[index] += sign * right.powers[i]
            end
        end
    end
    result
end
function reduced_text(tree::UnitExpr)
    result = reduce_unit(tree)
    parts = result.coefficient == ONE ? String[] : [fraction_text(result.coefficient)]
    for i in eachindex(result.names)
        exponent = result.powers[i]
        exponent == 0 && continue
        push!(parts, exponent == 1 ? result.names[i] : "$(result.names[i])^$exponent")
    end
    isempty(parts) ? "1" : join(parts, ' ')
end

abstract type QuantityExpr end
struct Literal <: QuantityExpr
    text::String
    unit::Union{String,Nothing}
end
struct Variable <: QuantityExpr
    name::String
end
struct Power <: QuantityExpr
    child::QuantityExpr
    exponent::String
end
struct Negative <: QuantityExpr
    child::QuantityExpr
end
struct Binary <: QuantityExpr
    operation::Char
    left::QuantityExpr
    right::QuantityExpr
end
struct Call <: QuantityExpr
    name::String
    arguments::Vector{QuantityExpr}
end
function quantity_primary!(parser::Parser)::QuantityExpr
    token = current(parser)
    result = if token.kind == NUMBER_TOKEN
        parser.position += 1
        unit = nothing
        if current(parser).kind == UNIT_TOKEN
            text = current(parser).text
            parser.position += 1
            unit = text[2:end-1]
        end
        Literal(token.text, unit)
    elseif token.kind == UNIT_TOKEN
        parser.position += 1
        Literal("1", token.text[2:end-1])
    elseif token.kind == NAME_TOKEN
        parser.position += 1
        if take_token!(parser, "(")
            arguments = QuantityExpr[quantity_expression!(parser)]
            while take_token!(parser, ",")
                push!(arguments, quantity_expression!(parser))
            end
            expect!(parser, ")")
            Call(token.text, arguments)
        else
            Variable(token.text)
        end
    elseif take_token!(parser, "(")
        inner = quantity_expression!(parser)
        expect!(parser, ")")
        inner
    else
        syntax_error(parser)
    end
    take_token!(parser, "^") ? Power(result, parse_exponent!(parser)) : result
end
quantity_unary!(parser::Parser)::QuantityExpr = take_token!(parser, "-") ? Negative(quantity_unary!(parser)) : quantity_primary!(parser)
function quantity_product!(parser::Parser)::QuantityExpr
    result = quantity_unary!(parser)
    while current(parser).text in ("*", "/")
        operation = first(current(parser).text)
        parser.position += 1
        right = quantity_unary!(parser)
        result = Binary(operation, result, right)
    end
    result
end
function quantity_expression!(parser::Parser)::QuantityExpr
    result = quantity_product!(parser)
    while current(parser).text in ("+", "-")
        operation = first(current(parser).text)
        parser.position += 1
        right = quantity_product!(parser)
        result = Binary(operation, result, right)
    end
    result
end
function integer_sqrt(value::Int64)
    value < 2 && return value
    current_value = value
    following = div(value + 1, 2)
    while following < current_value
        current_value = following
        following = div(current_value + div(value, current_value), 2)
    end
    current_value
end
function evaluate_quantity(database::Database, tree::Literal)
    isnothing(tree.unit) && return Quantity(parse_number(tree.text))
    unit = unit_value(database, tree.unit)
    Quantity(parse_number(tree.text) * unit.value, unit.dimension)
end
function evaluate_quantity(database::Database, tree::Variable)
    haskey(database.variables, tree.name) || fail("UNKNOWN VARIABLE $(tree.name)")
    database.variables[tree.name]
end
function evaluate_quantity(database::Database, tree::Negative)
    value = evaluate_quantity(database, tree.child)
    Quantity(-value.value, value.dimension)
end
function evaluate_quantity(database::Database, tree::Power)
    value = evaluate_quantity(database, tree.child)
    exponent = checked_exponent(tree.exponent)
    value.value == ZERO && exponent < 0 && fail("DIVISION BY ZERO")
    Quantity(scalar_power(value.value, exponent), scaled(value.dimension, exponent))
end
function evaluate_quantity(database::Database, tree::Binary)
    left = evaluate_quantity(database, tree.left)
    right = evaluate_quantity(database, tree.right)
    if tree.operation in ('+', '-')
        match_dimensions(left.dimension, right.dimension)
        value = tree.operation == '+' ? left.value + right.value : left.value - right.value
        return Quantity(value, left.dimension)
    end
    tree.operation == '*' && return Quantity(left.value * right.value, combine(left.dimension, right.dimension))
    right.value == ZERO && fail("DIVISION BY ZERO")
    Quantity(left.value / right.value, combine(left.dimension, right.dimension, Int64(-1)))
end
function evaluate_quantity(database::Database, tree::Call)
    tree.name in ("abs", "sqrt", "min", "max") || fail("UNKNOWN FUNCTION $(tree.name)")
    required = tree.name in ("abs", "sqrt") ? 1 : 2
    length(tree.arguments) == required || fail("BAD ARGUMENTS $(tree.name)")
    first_value = evaluate_quantity(database, tree.arguments[1])
    tree.name == "abs" && return Quantity(abs(first_value.value), first_value.dimension)
    if tree.name == "sqrt"
        first_value.value < ZERO && fail("NEGATIVE ROOT")
        all(iseven, first_value.dimension) || fail("ODD DIMENSION $(dimension_text(first_value.dimension))")
        n, d = numerator(first_value.value), denominator(first_value.value)
        root_n, root_d = integer_sqrt(n), integer_sqrt(d)
        root_n * root_n == n && root_d * root_d == d || fail("NOT EXACT")
        return Quantity(root_n // root_d, ntuple(i -> div(first_value.dimension[i], 2), 7))
    end
    second_value = evaluate_quantity(database, tree.arguments[2])
    match_dimensions(first_value.dimension, second_value.dimension)
    take_first = tree.name == "min" ? first_value.value <= second_value.value : first_value.value >= second_value.value
    take_first ? first_value : second_value
end
function quantity_value(database::Database, source::String)
    parser = tokenize(source, true)
    tree = quantity_expression!(parser)
    current(parser).kind == END_TOKEN || syntax_error(parser)
    evaluate_quantity(database, tree)
end

const COMMANDS = ("DEFINE", "UNDEF", "DEFS", "CONVERT", "INVERT", "DIM", "REDUCE", "SIMPLIFY",
                  "ADD", "SUB", "MUL", "DIV", "TEMP", "COMPARE", "LIST", "TABLE", "AUTO", "SPLIT",
                  "LET", "EVAL", "VARS")
function execute!(database::Database, line::String)::Vector{String}
    words = String.(split(line))
    command = words[1]
    command in COMMANDS || fail("UNKNOWN COMMAND $command")
    if command == "DEFINE"
        name = words[2]
        check_name(name)
        value = parse_number(words[4])
        unit = unit_value(database, words[5])
        if !isnothing(kind_dimension(name)) || !isnothing(resolve(database, name))
            fail("NAME TAKEN $name")
        end
        value > ZERO || fail("NOT POSITIVE $(words[4])")
        result = Quantity(value * unit.value, unit.dimension)
        push!(database.units, UnitEntry(name, result, false, Definition(value, words[5])))
        return ["DEFINE $name factor=$(fraction_text(result.value)) dim=$(dimension_text(result.dimension)) kind=$(kind_name(result.dimension))"]
    elseif command == "UNDEF"
        name = words[2]
        index = findfirst(unit -> unit.symbol == name, database.units)
        isnothing(index) && fail("NOT DEFINED $name")
        index <= 42 && fail("BUILTIN UNIT $name")
        deleteat!(database.units, index)
        return ["UNDEF $name"]
    elseif command == "DEFS"
        output = ["DEFS count=$(length(database.units) - 42)"]
        for unit in @view database.units[43:end]
            definition = unit.definition::Definition
            push!(output, "DEF $(unit.symbol) = $(fraction_text(definition.value)) $(definition.expression) factor=$(fraction_text(unit.quantity.value)) dim=$(dimension_text(unit.quantity.dimension))")
        end
        return output
    elseif command in ("CONVERT", "INVERT")
        value = parse_number(words[2])
        source = unit_value(database, words[3])
        target = unit_value(database, words[5])
        if command == "INVERT"
            if source.dimension == DIMENSIONLESS || combine(source.dimension, target.dimension) != DIMENSIONLESS
                fail("NOT RECIPROCAL $(dimension_text(source.dimension)) vs $(dimension_text(target.dimension))")
            end
            value == ZERO && fail("DIVISION BY ZERO")
        else
            match_dimensions(source.dimension, target.dimension)
        end
        result = value * source.value
        command == "INVERT" && (result = ONE / result)
        return ["$command $(fraction_text(value)) $(words[3]) = $(notation(result / target.value, words[5]))"]
    elseif command in ("DIM", "REDUCE", "SIMPLIFY")
        tree = parse_unit(database, words[2])
        unit = evaluate_unit(database, tree)
        result_text = if command == "DIM"
            "$(dimension_text(unit.dimension)) factor=$(fraction_text(unit.value)) kind=$(kind_name(unit.dimension))"
        elseif command == "REDUCE"
            reduced_text(tree)
        else
            notation(unit.value, simplified(database, unit.dimension))
        end
        return ["$command $(words[2]) = $result_text"]
    elseif command in ("ADD", "SUB", "MUL", "DIV", "COMPARE")
        a = parse_number(words[2])
        first_unit = unit_value(database, words[3])
        b = parse_number(words[4])
        second_unit = unit_value(database, words[5])
        has_target = length(words) == 7
        target = has_target ? unit_value(database, words[7]) : first_unit
        prefix = "$command $(fraction_text(a)) $(words[3])"
        suffix = "$(fraction_text(b)) $(words[5])"
        if command in ("ADD", "SUB", "COMPARE")
            match_dimensions(first_unit.dimension, second_unit.dimension)
            has_target && match_dimensions(first_unit.dimension, target.dimension)
            left = a * first_unit.value
            right = b * second_unit.value
            if command == "COMPARE"
                relation = left < right ? "<" : left > right ? ">" : "="
                ratio = right == ZERO ? "undefined" : fraction_text(left / right)
                return ["$prefix $relation $suffix ratio=$ratio"]
            end
            operation = command == "ADD" ? "+" : "-"
            result = command == "ADD" ? left + right : left - right
            label = has_target ? words[7] : words[3]
            return ["$prefix $operation $suffix = $(notation(result / target.value, label))"]
        end
        multiply = command == "MUL"
        dimension = combine(first_unit.dimension, second_unit.dimension, multiply ? Int64(1) : Int64(-1))
        !multiply && b == ZERO && fail("DIVISION BY ZERO")
        has_target && match_dimensions(dimension, target.dimension)
        raw = multiply ? a * b : a / b
        left = a * first_unit.value
        right = b * second_unit.value
        coherent = multiply ? left * right : left / right
        operation = multiply ? "*" : "/"
        prefix = "$prefix $operation $suffix ="
        has_target && return ["$prefix $(notation(coherent / target.value, words[7]))"]
        right_unit = words[5]
        if !multiply && (occursin('*', right_unit) || occursin('/', right_unit))
            right_unit = "($right_unit)"
        end
        combined = words[3] * operation * right_unit
        return ["$prefix $(fraction_text(raw)) $combined = $(notation(coherent, simplified(database, dimension)))"]
    elseif command == "TEMP"
        value = parse_number(words[2])
        for scale in (words[3], words[5])
            scale in ("C", "F", "K", "R") || fail("UNKNOWN SCALE $scale")
        end
        kelvin = if words[3] == "C"
            value + 5463//20
        elseif words[3] == "F"
            (value + 45967//100) * 5 / 9
        elseif words[3] == "R"
            value * 5 / 9
        else
            value
        end
        kelvin < ZERO && fail("BELOW ABSOLUTE ZERO")
        result = if words[5] == "C"
            kelvin - 5463//20
        elseif words[5] == "F"
            kelvin * 9 / 5 - 45967//100
        elseif words[5] == "R"
            kelvin * 9 / 5
        else
            kelvin
        end
        return ["TEMP $(fraction_text(value)) $(words[3]) = $(notation(result, words[5]))"]
    elseif command in ("LIST", "TABLE")
        value = ONE
        unit = Quantity()
        dimension = if command == "TABLE"
            value = parse_number(words[2])
            unit = unit_value(database, words[3])
            unit.dimension
        else
            known = kind_dimension(words[2])
            isnothing(known) ? unit_value(database, words[2]).dimension : known
        end
        selected = selected_units(database, dimension)
        output = if command == "TABLE"
            ["TABLE $(fraction_text(value)) $(words[3]) dim=$(dimension_text(dimension)) count=$(length(selected))"]
        else
            ["LIST $(words[2]) dim=$(dimension_text(dimension)) kind=$(kind_name(dimension)) count=$(length(selected))"]
        end
        for item in selected
            if command == "TABLE"
                push!(output, "ROW $(notation((value * unit.value) / item.quantity.value, item.symbol))")
            else
                origin = isnothing(item.definition) ? "builtin" : "user"
                prefix_flag = item.prefixable ? "yes" : "no"
                push!(output, "UNIT $(item.symbol) factor=$(fraction_text(item.quantity.value)) origin=$origin prefix=$prefix_flag")
            end
        end
        return output
    elseif command == "AUTO"
        value = parse_number(words[2])
        unit = unit_value(database, words[3])
        index = findfirst(item -> item.prefixable && item.quantity.dimension == unit.dimension, @view database.units[1:42])
        isnothing(index) && fail("NO PREFIXABLE UNIT $(dimension_text(unit.dimension))")
        reference = database.units[index]
        scaled_value = (value * unit.value) / reference.quantity.value
        magnitude = abs(scaled_value)
        exponent = 0
        if magnitude >= ONE
            while exponent < 9 && magnitude >= scalar_power(10//1, exponent + 3)
                exponent += 3
            end
        elseif magnitude > ZERO
            while exponent > -9 && magnitude < scalar_power(10//1, exponent)
                exponent -= 3
            end
        end
        prefix = ("n", "u", "m", "", "k", "M", "G")[div(exponent + 9, 3) + 1]
        label = prefix * reference.symbol
        return ["AUTO $(fraction_text(value)) $(words[3]) = $(notation(scaled_value / scalar_power(10//1, exponent), label))"]
    elseif command == "SPLIT"
        value = parse_number(words[2])
        unit = unit_value(database, words[3])
        parts = String.(split(words[5], ','))
        targets = [unit_value(database, part) for part in parts]
        value < ZERO && fail("NEGATIVE VALUE")
        for target in targets
            match_dimensions(unit.dimension, target.dimension)
        end
        for i in 1:length(targets)-1
            targets[i].value > targets[i+1].value || fail("UNIT ORDER")
        end
        remaining = value * unit.value
        pieces = String[]
        for i in 1:length(parts)-1
            quotient = remaining / targets[i].value
            whole = div(numerator(quotient), denominator(quotient))
            remaining -= whole * targets[i].value
            push!(pieces, "$whole $(parts[i])")
        end
        push!(pieces, notation(remaining / targets[end].value, parts[end]))
        return ["SPLIT $(fraction_text(value)) $(words[3]) = $(join(pieces, ' '))"]
    elseif command == "LET"
        check_name(words[2], true)
        result = quantity_value(database, words[4])
        database.variables[words[2]] = result
        return ["LET $(words[2]) = $(notation(result.value, simplified(database, result.dimension)))"]
    elseif command == "EVAL"
        result = quantity_value(database, words[2])
        value = result.value
        label = simplified(database, result.dimension)
        if length(words) == 4
            unit = unit_value(database, words[4])
            match_dimensions(result.dimension, unit.dimension)
            value /= unit.value
            label = words[4]
        end
        return ["EVAL $(words[2]) = $(notation(value, label))"]
    else
        names = sort!(collect(keys(database.variables)))
        output = ["VARS count=$(length(names))"]
        for name in names
            result = database.variables[name]
            push!(output, "VAR $name = $(notation(result.value, simplified(database, result.dimension)))")
        end
        return output
    end
end

function main()
    command_count = parse(Int, readline())
    database = new_database()
    for _ in 1:command_count
        line = readline()
        output = try
            execute!(database, line)
        catch problem
            problem isa CommandError || rethrow()
            ["ERROR $(problem.message)"]
        end
        for line in output
            println(line)
        end
    end
end
main()
