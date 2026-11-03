const Word = UInt32

@enum CommandKind begin
    GEN
    PCHECK
    HAMMING
    SIMPLEX
    REPETITION
    PARITY
    RM
    CYCLIC
    DUAL
    EXTEND
    PUNCTURE
    SHORTEN
    AUGMENT
    EXPURGATE
    PERMUTE
    DIRECTSUM
    UUV
    PRODUCT
    LIST
    DELETE
    SHOW
    INFO
    SYSTEMATIC
    WEIGHTS
    COVERING
    BURST
    TRELLIS
    STDARRAY
    EQUAL
    ENCODE
    SYNDROME
    DECODE
    BOUNDED
    COSET
    ERASURE
    INTERLEAVE
    CRC
    CRCCHECK
    FACTOR
    MACWILLIAMS
    BOUNDS
end

struct CommandSpec
    kind::CommandKind
    types::String
    minimum::Int
    maximum::Int
end
CommandSpec(kind::CommandKind, types::String, count::Int) = CommandSpec(kind, types, count, count)
const SPECS = let rows = [
    CommandSpec(GEN, "NV", 2, 25), CommandSpec(PCHECK, "NV", 2, 25),
    CommandSpec(HAMMING, "NI", 2), CommandSpec(SIMPLEX, "NI", 2),
    CommandSpec(REPETITION, "NI", 2), CommandSpec(PARITY, "NI", 2),
    CommandSpec(RM, "NII", 3), CommandSpec(CYCLIC, "NIV", 3),
    CommandSpec(DUAL, "NA", 2), CommandSpec(EXTEND, "NA", 2),
    CommandSpec(PUNCTURE, "NAI", 3), CommandSpec(SHORTEN, "NAI", 3),
    CommandSpec(AUGMENT, "NA", 2), CommandSpec(EXPURGATE, "NA", 2),
    CommandSpec(PERMUTE, "NAI", 3, 26), CommandSpec(DIRECTSUM, "NAB", 3),
    CommandSpec(UUV, "NAB", 3), CommandSpec(PRODUCT, "NAB", 3),
    CommandSpec(LIST, "", 0), CommandSpec(DELETE, "A", 1),
    CommandSpec(SHOW, "A", 1), CommandSpec(INFO, "A", 1),
    CommandSpec(SYSTEMATIC, "A", 1), CommandSpec(WEIGHTS, "A", 1),
    CommandSpec(COVERING, "A", 1), CommandSpec(BURST, "A", 1),
    CommandSpec(TRELLIS, "A", 1), CommandSpec(STDARRAY, "A", 1),
    CommandSpec(EQUAL, "AB", 2), CommandSpec(ENCODE, "AV", 2),
    CommandSpec(SYNDROME, "AV", 2), CommandSpec(DECODE, "AV", 2),
    CommandSpec(BOUNDED, "AIV", 3), CommandSpec(COSET, "AV", 2),
    CommandSpec(ERASURE, "AX", 2), CommandSpec(INTERLEAVE, "AIIV", 4, 11),
    CommandSpec(CRC, "VV", 2), CommandSpec(CRCCHECK, "VV", 2),
    CommandSpec(FACTOR, "I", 1), CommandSpec(MACWILLIAMS, "II", 2, 26),
    CommandSpec(BOUNDS, "II", 2)
]
    Dict(string(row.kind) => row for row in rows)
end
const INDEPENDENT = (CRC, CRCCHECK, FACTOR, MACWILLIAMS, BOUNDS)

struct CommandError <: Exception
    message::String
end
ensure(condition::Bool, message::String) = condition || throw(CommandError(message))
function valid_word(text::String, kind::Char)
    pattern = if kind in ('N', 'A', 'B')
        r"^[A-Za-z][A-Za-z0-9]{0,7}$"
    elseif kind == 'I'
        r"^(0|[1-9][0-9]{0,3})$"
    elseif kind == 'X'
        r"^[01?]{1,30}$"
    else
        r"^[01]{1,30}$"
    end
    occursin(pattern, text)
end

