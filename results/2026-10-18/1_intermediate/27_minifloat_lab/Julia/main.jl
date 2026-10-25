@enum Mode::UInt8 RNE RNA RTZ RUP RDN
@enum Classification::UInt8 ZERO SUBNORMAL NORMAL INFINITY QNAN SNAN
@enum Operation::UInt8 ADD SUB MUL DIV SQRT FMA

const INVALID = UInt8(1)
const DIVBYZERO = UInt8(2)
const OVERFLOW = UInt8(4)
const UNDERFLOW = UInt8(8)
const INEXACT = UInt8(16)
const MODES = Dict(string(mode) => mode for mode in instances(Mode))
const OPERATIONS = Dict(string(operation) => operation for operation in instances(Operation))
const TYPES = Dict{String,Tuple{Int64,Int64}}("I8" => (-128, 127), "U8" => (0, 255), "I16" => (-32768, 32767),
                                           "U16" => (0, 65535), "I32" => (-2147483648, 2147483647), "U32" => (0, 4294967295))

struct CommandError <: Exception
    message::String
end
fail(message) = throw(CommandError(message))
line(output::IO, values...) = println(output, join(values, ' '))

struct Exact
    n::Int64
    e::Int
    d::Int64
    negative::Bool
    function Exact(n::Integer, e::Int = 0, d::Integer = 1, negative::Bool = false)
        numerator, denominator = Int64(n), Int64(d)
        if numerator == 0
            return new(0, 0, 1, negative)
        end
        factor = gcd(numerator, denominator)
        numerator ÷= factor
        denominator ÷= factor
        shift = trailing_zeros(numerator)
        numerator >>= shift
        e += shift
        shift = trailing_zeros(denominator)
        denominator >>= shift
        e -= shift
        new(numerator, e, denominator, negative)
    end
end
negated(value::Exact) = Exact(value.n, value.e, value.d, !value.negative)
product(a::Exact, b::Exact) = Exact(a.n * b.n, a.e + b.e, a.d * b.d, xor(a.negative, b.negative))

function scaled(value::Exact, quantum::Int)
    shift = value.e - quantum
    shift >= 0 ? (value.n << shift, value.d) : (value.n, value.d << -shift)
end
function log_two_floor(value::Exact)
    power = leading_zeros(value.d) - leading_zeros(value.n)
    below = power >= 0 ? value.n < (value.d << power) : (value.n << -power) < value.d
    value.e + power - Int(below)
end
function fraction_text(value::Exact)
    value.n == 0 && return "0"
    numerator, denominator = scaled(value, 0)
    string(value.negative ? "-" : "", numerator, denominator == 1 ? "" : "/$denominator")
end
function decimal_text(value::Exact; keep_zero_sign::Bool = false)
    numerator, denominator = scaled(value, 0)
    output = IOBuffer()
    value.negative && (value.n != 0 || keep_zero_sign) && print(output, '-')
    print(output, numerator ÷ denominator)
    remainder = numerator % denominator
    remainder != 0 && print(output, '.')
    while remainder != 0
        remainder *= 10
        print(output, remainder ÷ denominator)
        remainder %= denominator
    end
    String(take!(output))
end
function exact_sum(terms::Vector{Exact}, mode::Mode)
    nonzero = filter(term -> term.n != 0, terms)
    if isempty(nonzero)
        same = all(term -> term.negative == terms[1].negative, terms)
        return Exact(0, 0, 1, same ? terms[1].negative : mode == RDN)
    end
    exponent = minimum(term.e for term in nonzero)
    total = sum((term.negative ? -term.n : term.n) << (term.e - exponent) for term in nonzero)
    Exact(abs(total), exponent, 1, total < 0 || (total == 0 && mode == RDN))
end

struct Units
    value::Int64
    inexact::Bool
    halfway::Int
end
function integer_sqrt(value::Int64)
    value == 0 && return Int64(0)
    root, next = value, (value + 1) ÷ 2
    while next < root
        root = next
        next = (root + value ÷ root) ÷ 2
    end
    root
