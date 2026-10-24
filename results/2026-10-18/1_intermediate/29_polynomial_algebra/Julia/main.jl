const Fraction = Rational{Int64}
fraction(n::Integer, d::Integer = 1) = Int64(n) // Int64(d)
const FZERO = fraction(0)
const FONE = fraction(1)

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
degree_limit(condition::Bool) = condition && fail("DEGREE LIMIT")
fraction_text(value::Fraction) = denominator(value) == 1 ? string(numerator(value)) : "$(numerator(value))/$(denominator(value))"
function parse_fraction(text::AbstractString)
    parts = split(text, '/')
    n = parse(Int64, parts[1]; base = 10)
    d = length(parts) == 1 ? Int64(1) : parse(Int64, parts[2]; base = 10)
    d == 0 && fail("ZERO DENOMINATOR")
    n // d
end

struct Polynomial
    coefficients::Vector{Fraction}
    function Polynomial(values::Vector{Fraction})
        size = length(values)
        while size > 0 && iszero(values[size])
            size -= 1
        end
        new(values[1:size])
    end
end
Polynomial() = Polynomial(Fraction[])
Polynomial(value::Fraction) = Polynomial(Fraction[value])
const PZERO = Polynomial()
const PONE = Polynomial(FONE)
const PX = Polynomial(Fraction[0, 1])
linear(value::Fraction, slope::Fraction = FONE) = Polynomial(Fraction[value, slope])
degree(a::Polynomial) = length(a.coefficients) - 1
leading(a::Polynomial) = last(a.coefficients)
coefficient(a::Polynomial, i::Int) = i <= degree(a) ? a.coefficients[i + 1] : FZERO
Base.iszero(a::Polynomial) = isempty(a.coefficients)
Base.isone(a::Polynomial) = degree(a) == 0 && leading(a) == FONE
require_nonzero(a::Polynomial) = iszero(a) && fail("ZERO POLYNOMIAL")
require_divisor(a::Polynomial) = iszero(a) && fail("DIVISION BY ZERO")
product_limit(a::Polynomial, b::Polynomial) = degree_limit(!iszero(a) && !iszero(b) && degree(a) + degree(b) > 30)
composition_limit(a::Polynomial, b::Polynomial) = degree_limit(degree(a) >= 1 && degree(b) >= 1 && degree(a) * degree(b) > 30)

Base.:+(a::Polynomial, b::Polynomial) = Polynomial(Fraction[coefficient(a, i) + coefficient(b, i) for i in 0:max(degree(a), degree(b))])
Base.:-(a::Polynomial, b::Polynomial) = Polynomial(Fraction[coefficient(a, i) - coefficient(b, i) for i in 0:max(degree(a), degree(b))])
Base.:-(a::Polynomial) = Polynomial(-a.coefficients)
Base.:*(a::Polynomial, value::Fraction) = Polynomial(a.coefficients .* value)
Base.:/(a::Polynomial, value::Fraction) = Polynomial(a.coefficients ./ value)
function Base.:*(a::Polynomial, b::Polynomial)
    (iszero(a) || iszero(b)) && return PZERO
    result = zeros(Fraction, degree(a) + degree(b) + 1)
    for i in eachindex(a.coefficients), j in eachindex(b.coefficients)
        result[i + j - 1] += a.coefficients[i] * b.coefficients[j]
    end
    Polynomial(result)
end
function Base.:^(a::Polynomial, exponent::Int)
    exponent == 0 && return PONE
    iszero(a) && return PZERO
    if degree(a) == 0 && abs(leading(a)) == FONE
        return isodd(exponent) ? a : PONE
    end
    result = PONE
    for _ in 1:exponent
        result = result * a
    end
    result
end
function scalar_power(value::Fraction, exponent::Int)
    result = FONE
    for _ in 1:exponent
        result *= value
    end
    result