power2(exponent::Int) = 1 << exponent
word_mask(size::Int) = (one(Word) << size) - one(Word)
bit_at(size::Int, column::Int) = one(Word) << (size - column)
parse_bits(text::String) = parse(Word, text; base = 2)
weight(word::Word) = count_ones(word)
word_length(word::Word) = 32 - leading_zeros(word)
bits(value::Integer, size::Int) = string(value; base = 2, pad = size)
yes(value::Bool) = value ? "yes" : "no"
joined(values) = join(values, " ")
matrix_text(label::String, rows::Vector{Word}, size::Int) = ["$label $(bits(row, size))" for row in rows]

function poly_divide(value::Word, divisor::Word)
    quotient = zero(Word)
    while value != 0 && word_length(value) >= word_length(divisor)
        shift = word_length(value) - word_length(divisor)
        quotient ⊻= one(Word) << shift
        value ⊻= divisor << shift
    end
    (; quotient, remainder = value)
end

function basis(source::Vector{Word}, size::Int)
    pivots = zeros(Word, size)
    result = Word[]
    for original in source
        row = original
        for column in 1:size
            row & bit_at(size, column) == 0 && continue
            if pivots[column] != 0
                row ⊻= pivots[column]
            else
                pivots[column] = row
                push!(result, original)
                break
            end
        end
    end
    result
end

function rref(source::Vector{Word}, size::Int)
    rows = copy(source)
    columns = Int[]
    for column in 1:size
        pivot = length(columns) + 1
        found = findfirst(i -> i >= pivot && rows[i] & bit_at(size, column) != 0, eachindex(rows))
        isnothing(found) && continue
        rows[pivot], rows[found] = rows[found], rows[pivot]
        for i in eachindex(rows)
            i != pivot && rows[i] & bit_at(size, column) != 0 && (rows[i] ⊻= rows[pivot])
        end
        push!(columns, column)
    end
    (; rows = rows[1:length(columns)], columns)
end

function null_space(source::Vector{Word}, size::Int)
    reduced = rref(source, size)
    result = Word[]
    for column in setdiff(1:size, reduced.columns)
        row = bit_at(size, column)
        for (index, pivot) in enumerate(reduced.columns)
            reduced.rows[index] & bit_at(size, column) != 0 && (row |= bit_at(size, pivot))
        end
        push!(result, row)
    end
    result
end

function span(rows::Vector{Word})
    result = Word[0]
    for row in rows
        append!(result, result .⊻ row)
    end
    result
end

function reed_muller(order::Int, variables::Int)
    order == 0 && return Word[word_mask(power2(variables))]
    half = power2(variables - 1)
    first = reed_muller(min(order, variables - 1), variables - 1)
    vcat((first .<< half) .| first, reed_muller(order - 1, variables - 1))
end

function check_dimension(size::Int, dimension::Int)
    ensure(1 <= dimension <= 12 && 1 <= size - dimension <= 12, "bad dimension $size $dimension")
end

struct Code
    n::Int
    g::Vector{Word}
    h::Vector{Word}
    polynomial::Union{Nothing, Word}
end
function make_code(size::Int, generator::Vector{Word}; parity::Union{Nothing, Vector{Word}} = nothing,
                   polynomial::Union{Nothing, Word} = nothing)
    check_dimension(size, length(generator))
    Code(size, copy(generator), isnothing(parity) ? null_space(generator, size) : copy(parity), polynomial)
end
dimension(code::Code) = length(code.g)
encoder(code::Code) = isnothing(code.polynomial) ? "matrix" : "polynomial"

function encode(code::Code, message::Word)
    if !isnothing(code.polynomial)
        shifted = message << (code.n - dimension(code))
        return shifted | poly_divide(shifted, code.polynomial).remainder
    end
    result = zero(Word)
    for (column, row) in enumerate(code.g)
        message & bit_at(dimension(code), column) != 0 && (result ⊻= row)
    end
    result
end
encoded_words(code::Code) = isnothing(code.polynomial) ? span(reverse(code.g)) :
    [encode(code, Word(message)) for message in 0:power2(dimension(code))-1]