end
function quantize(value::Exact, exponent::Int, square_root::Bool)
    numerator, denominator = scaled(value, square_root ? 2 * exponent : exponent)
    if !square_root
        remainder = numerator % denominator
        return Units(numerator ÷ denominator, remainder != 0, cmp(remainder, denominator - remainder))
    end
    integer = integer_sqrt(numerator ÷ denominator)
    midpoint = 2 * integer + 1
    Units(integer, integer * integer * denominator != numerator, cmp(4 * numerator, midpoint * midpoint * denominator))
end
function rounded_units(units::Units, mode::Mode, negative::Bool)
    increment = if mode == RNE
        units.halfway > 0 || (units.halfway == 0 && isodd(units.value))
    elseif mode == RNA
        units.halfway >= 0
    elseif mode == RUP
        units.inexact && !negative
    elseif mode == RDN
        units.inexact && negative
    else
        false
    end
    units.value + Int(increment)
end

struct Result
    pattern::Int
    flags::UInt8
end
Result(pattern::Int) = Result(pattern, UInt8(0))
struct InputValue
    pattern::Int
    number::Union{Nothing,Exact}
end
struct MiniFormat
    name::String
    e::Int
    m::Int
    w::Int
    bias::Int
    emin::Int
    emax::Int
    hidden::Int
    sign_bit::Int
    infinity::Int
    nan::Int
end
function MiniFormat(name::AbstractString, e::Int, m::Int)
    bias = (1 << (e - 1)) - 1
    hidden = 1 << m
    infinity = ((1 << e) - 1) * hidden
    MiniFormat(String(name), e, m, 1 + e + m, bias, 1 - bias, bias, hidden, 1 << (e + m), infinity, infinity + hidden ÷ 2)
end
function fields(format::MiniFormat, pattern::Int)
    exponent = (pattern & (format.sign_bit - 1)) >> format.m
    (negative = (pattern & format.sign_bit) != 0, exponent = exponent,
     fraction = pattern & (format.hidden - 1), q = (exponent == 0 ? format.emin : exponent - format.bias) - format.m)
end
function classification(format::MiniFormat, pattern::Int)
    magnitude = pattern & (format.sign_bit - 1)
    fraction = pattern & (format.hidden - 1)
    if magnitude >= format.infinity
        fraction == 0 && return INFINITY
        return fraction >= format.hidden ÷ 2 ? QNAN : SNAN
    end
    magnitude == 0 ? ZERO : magnitude < format.hidden ? SUBNORMAL : NORMAL
end
is_nan(format::MiniFormat, pattern::Int) = classification(format, pattern) in (QNAN, SNAN)
is_signaling(format::MiniFormat, pattern::Int) = classification(format, pattern) == SNAN
is_finite(format::MiniFormat, pattern::Int) = classification(format, pattern) in (ZERO, SUBNORMAL, NORMAL)
is_infinite(format::MiniFormat, pattern::Int) = classification(format, pattern) == INFINITY
is_zero(format::MiniFormat, pattern::Int) = (pattern & (format.sign_bit - 1)) == 0
zero_pattern(format::MiniFormat, negative::Bool) = negative ? format.sign_bit : 0
infinity_pattern(format::MiniFormat, negative::Bool) = zero_pattern(format, negative) + format.infinity
flip(format::MiniFormat, pattern::Int) = xor(pattern, format.sign_bit)
function pattern_exact(format::MiniFormat, pattern::Int)
    field = fields(format, pattern)
    Exact(field.fraction + (field.exponent == 0 ? 0 : format.hidden), field.q, 1, field.negative)
end
function bits_text(format::MiniFormat, pattern::Int)
    field = fields(format, pattern)
    string(Int(field.negative), '|', string(field.exponent; base = 2, pad = format.e), '|', string(field.fraction; base = 2, pad = format.m))
end
hex_text(format::MiniFormat, pattern::Int) = "0x" * uppercase(string(pattern; base = 16, pad = cld(format.w, 4)))
function value_text(format::MiniFormat, pattern::Int)
    is_nan(format, pattern) && return "nan"
    is_infinite(format, pattern) && return (fields(format, pattern).negative ? "-inf" : "inf")
    decimal_text(pattern_exact(format, pattern); keep_zero_sign = true)