end
function Base.divrem(a::Polynomial, b::Polynomial)
    quotient = zeros(Fraction, max(0, degree(a) - degree(b) + 1))
    remainder = copy(a.coefficients)
    while !isempty(remainder) && length(remainder) >= length(b.coefficients)
        offset = length(remainder) - length(b.coefficients)
        factor = last(remainder) / leading(b)
        quotient[offset + 1] = factor
        for j in eachindex(b.coefficients)
            remainder[offset + j] -= factor * b.coefficients[j]
        end
        while !isempty(remainder) && iszero(last(remainder))
            pop!(remainder)
        end
    end
    Polynomial(quotient), Polynomial(remainder)
end
quotient(a::Polynomial, b::Polynomial) = first(divrem(a, b))
Base.rem(a::Polynomial, b::Polynomial) = last(divrem(a, b))
monic(a::Polynomial) = iszero(a) ? a : a / leading(a)
function derivative(a::Polynomial, count::Int = 1)
    for _ in 1:count
        degree(a) <= 0 && return PZERO
        a = Polynomial(Fraction[i * coefficient(a, i) for i in 1:degree(a)])
    end
    a
end
integral(a::Polynomial) = Polynomial(vcat(FZERO, Fraction[coefficient(a, i) / (i + 1) for i in 0:degree(a)]))
function evaluate(a::Polynomial, point::Fraction)
    value = FZERO
    for i in degree(a):-1:0
        value = value * point + coefficient(a, i)
    end
    value
end
function compose(a::Polynomial, b::Polynomial)
    result = PZERO
    for i in degree(a):-1:0
        result = result * b + Polynomial(coefficient(a, i))
    end
    result
end
function polynomial_gcd(a::Polynomial, b::Polynomial)
    while !iszero(b)
        a, b = b, rem(a, b)
    end
    monic(a)
end
function extended_gcd(a::Polynomial, b::Polynomial)
    s0, s1, t0, t1 = PONE, PZERO, PZERO, PONE
    while !iszero(b)
        q, r = divrem(a, b)
        next_s = s0 - q * s1
        next_t = t0 - q * t1
        a, b = b, r
        s0, s1 = s1, next_s
        t0, t1 = t1, next_t
    end
    iszero(a) && return (a, s0, t0)
    divisor = leading(a)
    a / divisor, s0 / divisor, t0 / divisor
end
function content(a::Polynomial)
    common, multiple = Int64(0), Int64(1)
    for value in a.coefficients
        d = denominator(value)
        multiple = (multiple * d) ÷ gcd(multiple, d)
        common = gcd(common, abs(numerator(value)))
    end
    fraction(leading(a) < 0 ? -common : common, multiple)
end
primitive(a::Polynomial) = a / content(a)
squarefree(a::Polynomial) = degree(a) >= 1 ? quotient(a, polynomial_gcd(a, derivative(a))) : a

function notation(a::Polynomial, variable::String = "x")
    result = IOBuffer()
    first_term = true
    for i in degree(a):-1:0
        value = coefficient(a, i)
        iszero(value) && continue
        print(result, first_term ? (value < 0 ? "-" : "") : (value < 0 ? " - " : " + "))
        if i == 0 || abs(value) != FONE
            print(result, fraction_text(abs(value)))
        end
        i >= 1 && print(result, variable)
        i >= 2 && print(result, '^', i)
        first_term = false
    end
    first_term ? "0" : String(take!(result))
end

struct Root
    value::Fraction
    multiplicity::Int