function syndrome(code::Code, word::Word)
    result = zero(Word)
    for row in code.h
        result = (result << 1) | Word(isodd(weight(row & word)))
    end
    result
end

function leaders(code::Code)
    result = fill(typemax(Word), power2(code.n - dimension(code)))
    result[1] = 0
    found = 1
    for size in 1:code.n
        word = word_mask(size)
        while word < one(Word) << code.n
            state = Int(syndrome(code, word)) + 1
            if result[state] == typemax(Word)
                result[state] = word
                found += 1
                found == length(result) && return result
            end
            lowest = word & -word
            following = word + lowest
            word = following | ((following ⊻ word) >> 2) ÷ lowest
        end
    end
    result
end

struct Decoded
    word::Word
    message::Int
    error_pattern::Word
end
function decode(code::Code, received::Word, errors::Vector{Word}, encoding::Vector{Word})
    pattern = errors[Int(syndrome(code, received)) + 1]
    word = received ⊻ pattern
    Decoded(word, something(findfirst(==(word), encoding)) - 1, pattern)
end
decoded_text(code::Code, result::Decoded) =
    "codeword $(bits(result.word, code.n)) message $(bits(result.message, dimension(code))) error $(bits(result.error_pattern, code.n)) weight $(weight(result.error_pattern))"

function burst_correction(code::Code)
    seen = falses(power2(code.n - dimension(code)))
    seen[1] = true
    for size in 1:code.n
        variants = size == 1 ? 1 : power2(size - 2)
        for offset in 0:code.n-size, middle in 0:variants-1
            word = size == 1 ? one(Word) : (one(Word) << (size - 1)) | (Word(middle) << 1) | one(Word)
            state = Int(syndrome(code, word << offset)) + 1
            seen[state] && return size - 1
            seen[state] = true
        end
    end
    0
end