end
function flags_text(flags::UInt8)
    names = ("invalid", "divbyzero", "overflow", "underflow", "inexact")
    raised = [name for (index, name) in enumerate(names) if (flags & (UInt8(1) << (index - 1))) != 0]
    "flags=" * (isempty(raised) ? "none" : join(raised, ','))
end
pattern_text(format::MiniFormat, pattern::Int) = "$(bits_text(format, pattern)) $(hex_text(format, pattern)) $(value_text(format, pattern))"
result_text(format::MiniFormat, result::Result) = "$(pattern_text(format, result.pattern)) $(flags_text(result.flags))"

function overflow_result(format::MiniFormat, mode::Mode, negative::Bool)
    infinite = mode in (RNE, RNA) || (mode == RUP && !negative) || (mode == RDN && negative)
    Result(zero_pattern(format, negative) + (infinite ? format.infinity : format.infinity - 1), OVERFLOW | INEXACT)
end
function round_exact(format::MiniFormat, value::Exact, mode::Mode; square_root::Bool = false)
    value.n == 0 && return Result(zero_pattern(format, value.negative))
    order = log_two_floor(value)
    square_root && (order = fld(order, 2))
    order > format.emax && return overflow_result(format, mode, value.negative)
    exponent = max(order, format.emin) - format.m
    units = quantize(value, exponent, square_root)
    n = rounded_units(units, mode, value.negative)
    if n == 2 * format.hidden
        n = Int64(format.hidden)
        exponent += 1
    end
    exponent > format.emax - format.m && return overflow_result(format, mode, value.negative)
    flags = units.inexact ? INEXACT : UInt8(0)
    if units.inexact && order < format.emin
        tiny = order < format.emin - 1 || rounded_units(quantize(value, order - format.m, square_root), mode, value.negative) < 2 * format.hidden
        tiny && (flags |= UNDERFLOW)
    end
    magnitude = n < format.hidden ? Int(n) : (exponent + format.m + format.bias) * format.hidden + Int(n - format.hidden)
    Result(zero_pattern(format, value.negative) + magnitude, flags)
end

function raw_operand(format::MiniFormat, word::AbstractString; encoding::Bool = false)
    if startswith(word, "0b") || startswith(word, "0x")
        binary = startswith(word, "0b")
        width = binary ? format.w : cld(format.w, 4)
        (encoding || length(word) - 2 != width) && fail("BAD OPERAND $word")
        pattern = parse(Int, word[3:end]; base = binary ? 2 : 16)
        pattern >= 2 * format.sign_bit && fail("BAD OPERAND $word")
        return InputValue(pattern, nothing)
    end
    word == "nan" && return InputValue(format.nan, nothing)
    word == "inf" && return InputValue(format.infinity, nothing)
    word == "-inf" && return InputValue(infinity_pattern(format, true), nothing)
    negative = startswith(word, "-")
    body = negative ? word[2:end] : word
    denominator = Int64(1)
    if occursin('/', body)
        parts = split(body, '/')
        numerator = parse(Int64, parts[1]; base = 10)
        denominator = parse(Int64, parts[2]; base = 10)
        denominator == 0 && fail("BAD OPERAND $word")
    elseif occursin('.', body)
        parts = split(body, '.')
        numerator = parse(Int64, parts[1] * parts[2]; base = 10)
        denominator = Int64(10)^length(parts[2])
    else
        numerator = parse(Int64, body; base = 10)
    end
    InputValue(0, Exact(numerator, 0, denominator, negative))
end
function operand(format::MiniFormat, word::AbstractString)
    value = raw_operand(format, word)
    isnothing(value.number) ? value.pattern : round_exact(format, value.number, RNE).pattern
end