end
function rational_roots(a::Polynomial)
    remaining = primitive(a)
    zeros = 0
    while iszero(first(remaining.coefficients))
        remaining = Polynomial(remaining.coefficients[2:end])
        zeros += 1
    end
    divisors(n::Int64) = Int64[i for i in 1:n if n % i == 0]
    candidates = Fraction[]
    for n in divisors(abs(numerator(first(remaining.coefficients))))
        for d in divisors(numerator(leading(remaining)))
            gcd(n, d) == 1 || continue
            push!(candidates, -n // d, n // d)
        end
    end
    roots = Root[]
    for value in sort!(candidates)
        factor = linear(fraction(-numerator(value)), fraction(denominator(value)))
        multiplicity = 0
        while degree(remaining) >= 1 && iszero(evaluate(remaining, value))
            remaining = quotient(remaining, factor)
            multiplicity += 1
        end
        multiplicity > 0 && push!(roots, Root(value, multiplicity))
    end
    zeros > 0 && push!(roots, Root(FZERO, zeros))
    sort!(roots; by = root -> root.value)
    roots, remaining
end
factor_text(text::String, multiplicity::Int) = " * " * text * (multiplicity > 1 ? "^$multiplicity" : "")
function factorization(a::Polynomial, roots::Vector{Root}, remaining::Polynomial)
    result = fraction_text(content(a))
    for root in roots
        value = root.value
        text = iszero(value) ? "x" : "(" * notation(linear(fraction(-numerator(value)), fraction(denominator(value)))) * ")"
        result *= factor_text(text, root.multiplicity)
    end
    degree(remaining) >= 1 && (result *= " * (" * notation(remaining) * ")")
    result
end
function squarefree_factors(a::Polynomial)
    result = fraction_text(content(a))
    degree(a) == 0 && return result
    normalized = monic(a)
    common = polynomial_gcd(normalized, derivative(normalized))
    remaining = quotient(normalized, common)
    multiplicity = 1
    while degree(remaining) >= 1
        shared = polynomial_gcd(remaining, common)
        factor = quotient(remaining, shared)
        if degree(factor) >= 1
            text = notation(primitive(factor))
            result *= factor_text(text == "x" ? text : "($text)", multiplicity)
        end
        common, remaining = quotient(common, shared), shared
        multiplicity += 1
    end
    result
end
function sign_changes(signs::Vector{Int})
    signs = filter(!iszero, signs)
    count(i -> signs[i] != signs[i - 1], 2:length(signs))
end
struct Bound
    kind::Int
    value::Fraction
end
Bound(value::Fraction) = Bound(0, value)
parse_bound(text::String) = text == "-inf" ? Bound(-1, FZERO) : text == "inf" ? Bound(1, FZERO) : Bound(parse_fraction(text))
bound_text(value::Bound) = value.kind == 0 ? fraction_text(value.value) : value.kind < 0 ? "-inf" : "inf"
function compare_bounds(a::Bound, b::Bound)
    a.kind != b.kind && return cmp(a.kind, b.kind)
    a.kind == 0 ? cmp(a.value, b.value) : 0
end
function sturm_sequence(a::Polynomial)
    first = squarefree(a)
    second = derivative(first)
    sequence = Polynomial[first]
    while !iszero(second)
        push!(sequence, second)
        first, second = second, -rem(first, second)
    end
    sequence
end
function variations(sequence::Vector{Polynomial}, point::Bound)
    signs = Int[]
    for a in sequence
        value = point.kind == 0 ? sign(numerator(evaluate(a, point.value))) : sign(numerator(leading(a)))
        point.kind < 0 && isodd(degree(a)) && (value = -value)
        push!(signs, value)
    end
    sign_changes(signs)
end
root_count(sequence::Vector{Polynomial}, low::Bound, high::Bound) = variations(sequence, low) - variations(sequence, high)
function isolate(a::Polynomial, precision::Int)
    sequence = sturm_sequence(a)
    first = sequence[1]
    beta = degree(first) == 0 ? FONE : FONE + maximum(abs.(first.coefficients[1:end-1] ./ leading(first)))
    width = fraction(1, Int64(1) << precision)
    intervals = Tuple{Fraction,Fraction}[]
    function examine(low::Fraction, high::Fraction)
        count = root_count(sequence, Bound(low), Bound(high))
        if count >= 2
            middle = (low + high) / 2
            examine(low, middle)
            examine(middle, high)
        elseif count == 1
            while high - low > width
                middle = (low + high) / 2
                if root_count(sequence, Bound(low), Bound(middle)) >= 1
                    high = middle
                else
                    low = middle
                end
            end
            push!(intervals, (low, high))
        end
    end
    examine(-beta, beta)
    isempty(intervals) ? "none" : join(("($(fraction_text(low)), $(fraction_text(high))]" for (low, high) in intervals), ", ")
end
function resultant(a::Polynomial, b::Polynomial)
    result = FONE
    while degree(b) >= 1
        remainder = rem(a, b)
        iszero(remainder) && return FZERO
        result *= scalar_power(leading(b), degree(a) - degree(remainder))
        isodd(degree(a) * degree(b)) && (result = -result)
        a, b = b, remainder
    end
    result * scalar_power(coefficient(b, 0), degree(a))
end
function power_sums(a::Polynomial, count::Int)
    d = degree(a)
    normalized = monic(a)
    sums = zeros(Fraction, count)
    for j in 1:count
        value = j <= d ? j * coefficient(normalized, d - j) : FZERO
        for i in 1:min(j - 1, d)
            value += coefficient(normalized, d - i) * sums[j - i]
        end
        sums[j] = -value
    end
    join(fraction_text.(sums), ", ")
end
function interpolate(values::Vector{Fraction})
    xs = values[1:2:end]
    differences = values[2:2:end]
    count = length(xs)
    for j in 2:count
        any(==(xs[j]), xs[1:j-1]) && fail("DUPLICATE X " * fraction_text(xs[j]))
    end
    for j in 1:count-1, i in count:-1:j+1
        differences[i] = (differences[i] - differences[i - 1]) / (xs[i] - xs[i - j])
    end
    result = PZERO
    for i in count:-1:1
        result = result * linear(-xs[i]) + Polynomial(differences[i])
    end
    result
end
function special(kind::String, count::Int)
    kind in ("chebyshev", "chebyshev2", "legendre", "hermite", "laguerre") || fail("UNKNOWN KIND $kind")
    degree_limit(count > 30)
    previous = PONE
    count == 0 && return previous
    current = kind in ("chebyshev2", "hermite") ? PX * fraction(2) : kind == "laguerre" ? linear(FONE, -FONE) : PX
    for j in 1:count-1
        factor = kind == "legendre" ? PX * fraction(2j + 1) : kind == "laguerre" ? linear(fraction(2j + 1), -FONE) : PX * fraction(2)
        multiplier = kind in ("legendre", "laguerre") ? j : kind == "hermite" ? 2j : 1
        next_value = factor * current - previous * fraction(multiplier)
        kind in ("legendre", "laguerre") && (next_value = next_value * fraction(1, j + 1))
        previous, current = current, next_value
    end
    current
end

abstract type Expression end
struct Literal <: Expression
    value::Fraction
end
struct Variable <: Expression end
struct Reference <: Expression
    name::String
    order::Int
end
struct Negative <: Expression
    operand::Expression
end
struct Binary <: Expression
    operation::Char
    left::Expression
    right::Expression
end
struct Power <: Expression
    operand::Expression
    exponent::Int
end
struct Call <: Expression
    function_value::Expression
    argument::Expression
end
@enum TokenKind NumberToken NameToken SymbolToken EndToken
struct Token
    kind::TokenKind
    text::String
    position::Int
end
mutable struct Parser
    tokens::Vector{Token}
    position::Int
end
function Parser(source::String)
    tokens = Token[]
    for match in eachmatch(r"[0-9]+|[A-Z][A-Z0-9]*|[^ ]", source)
        word = String(match.match)
        kind = isdigit(first(word)) ? NumberToken : 'A' <= first(word) <= 'Z' ? NameToken : SymbolToken
        push!(tokens, Token(kind, word, match.offset))
    end
    push!(tokens, Token(EndToken, "", length(source) + 1))
    Parser(tokens, 1)
end
current(parser::Parser) = parser.tokens[parser.position]
syntax_error(parser::Parser) = fail("SYNTAX AT " * (current(parser).kind == EndToken ? "END" : string(current(parser).position)))
function accept!(parser::Parser, word::String)
    if current(parser).kind == SymbolToken && current(parser).text == word
        parser.position += 1
        return true
    end
    false
end
expect!(parser::Parser, word::String) = accept!(parser, word) || syntax_error(parser)
function primary!(parser::Parser)::Expression
    token = current(parser)
    if token.kind == NumberToken
        parser.position += 1
        return Literal(fraction(parse(Int64, token.text; base = 10)))
    end
    accept!(parser, "x") && return Variable()
    if token.kind == NameToken
        parser.position += 1
        order = 0
        while accept!(parser, "'")
            order += 1
        end
        reference = Reference(token.text, order)
        accept!(parser, "(") || return reference
        argument = expression!(parser)
        expect!(parser, ")")
        return Call(reference, argument)
    end
    if accept!(parser, "(")
        result = expression!(parser)
        expect!(parser, ")")
        return result
    end
    syntax_error(parser)
end
function factor!(parser::Parser)::Expression
    result = primary!(parser)
    if accept!(parser, "^")
        current(parser).kind == NumberToken || syntax_error(parser)
        exponent = parse(Int, current(parser).text; base = 10)
        parser.position += 1
        result = Power(result, exponent)
    end
    result
end
function term!(parser::Parser)::Expression
    result = factor!(parser)
    while true
        if accept!(parser, "*")
            operation = '*'
        elseif accept!(parser, "/")
            operation = '/'
        elseif current(parser).kind == NameToken || current(parser).text in ("x", "(")
            operation = '*'
        else
            break
        end
        result = Binary(operation, result, factor!(parser))
    end
    result
end
function expression!(parser::Parser)::Expression
    negative = accept!(parser, "-")
    result = term!(parser)
    negative && (result = Negative(result))
    while true
        if accept!(parser, "+")
            operation = '+'
        elseif accept!(parser, "-")
            operation = '-'
        else
            break
        end
        result = Binary(operation, result, term!(parser))
    end
    result
end
function parse_definition(source::String)
    parser = Parser(source)
    result = expression!(parser)
    current(parser).kind == EndToken || syntax_error(parser)
    result
end

const Storage = Dict{String,Polynomial}
function lookup(storage::Storage, name::String)
    haskey(storage, name) || fail("UNKNOWN $name")
    storage[name]
end
evaluate(node::Literal, storage::Storage) = Polynomial(node.value)
evaluate(node::Variable, storage::Storage) = PX
evaluate(node::Reference, storage::Storage) = derivative(lookup(storage, node.name), node.order)
evaluate(node::Negative, storage::Storage) = -evaluate(node.operand, storage)
function evaluate(node::Power, storage::Storage)
    a = evaluate(node.operand, storage)
    degree_limit(!iszero(a) && degree(a) * node.exponent > 30)
    a ^ node.exponent
end
function evaluate(node::Call, storage::Storage)
    a = evaluate(node.function_value, storage)
    b = evaluate(node.argument, storage)
    composition_limit(a, b)
    compose(a, b)
end
function evaluate(node::Binary, storage::Storage)
    a = evaluate(node.left, storage)
    b = evaluate(node.right, storage)
    node.operation == '+' && return a + b
    node.operation == '-' && return a - b
    if node.operation == '*'
        product_limit(a, b)
        return a * b
    end
    require_divisor(b)
    degree(b) >= 1 && fail("NONCONSTANT DIVISOR")
    a / leading(b)
end

const REFERENCES = Dict(
    "PRINT" => [2], "DELETE" => [2], "DEGREE" => [2], "ADD" => [3, 4], "SUB" => [3, 4], "MUL" => [3, 4],
    "POW" => [3], "DIV" => [4, 5], "GCD" => [3, 4], "XGCD" => [5, 6], "LCM" => [3, 4], "INVMOD" => [3, 4],
    "CRT" => [3, 4, 5, 6], "MODPOW" => [3, 5], "DERIV" => [3], "INTEG" => [3], "AREA" => [2], "TANGENT" => [3],
    "TAYLOR" => [2], "COMPOSE" => [3, 4], "EVAL" => [2], "ROOTS" => [2], "FACTOR" => [2], "SQFREE" => [2],
    "DESCARTES" => [2], "STURM" => [2], "ISOLATE" => [2], "RESULTANT" => [2, 3], "DISCRIM" => [2], "POWERSUM" => [2]
)
function execute!(storage::Storage, source::String)
    words = String.(split(source, ' '))
    command = words[1]
    name = length(words) >= 2 ? words[2] : ""
    pending = Pair{String,Polynomial}[]
    output = String[]
    deletion = nothing
    function save!(destination::String, value::Polynomial)
        push!(pending, destination => value)
        push!(output, "$destination = $(notation(value))")
    end
    if command == "DEF"
        tree = parse_definition(source[length(name)+6:end])
        save!(name, evaluate(tree, storage))
    else
        ((command == "DIV" && words[2] == words[3]) || (command == "XGCD" && length(unique(words[2:4])) < 3)) && fail("SAME NAME")
        operands = Polynomial[lookup(storage, words[i]) for i in get(REFERENCES, command, Int[])]
        a = length(operands) >= 1 ? operands[1] : PZERO
        b = length(operands) >= 2 ? operands[2] : PZERO
        literal_words = command in ("AREA", "STURM") ? words[3:4] : command == "TANGENT" ? words[4:4] :
                        command == "TAYLOR" ? words[3:3] : command in ("EVAL", "INTERP") ? words[3:end] : String[]
        bounds = command == "STURM" ? parse_bound.(literal_words) : Bound[]
        values = command == "STURM" ? Fraction[] : parse_fraction.(literal_words)
        if command == "PRINT"
            push!(output, "$name = $(notation(a))")
        elseif command == "DELETE"
            deletion = name
            push!(output, "deleted $name")
        elseif command == "LIST"
            for key in sort!(collect(keys(storage)))
                push!(output, "$key = $(notation(storage[key]))")
            end
            isempty(output) && push!(output, "no polynomials")
        elseif command == "DEGREE"
            push!(output, "deg($name) = $(iszero(a) ? "-inf" : degree(a))")
        elseif command in ("ADD", "SUB", "MUL")
            command == "MUL" && product_limit(a, b)
            save!(name, command == "ADD" ? a + b : command == "SUB" ? a - b : a * b)
        elseif command == "POW"
            exponent = parse(Int, words[4])
            degree_limit(!iszero(a) && degree(a) * exponent > 30)
            save!(name, a ^ exponent)
        elseif command == "DIV"
            require_divisor(b)
            q, r = divrem(a, b)
            save!(name, q)
            save!(words[3], r)
        elseif command == "GCD"
            save!(name, polynomial_gcd(a, b))
        elseif command == "XGCD"
            result = extended_gcd(a, b)
            for i in 1:3
                save!(words[i + 1], result[i])
            end
        elseif command == "LCM"
            result = PZERO
            if !iszero(a) && !iszero(b)
                common = polynomial_gcd(a, b)
                degree_limit(degree(a) + degree(b) - degree(common) > 30)
                result = monic(quotient(a, common) * b)
            end
            save!(name, result)
        elseif command == "INVMOD"
            require_divisor(b)
            degree(b) == 0 && fail("DEGREE TOO LOW")
            common, inverse, _ = extended_gcd(a, b)
            isone(common) || fail("NOT COPRIME")
            save!(name, rem(inverse, b))
        elseif command == "CRT"
            c, d = operands[3:4]
            require_divisor(b)
            require_divisor(d)
            degree_limit(degree(b) + degree(d) > 30)
            common, inverse, _ = extended_gcd(b, d)
            isone(common) || fail("NOT COPRIME")
            first = rem(a, b)
            second = rem(c, d)
            correction = rem((second - first) * inverse, d)
            save!(name, first + b * correction)
        elseif command == "MODPOW"
            require_divisor(b)
            degree_limit(2 * degree(b) - 2 > 30)
            result, base = rem(PONE, b), rem(a, b)
            exponent = parse(Int, words[4])
            while exponent > 0
                isodd(exponent) && (result = rem(result * base, b))
                exponent ÷= 2
                exponent > 0 && (base = rem(base * base, b))
            end
            save!(name, result)
        elseif command == "DERIV"
            save!(name, derivative(a, parse(Int, words[4])))
        elseif command == "INTEG"
            degree_limit(!iszero(a) && degree(a) + 1 > 30)
            save!(name, integral(a))
        elseif command == "AREA"
            antiderivative = integral(a)
            value = evaluate(antiderivative, values[2]) - evaluate(antiderivative, values[1])
            push!(output, "integral($name, $(fraction_text(values[1])), $(fraction_text(values[2]))) = $(fraction_text(value))")
        elseif command == "TANGENT"
            point = values[1]
            value = evaluate(a, point)
            slope = evaluate(derivative(a), point)
            save!(name, linear(value - slope * point, slope))
        elseif command == "TAYLOR"
            point = values[1]
            variable = iszero(point) ? "x" : point > 0 ? "(x - $(fraction_text(point)))" : "(x + $(fraction_text(-point)))"
            push!(output, "taylor($name, $(fraction_text(point))) = $(notation(compose(a, linear(point)), variable))")
        elseif command == "COMPOSE"
            composition_limit(a, b)
            save!(name, compose(a, b))
        elseif command == "EVAL"
            for point in values
                push!(output, "$name($(fraction_text(point))) = $(fraction_text(evaluate(a, point)))")
            end
        elseif command in ("ROOTS", "FACTOR")
            require_nonzero(a)
            roots, remaining = rational_roots(a)
            if command == "ROOTS"
                text = isempty(roots) ? "none" : join(("$(fraction_text(root.value)) ($(root.multiplicity))" for root in roots), ", ")
                push!(output, "roots($name) = $text")
            else
                push!(output, "factor($name) = $(factorization(a, roots, remaining))")
            end
        elseif command == "SQFREE"
            require_nonzero(a)
            push!(output, "sqfree($name) = $(squarefree_factors(a))")
        elseif command == "DESCARTES"
            require_nonzero(a)
            signs = Int[sign(numerator(value)) for value in a.coefficients]
            positive = sign_changes(reverse(signs))
            signs[2:2:end] .*= -1
            push!(output, "descartes($name) = positive $positive, negative $(sign_changes(reverse(signs)))")
        elseif command == "STURM"
            require_nonzero(a)
            compare_bounds(bounds[1], bounds[2]) >= 0 && fail("BAD INTERVAL")
            sequence = sturm_sequence(a)
            push!(output, "sturm($name, $(bound_text(bounds[1])), $(bound_text(bounds[2]))) = $(root_count(sequence, bounds[1], bounds[2]))")
        elseif command == "ISOLATE"
            require_nonzero(a)
            precision = parse(Int, words[3])
            push!(output, "isolate($name, $precision) = $(isolate(a, precision))")
        elseif command == "RESULTANT"
            require_nonzero(a)
            require_nonzero(b)
            push!(output, "res($name, $(words[3])) = $(fraction_text(resultant(a, b)))")
        elseif command in ("DISCRIM", "POWERSUM")
            require_nonzero(a)
            degree(a) == 0 && fail("DEGREE TOO LOW")
            if command == "DISCRIM"
                value = resultant(a, derivative(a)) / leading(a)
                isodd((degree(a) * (degree(a) - 1)) ÷ 2) && (value = -value)
                push!(output, "disc($name) = $(fraction_text(value))")
            else
                push!(output, "powersum($name) = $(power_sums(a, parse(Int, words[3])))")
            end
        elseif command == "INTERP"
            save!(name, interpolate(values))
        elseif command == "SPECIAL"
            save!(name, special(words[3], parse(Int, words[4])))
        end
    end
    deletion !== nothing && delete!(storage, deletion)
    for (destination, value) in pending
        storage[destination] = value
    end
    output
end

function main()
    storage = Storage()
    count = parse(Int, readline())
    for _ in 1:count
        source = readline()
        try
            for line in execute!(storage, source)
                println(line)
            end
        catch error
            error isa CommandError || rethrow()
            println("ERROR ", error.message)
        end
    end
end
main()