function construct(command::CommandKind, args::Vector{String}, sources::Vector{Code})
    if command in (GEN, PCHECK)
        size = length(args[2])
        ensure(all(text -> length(text) == size, args[2:end]), "bad length")
        rows = basis(parse_bits.(args[2:end]), size)
        return command == GEN ? make_code(size, rows) : make_code(size, null_space(rows, size); parity = rows)
    elseif command in (HAMMING, SIMPLEX)
        order = parse(Int, args[2])
        ensure(2 <= order <= 4, "bad parameter")
        size = power2(order) - 1
        rows = zeros(Word, order)
        for column in 1:size, row in 1:order
            rows[row] = (rows[row] << 1) | Word((column >> (order - row)) & 1)
        end
        return command == SIMPLEX ? make_code(size, rows) : make_code(size, null_space(rows, size); parity = rows)
    elseif command in (REPETITION, PARITY)
        size = parse(Int, args[2])
        ensure(2 <= size <= 24, "bad parameter")
        rows = command == REPETITION ? Word[word_mask(size)] : [bit_at(size, i) | one(Word) for i in 1:size-1]
        return make_code(size, rows)
    elseif command == RM
        order, variables = parse.(Int, args[2:3])
        ensure(1 <= variables <= 4 && order <= variables, "bad parameter")
        return make_code(power2(variables), reed_muller(order, variables))
    elseif command == CYCLIC
        size = parse(Int, args[2])
        degree = length(args[3]) - 1
        ensure(2 <= size <= 24 && first(args[3]) == '1' && 1 <= degree < size, "bad parameter")
        polynomial = parse_bits(args[3])
        ensure(poly_divide((one(Word) << size) | one(Word), polynomial).remainder == 0, "not a divisor")
        count = size - degree
        rows = [polynomial << (count - i) for i in 1:count]
        checks = zeros(Word, degree)
        for column in 1:size
            residue = poly_divide(bit_at(size, column), polynomial).remainder
            for row in 1:degree
                checks[row] = (checks[row] << 1) | Word(residue & bit_at(degree, row) != 0)
            end
        end
        return make_code(size, rows; parity = checks, polynomial = polynomial)
    end

    source = first(sources)
    size = source.n
    command == DUAL && return make_code(size, source.h; parity = source.g)
    command == EXTEND && return make_code(size + 1, [(row << 1) | Word(isodd(weight(row))) for row in source.g])
    if command in (PUNCTURE, SHORTEN, EXPURGATE)
        expurgating = command == EXPURGATE
        position = expurgating ? 0 : parse(Int, args[3])
        ensure(expurgating || 1 <= position <= size, "bad position")
        selected(row) = expurgating ? isodd(weight(row)) : row & bit_at(size, position) != 0
        removed = command == PUNCTURE ? nothing : findfirst(selected, source.g)
        rows = Word[]
        for (index, original) in enumerate(source.g)
            index == removed && continue
            row = !isnothing(removed) && selected(original) ? original ⊻ source.g[removed] : original
            if !expurgating
                low = size - position
                row = ((row >> (low + 1)) << low) | (row & word_mask(low))
            end
            push!(rows, row)
        end
        expurgating || (size -= 1)
        return make_code(size, command == PUNCTURE ? basis(rows, size) : rows)
    elseif command == AUGMENT
        return make_code(size, basis(vcat(source.g, word_mask(size)), size))
    elseif command == PERMUTE
        permutation = parse.(Int, args[3:end])
        ensure(sort(permutation) == collect(1:size), "bad permutation")
        rows = Word[]
        for row in source.g
            result = zero(Word)
            for column in permutation
                result = (result << 1) | Word(row & bit_at(size, column) != 0)
            end
            push!(rows, result)
        end
        return make_code(size, rows)
    end

    other = sources[2]
    ensure(command != UUV || size == other.n, "bad length")
    product = command == PRODUCT
    combined = product ? size * other.n : size + other.n
    count = product ? dimension(source) * dimension(other) : dimension(source) + dimension(other)
    check_dimension(combined, count)
    rows = Word[]
    if product
        for left in source.g, right in other.g
            row = zero(Word)
            for column in 1:size
                row = (row << other.n) | (left & bit_at(size, column) != 0 ? right : zero(Word))
            end
            push!(rows, row)
        end
    else
        append!(rows, [(row << other.n) | (command == UUV ? row : zero(Word)) for row in source.g])
        append!(rows, other.g)
    end
    make_code(combined, rows)
end

const COMBINATIONS = let table = zeros(Int64, 25, 25)
    for n in 0:24
        table[n + 1, 1] = 1
        for k in 1:n
            table[n + 1, k + 1] = table[n, k] + table[n, k + 1]
        end
    end
    table
end
choose_count(size::Int, selected::Int) = 0 <= selected <= size ? COMBINATIONS[size + 1, selected + 1] : Int64(0)
volume(size::Int, radius::Int) = sum(@view COMBINATIONS[size + 1, 1:radius+1])
krawtchouk(size::Int, index::Int, argument::Int) =
    sum((iseven(selected) ? 1 : -1) * choose_count(argument, selected) * choose_count(size - argument, index - selected)
        for selected in 0:index)
function fraction_text(numerator::Integer, denominator::Integer)
    common = gcd(numerator, denominator)
    top, bottom = numerator ÷ common, denominator ÷ common
    bottom == 1 ? string(top) : "$top/$bottom"
end
function distribution(words::Vector{Word}, size::Int, offset::Word = zero(Word))
    counts = zeros(Int, size + 1)
    for word in words
        counts[weight(word ⊻ offset) + 1] += 1
    end
    counts
end
weight_items(counts::Vector{Int}) = joined(["$(index - 1):$count" for (index, count) in enumerate(counts) if count != 0])