function arithmetic(format::MiniFormat, operation::Operation, inputs::Vector{Int}, mode::Mode)
    if operation == SUB
        return arithmetic(format, ADD, [inputs[1], flip(format, inputs[2])], mode)
    end
    if any(pattern -> is_nan(format, pattern), inputs)
        return Result(format.nan, any(pattern -> is_signaling(format, pattern), inputs) ? INVALID : UInt8(0))
    end
    invalid = Result(format.nan, INVALID)
    a = inputs[1]
    negative = fields(format, a).negative
    if operation == SQRT
        is_zero(format, a) && return Result(a)
        negative && return invalid
        is_infinite(format, a) && return Result(a)
        return round_exact(format, pattern_exact(format, a), mode; square_root = true)
    end
    b = inputs[2]
    sigma = xor(negative, fields(format, b).negative)
    if operation == ADD
        is_infinite(format, a) && is_infinite(format, b) && sigma && return invalid
        is_infinite(format, a) && return Result(a)
        is_infinite(format, b) && return Result(b)
        return round_exact(format, exact_sum([pattern_exact(format, a), pattern_exact(format, b)], mode), mode)
    elseif operation == MUL
        if is_infinite(format, a) || is_infinite(format, b)
            return is_zero(format, a) || is_zero(format, b) ? invalid : Result(infinity_pattern(format, sigma))
        end
        return round_exact(format, product(pattern_exact(format, a), pattern_exact(format, b)), mode)
    elseif operation == DIV
        is_infinite(format, a) && return (is_infinite(format, b) ? invalid : Result(infinity_pattern(format, sigma)))
        is_infinite(format, b) && return Result(zero_pattern(format, sigma))
        is_zero(format, b) && return (is_zero(format, a) ? invalid : Result(infinity_pattern(format, sigma), DIVBYZERO))
        is_zero(format, a) && return Result(zero_pattern(format, sigma))
        x, y = pattern_exact(format, a), pattern_exact(format, b)
        return round_exact(format, Exact(x.n * y.d, x.e - y.e, x.d * y.n, sigma), mode)
    end
    c = inputs[3]
    if is_infinite(format, a) || is_infinite(format, b)
        (is_zero(format, a) || is_zero(format, b) || (is_infinite(format, c) && fields(format, c).negative != sigma)) && return invalid
        return Result(infinity_pattern(format, sigma))
    end
    is_infinite(format, c) && return Result(c)
    terms = [product(pattern_exact(format, a), pattern_exact(format, b)), pattern_exact(format, c)]
    round_exact(format, exact_sum(terms, mode), mode)
end
function next_up(format::MiniFormat, pattern::Int)
    pattern == format.infinity && return pattern
    is_zero(format, pattern) && return 1
    pattern + (fields(format, pattern).negative ? -1 : 1)
end
function difference_text(format::MiniFormat, pattern::Int, value::Exact)
    is_finite(format, pattern) || return value_text(format, pattern)
    fraction_text(exact_sum([pattern_exact(format, pattern), negated(value)], RNE))
end
relation(a::Integer, b::Integer) = a < b ? "LT" : a > b ? "GT" : "EQ"

function summation(output::IO, command::AbstractString, format::MiniFormat, mode::Mode, patterns::Vector{Int})
    all(pattern -> is_finite(format, pattern), patterns) || fail("NOT FINITE")
    line(output, command, format.name, mode, "count=$(length(patterns))")
    current, compensation, flags = patterns[1], 0, UInt8(0)
    for index in 2:length(patterns)
        if command == "SUM"
            added = arithmetic(format, ADD, [current, patterns[index]], mode)
            current = added.pattern
            flags |= added.flags
            line(output, "PARTIAL", index, result_text(format, added))
        else
            y = arithmetic(format, SUB, [patterns[index], compensation], mode)
            t = arithmetic(format, ADD, [current, y.pattern], mode)
            d = arithmetic(format, SUB, [t.pattern, current], mode)
            correction = arithmetic(format, SUB, [d.pattern, y.pattern], mode)
            current, compensation = t.pattern, correction.pattern
            step_flags = y.flags | t.flags | d.flags | correction.flags
            flags |= step_flags
            line(output, "KSTEP", index, "sum=$(value_text(format, current))", "comp=$(value_text(format, compensation))", flags_text(step_flags))
        end
    end
    value = exact_sum([pattern_exact(format, pattern) for pattern in patterns], mode)
    line(output, "RESULT", result_text(format, Result(current, flags)))
    line(output, "EXACT", decimal_text(value))
    line(output, "ROUNDED", result_text(format, round_exact(format, value, mode)))
    line(output, "DIFF", difference_text(format, current, value))