function systematic(name::String, code::Code)
    rows = copy(code.g)
    n, k = code.n, dimension(code)
    permutation = collect(1:n)
    for pivot in 1:k
        column = pivot
        found = nothing
        while isnothing(found)
            found = findfirst(i -> i >= pivot && rows[i] & bit_at(n, column) != 0, eachindex(rows))
            isnothing(found) && (column += 1)
        end
        if column != pivot
            left, right = bit_at(n, pivot), bit_at(n, column)
            for i in eachindex(rows)
                (rows[i] & left != 0) != (rows[i] & right != 0) && (rows[i] ⊻= left | right)
            end
            permutation[pivot], permutation[column] = permutation[column], permutation[pivot]
        end
        rows[pivot], rows[found] = rows[found], rows[pivot]
        for i in eachindex(rows)
            i != pivot && rows[i] & bit_at(n, pivot) != 0 && (rows[i] ⊻= rows[pivot])
        end
    end
    checks = Word[]
    for column in 1:n-k
        row = zero(Word)
        for original in rows
            row = (row << 1) | Word(original & bit_at(n, k + column) != 0)
        end
        push!(checks, (row << (n - k)) | bit_at(n - k, column))
    end
    vcat(["systematic $name perm $(joined(permutation))"], matrix_text("G", rows, n), matrix_text("H", checks, n))
end

function inspect_code(command::CommandKind, args::Vector{String}, sources::Vector{Code})
    code = first(sources)
    name, n, k = args[1], code.n, dimension(code)
    if command == SHOW
        output = ["code $name n $n k $k encoder $(encoder(code))"]
        if !isnothing(code.polynomial)
            quotient = poly_divide((one(Word) << n) | one(Word), code.polynomial).quotient
            push!(output, "poly g $(bits(code.polynomial, n - k + 1)) h $(bits(quotient, k + 1))")
        end
        return vcat(output, matrix_text("G", code.g, n), matrix_text("H", code.h, n))
    elseif command == SYSTEMATIC
        return systematic(name, code)
    elseif command == EQUAL
        other = sources[2]
        n != other.n && return ["equal $name $(args[2]) no lengths $n $(other.n)"]
        common = k + dimension(other) - length(basis(vcat(code.g, other.g), n))
        return ["equal $name $(args[2]) $(yes(k == common == dimension(other))) intersection $common"]
    elseif command == TRELLIS
        profile = [length(basis(code.g .>> (n - column), column)) +
                   length(basis(code.g .& word_mask(n - column), n - column)) - k for column in 0:n]
        return ["trellis $name profile $(joined(profile)) max $(maximum(profile))"]
    elseif command == COVERING
        counts = distribution(leaders(code), n)
        radius = something(findlast(!=(0), counts)) - 1
        items = ["$i:$(counts[i + 1])" for i in 0:radius]
        return ["covering $name radius $radius leaders $(joined(items))"]
    end
    ensure(command != STDARRAY || (n - k <= 6 && k <= 4), "too large")
    words = span(code.g)
    if command == INFO
        distance = minimum(weight, @view words[2:end])
        correction = (distance - 1) ÷ 2
        rotated = ((code.g .<< 1) .& word_mask(n)) .| (code.g .>> (n - 1))
        first_word = minimum(@view words[2:end])
        cyclic = all(row -> syndrome(code, row) == 0, rotated) ? bits(first_word, word_length(first_word)) : "no"
        return ["info $name n $n k $k rate $(fraction_text(k, n)) d $distance t $correction perfect $(yes(volume(n, correction) == power2(n - k))) mds $(yes(distance == n - k + 1)) cyclic $cyclic"]
    elseif command == WEIGHTS
        primal, dual = distribution(words, n), distribution(span(code.h), n)
        orthogonal = all(iseven(weight(left & right)) for left in code.g, right in code.g)
        return ["weights $name $(weight_items(primal))", "dual $name $(weight_items(dual))",
                "duality $name self-orthogonal $(yes(orthogonal)) self-dual $(yes(orthogonal && n == 2k)) formally-self-dual $(yes(primal == dual))"]
    elseif command == BURST
        detection = minimum(word -> word_length(word) - word_length(word & -word), @view words[2:end])
        return ["burst $name detect $detection correct $(burst_correction(code))"]
    end
    errors = leaders(code)
    ordering = sortperm(errors; by = word -> (weight(word), word))
    sort!(words)
    output = ["stdarray $name rows $(length(errors)) columns $(length(words))"]
    for state in ordering
        row = [bits(errors[state] ⊻ word, n) for word in words]
        push!(output, "$(bits(state - 1, n - k)): $(joined(row))")
    end
    output
end

function encoding_report(command::CommandKind, args::Vector{String}, code::Code)
    name, n, k = args[1], code.n, dimension(code)
    if command == INTERLEAVE
        messages = args[4:end]
        ensure(all(message -> length(message) == k, messages), "bad length")
        start, burst_length = parse.(Int, args[2:3])
        depth = length(messages)
        ensure(start >= 1 && burst_length >= 1 && start + burst_length - 1 <= depth * n, "bad burst")
        encoded = [encode(code, parse_bits(message)) for message in messages]
        sent_matrix = [word & bit_at(n, column) != 0 for word in encoded, column in 1:n]
        sent = vec(sent_matrix)
        received = copy(sent)
        selected = start:start+burst_length-1
        received[selected] .= .!received[selected]
        received_matrix = reshape(received, depth, n)
        received_words = zeros(Word, depth)
        for column in 1:n, row in 1:depth
            received_words[row] = (received_words[row] << 1) | Word(received_matrix[row, column])
        end
        output = ["interleave $name depth $depth burst $start $burst_length",
                  "sent $(join(Int.(sent)))", "recv $(join(Int.(received)))"]
        errors, encoding = leaders(code), encoded_words(code)
        correct = 0
        for row in 1:depth
            result = decode(code, received_words[row], errors, encoding)
            success = result.message == parse_bits(messages[row])
            correct += success
            push!(output, "row $row errors $(weight(received_words[row] ⊻ encoded[row])) corrected $(weight(result.error_pattern)) message $(bits(result.message, k)) $(success ? "ok" : "wrong")")
        end
        push!(output, "result ok $correct wrong $(depth - correct)")
        return output
    end

    text = args[command == BOUNDED ? 3 : 2]
    expected = command == ENCODE ? k : n
    ensure(length(text) == expected, "bad length")
    if command == ENCODE
        return ["encode $name message $text codeword $(bits(encode(code, parse_bits(text)), n))"]
    elseif command == ERASURE
        known, value = zero(Word), zero(Word)
        for (column, unit) in enumerate(text)
            unit != '?' && (known |= bit_at(n, column))
            unit == '1' && (value |= bit_at(n, column))
        end
        candidates = filter(word -> word & known == value, span(code.g))
        output = "erasure $name erased $(count(==('?'), text)) candidates $(length(candidates))"
        if length(candidates) == 1
            word = only(candidates)
            message = something(findfirst(==(word), encoded_words(code))) - 1
            output *= " codeword $(bits(word, n)) message $(bits(message, k))"
        end
        return [output]
    end
    word = parse_bits(text)
    state = syndrome(code, word)
    command == SYNDROME && return ["syndrome $name $(bits(state, n - k)) codeword $(yes(state == 0))"]
    errors = leaders(code)
    if command == COSET
        return ["coset $name syndrome $(bits(state, n - k)) leader $(bits(errors[Int(state) + 1], n)) weights $(weight_items(distribution(span(code.g), n, word)))"]
    end
    result = decode(code, word, errors, encoded_words(code))
    if command == BOUNDED && weight(result.error_pattern) > parse(Int, args[2])
        return ["bounded $name fail weight $(weight(result.error_pattern))"]
    end
    ["$(lowercase(string(command))) $name $(decoded_text(code, result))"]
end