end
function dot_product(output::IO, format::MiniFormat, mode::Mode, a::Vector{Int}, b::Vector{Int})
    length(a) == length(b) || fail("LENGTH MISMATCH")
    all(pattern -> is_finite(format, pattern), [a; b]) || fail("NOT FINITE")
    naive = arithmetic(format, MUL, [a[1], b[1]], mode)
    chained = naive
    for index in 2:length(a)
        multiplied = arithmetic(format, MUL, [a[index], b[index]], mode)
        added = arithmetic(format, ADD, [naive.pattern, multiplied.pattern], mode)
        naive = Result(added.pattern, naive.flags | multiplied.flags | added.flags)
        fused = arithmetic(format, FMA, [a[index], b[index], chained.pattern], mode)
        chained = Result(fused.pattern, chained.flags | fused.flags)
    end
    value = exact_sum([product(pattern_exact(format, a[index]), pattern_exact(format, b[index])) for index in eachindex(a)], mode)
    line(output, "DOT", format.name, mode, "n=$(length(a))")
    line(output, "NAIVE", result_text(format, naive))
    line(output, "CHAINED", result_text(format, chained))
    line(output, "EXACT", decimal_text(value))
    line(output, "FUSED", result_text(format, round_exact(format, value, mode)))
    line(output, "DIFF", "naive=$(difference_text(format, naive.pattern, value))", "chained=$(difference_text(format, chained.pattern, value))")
end
function table_lines(output::IO, format::MiniFormat)
    format.w <= 8 || fail("TABLE TOO LARGE")
    count = format.infinity
    line(output, "TABLE", format.name, "count=$count")
    for pattern in 0:(count - 1)
        gap = pattern == count - 1 ? "-" : decimal_text(exact_sum([pattern_exact(format, pattern + 1), negated(pattern_exact(format, pattern))], RNE))
        line(output, "ENTRY", pattern, pattern_text(format, pattern), "gap=$gap")
    end
    line(output, "MAX", pattern_text(format, format.infinity - 1))
    line(output, "MINNORMAL", pattern_text(format, format.hidden))
    line(output, "MINSUBNORMAL", pattern_text(format, 1))
    line(output, "EPSILON", decimal_text(Exact(1, -format.m)))
    line(output, "PATTERNS", "finite=$(2 * count)", "infinite=2", "nan=$(2 * (format.hidden - 1))", "total=$(2 * format.sign_bit)")
end

function format_named(formats::Dict{String,MiniFormat}, name::AbstractString)
    haskey(formats, name) || fail("UNKNOWN FORMAT $name")
    formats[name]
end
function mode_word(words::Vector{<:AbstractString}, index::Int)
    index > length(words) && return RNE
    mode = get(MODES, words[index], nothing)
    isnothing(mode) && fail("BAD MODE $(words[index])")
    mode