function independent_report(command::CommandKind, args::Vector{String})
    if command in (CRC, CRCCHECK)
        degree = length(args[1]) - 1
        ensure(first(args[1]) == '1' && 1 <= degree <= 16, "bad parameter")
        ensure(command != CRC || length(args[2]) + degree <= 30, "bad length")
        word = parse_bits(args[2]) << (command == CRC ? degree : 0)
        residue = poly_divide(word, parse_bits(args[1])).remainder
        suffix = bits(residue, degree)
        return command == CRC ? ["crc remainder $suffix frame $(args[2])$suffix"] :
            ["crccheck $(residue == 0 ? "ok" : "error") remainder $suffix"]
    end
    size = parse(Int, args[1])
    if command == BOUNDS
        distance = parse(Int, args[2])
        ensure(1 <= distance <= size <= 24, "bad parameter")
        ball = volume(size, (distance - 1) ÷ 2)
        hamming = maximum(k for k in 0:size if Int64(power2(k)) * ball <= power2(size))
        griesmer = maximum(k for k in 1:size if sum(cld(distance, power2(i)) for i in 0:k-1) <= size)
        return ["bounds n $size d $distance singleton $(size - distance + 1) hamming $hamming griesmer $griesmer"]
    end
    ensure(1 <= size <= 24, "bad parameter")
    if command == FACTOR
        remaining = (one(Word) << size) | one(Word)
        factor = Word(3)
        divisors = 1
        factors = String[]
        while 2 * (word_length(factor) - 1) <= word_length(remaining) - 1
            exponent = 0
            while true
                divided = poly_divide(remaining, factor)
                divided.remainder != 0 && break
                remaining = divided.quotient
                exponent += 1
            end
            if exponent != 0
                push!(factors, "$(bits(factor, word_length(factor)))^$exponent")
                divisors *= exponent + 1
            end
            factor += Word(2)
        end
        if remaining != 1
            push!(factors, "$(bits(remaining, word_length(remaining)))^1")
            divisors *= 2
        end
        return ["factor $size $(joined(factors)) divisors $divisors"]
    end
    ensure(length(args) == size + 2, "bad length")
    counts = parse.(Int, args[2:end])
    ensure(counts[1] == 1, "bad parameter")
    total = sum(counts)
    numerators = [sum(counts[argument + 1] * krawtchouk(size, index, argument) for argument in 0:size) for index in 0:size]
    feasible = ispow2(total) && all(numerator -> numerator >= 0 && numerator % total == 0, numerators)
    dual = [fraction_text(numerator, total) for numerator in numerators]
    ["macwilliams n $size size $total", "dual $(joined(dual))", "feasible $(yes(feasible))"]
end

function execute(line::String, registry::Dict{String, Code})
    words = String.(split(line, ' '))
    name = first(words)
    form = get(SPECS, name, nothing)
    ensure(!isnothing(form), "unknown command $name")
    args = words[2:end]
    ensure(form.minimum <= length(args) <= form.maximum, "bad arguments")
    for (index, argument) in enumerate(args)
        ensure(valid_word(argument, form.types[min(index, length(form.types))]), "bad arguments")
    end
    sources = Code[]
    for (index, kind) in enumerate(form.types)
        if kind in ('A', 'B')
            ensure(haskey(registry, args[index]), "no code $(args[index])")
            push!(sources, registry[args[index]])
        end
    end
    command = form.kind
    if Int(command) <= Int(PRODUCT)
        code = construct(command, args, sources)
        action = haskey(registry, args[1]) ? "redefined" : "defined"
        registry[args[1]] = code
        return ["$action $(args[1]) n $(code.n) k $(dimension(code))"]
    elseif command in INDEPENDENT
        return independent_report(command, args)
    elseif command == LIST
        names = sort!(collect(keys(registry)))
        rows = ["codes $(length(names))"]
        for code_name in names
            code = registry[code_name]
            push!(rows, "$code_name n $(code.n) k $(dimension(code)) encoder $(encoder(code))")
        end
        return rows
    elseif command == DELETE
        delete!(registry, args[1])
        return ["deleted $(args[1])"]
    elseif command in (ENCODE, SYNDROME, DECODE, BOUNDED, COSET, ERASURE, INTERLEAVE)
        return encoding_report(command, args, only(sources))
    end
    inspect_code(command, args, sources)
end

function main()
    registry = Dict{String, Code}()
    command_count = parse(Int, readline())
    for _ in 1:command_count
        try
            foreach(println, execute(readline(), registry))
        catch problem
            problem isa CommandError || rethrow()
            println("error: ", problem.message)
        end
    end
end

main()