end
function execute(formats::Dict{String,MiniFormat}, words::Vector{<:AbstractString})
    command = words[1]
    output = IOBuffer()
    if command == "FORMAT"
        name = words[2]
        e, m = parse(Int, words[3]), parse(Int, words[4])
        haskey(formats, name) && fail("FORMAT EXISTS $name")
        (2 <= e <= 5 && 1 <= m <= 10) || fail("BAD FORMAT")
        format = MiniFormat(name, e, m)
        formats[format.name] = format
        line(output, "FORMAT", name, "e=$e", "m=$m", "bits=$(format.w)", "bias=$(format.bias)", "emin=$(format.emin)", "emax=$(format.emax)")
        return String(take!(output))
    end
    format = format_named(formats, words[2])
    name = format.name
    if command == "ENCODE"
        input = raw_operand(format, words[3]; encoding = true)
        mode = mode_word(words, 4)
        value = isnothing(input.number) ? value_text(format, input.pattern) : fraction_text(input.number)
        encoded = isnothing(input.number) ? Result(input.pattern) : round_exact(format, input.number, mode)
        line(output, "ENCODE", name, mode, value, result_text(format, encoded))
    elseif command == "CONVERT"
        target = format_named(formats, words[3])
        a = operand(format, words[4])
        mode = mode_word(words, 5)
        converted = if is_nan(format, a)
            Result(target.nan, is_signaling(format, a) ? INVALID : UInt8(0))
        elseif is_infinite(format, a)
            Result(infinity_pattern(target, fields(format, a).negative))
        else
            round_exact(target, pattern_exact(format, a), mode)
        end
        line(output, "CONVERT", name, target.name, mode, result_text(target, converted))
    elseif command in ("SUM", "KAHAN", "DOT")
        mode = mode_word(words, 3)
        if command == "DOT"
            separator = findfirst(==("|"), words)::Int
            a = [operand(format, word) for word in words[4:(separator - 1)]]
            b = [operand(format, word) for word in words[(separator + 1):end]]
            dot_product(output, format, mode, a, b)
        else
            patterns = [operand(format, word) for word in words[4:end]]
            summation(output, command, format, mode, patterns)
        end
    elseif command == "TABLE"
        table_lines(output, format)
    elseif haskey(OPERATIONS, command)
        operation = OPERATIONS[command]
        count = operation == SQRT ? 1 : operation == FMA ? 3 : 2
        patterns = [operand(format, word) for word in words[3:(2 + count)]]
        mode = mode_word(words, 3 + count)
        line(output, command, name, mode, result_text(format, arithmetic(format, operation, patterns, mode)))
    else
        a = operand(format, words[3])
        field = fields(format, a)
        if command == "DECODE"
            kind = classification(format, a)
            line(output, "DECODE", name, bits_text(format, a), hex_text(format, a), lowercase(string(kind)), "sign=$(Int(field.negative))")
            description = "FIELDS exponent=$(field.exponent) fraction=$(field.fraction)"
            if is_finite(format, a)
                description *= " unbiased=$(field.q + format.m) significand=$(field.exponent == 0 ? 0 : 1).$(string(field.fraction; base = 2, pad = format.m))"
                println(output, description)
                line(output, "VALUE", fraction_text(pattern_exact(format, a)), value_text(format, a))
            else
                is_nan(format, a) && (description *= " payload=$(field.fraction % (format.hidden ÷ 2))")
                println(output, description)
            end
        elseif command == "COMPARE"
            b = operand(format, words[4])
            key(pattern) = fields(format, pattern).negative ? -(pattern - format.sign_bit) - 1 : pattern
            total = relation(key(a), key(b))
            numeric = is_nan(format, a) || is_nan(format, b) ? "UN" : is_zero(format, a) && is_zero(format, b) ? "EQ" : total
            flags = is_signaling(format, a) || is_signaling(format, b) ? INVALID : UInt8(0)
            line(output, "COMPARE", name, hex_text(format, a), hex_text(format, b), numeric, "total=$total", flags_text(flags))
        elseif command == "TOINT"
            type = words[4]
            haskey(TYPES, type) || fail("BAD TYPE $type")
            mode = mode_word(words, 5)
            if !is_finite(format, a)
                line(output, "TOINT", name, type, mode, "invalid flags=invalid")
            else
                units = quantize(pattern_exact(format, a), 0, false)
                magnitude = rounded_units(units, mode, field.negative)
                integer = field.negative ? -magnitude : magnitude
                minimum, maximum = TYPES[type]
                if integer < minimum || integer > maximum
                    line(output, "TOINT", name, type, mode, "invalid flags=invalid")
                else
                    line(output, "TOINT", name, type, mode, integer, flags_text(units.inexact ? INEXACT : UInt8(0)))
                end
            end
        else
            value = if is_nan(format, a)
                Result(format.nan, is_signaling(format, a) ? INVALID : UInt8(0))
            elseif command == "NEXTUP"
                Result(next_up(format, a))
            elseif command == "NEXTDOWN"
                Result(flip(format, next_up(format, flip(format, a))))
            else
                Result(is_infinite(format, a) ? format.infinity : round_exact(format, Exact(1, field.q), RNE).pattern)
            end
            line(output, command, name, result_text(format, value))
        end
    end
    String(take!(output))
end

function main()
    count = parse(Int, readline())
    formats = Dict("HALF" => MiniFormat("HALF", 5, 10), "E5M2" => MiniFormat("E5M2", 5, 2), "E4M3" => MiniFormat("E4M3", 4, 3))
    for _ in 1:count
        words = split(readline())
        try
            print(execute(formats, words))
        catch error
            error isa CommandError || rethrow()
            println("ERROR ", error.message)
        end
    end
end

main()
