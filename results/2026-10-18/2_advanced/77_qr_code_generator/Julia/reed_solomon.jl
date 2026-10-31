const QR_EXP = let result = ones(Int, 255)
    for exponent in 2:255
        doubled = result[exponent - 1] * 2
        result[exponent] = doubled >= 256 ? xor(doubled, 285) : doubled
    end
    result
end
const QR_LOG = let result = zeros(Int, 256)
    for (exponent, value) in enumerate(QR_EXP)
        result[value + 1] = exponent - 1
    end
    result
end
const QR_GENERATORS = Dict{Int,Vector{Int}}()

gf_multiply(left, right) = left == 0 || right == 0 ? 0 : QR_EXP[mod(
    QR_LOG[left + 1] + QR_LOG[right + 1],
    255
) + 1]
gf_divide(numerator, denominator) = numerator == 0 ? 0 : QR_EXP[mod(
    QR_LOG[numerator + 1] - QR_LOG[denominator + 1],
    255
) + 1]

function rs_generator(degree)
    return get!(QR_GENERATORS, degree) do
        coefficients = [1]
        for exponent in 0:degree - 1
            product = zeros(Int, length(coefficients) + 1)
            for (index, coefficient) in enumerate(coefficients)
                product[index] = xor(product[index], coefficient)
                product[index + 1] = xor(product[index + 1], gf_multiply(coefficient, QR_EXP[exponent + 1]))
            end
            coefficients = product
        end
        coefficients
    end
end

function rs_parity(data, degree)
    polynomial = rs_generator(degree)
    remainder = vcat(data, zeros(Int, degree))
    for index in eachindex(data)
        leading = remainder[index]
        if leading != 0
            for (offset, coefficient) in enumerate(polynomial)
                target = index + offset - 1
                remainder[target] = xor(remainder[target], gf_multiply(leading, coefficient))
            end
        end
    end
    return remainder[end - degree + 1:end]
end

function rs_syndromes(words, degree)
    result = zeros(Int, degree)
    for exponent in 0:degree - 1
        value = 0
        for word in words
            value = xor(gf_multiply(value, QR_EXP[exponent + 1]), word)
        end
        result[exponent + 1] = value
    end
    return result
end

function gf_evaluate(coefficients, argument)
    value = 0
    for coefficient in Iterators.reverse(coefficients)
        value = xor(gf_multiply(value, argument), coefficient)
    end
    return value
end

function rs_correct(received, degree)
    syndromes = rs_syndromes(received, degree)
    all(iszero, syndromes) && return (syndromes, copy(received), Int[])
    locator = vcat(1, zeros(Int, degree))
    previous = copy(locator)
    locator_length, shift, beta = 0, 1, 1
    for step in 0:degree - 1
        discrepancy = syndromes[step + 1]
        for index in 1:locator_length
            discrepancy = xor(discrepancy, gf_multiply(locator[index + 1], syndromes[step - index + 1]))
        end
        if discrepancy == 0
            shift += 1
            continue
        end
        saved = copy(locator)
        multiplier = gf_divide(discrepancy, beta)
        for index in 0:degree - shift
            locator[index + shift + 1] = xor(
                locator[index + shift + 1],
                gf_multiply(multiplier, previous[index + 1])
            )
        end
        if 2 * locator_length <= step
            locator_length = step + 1 - locator_length
            previous = saved
            beta = discrepancy
            shift = 1
        else
            shift += 1
        end
    end
    locator_length > degree ÷ 2 && return (syndromes, nothing, Int[])
    locator = locator[1:locator_length + 1]
    positions = Int[]
    word_count = length(received)
    for index in 0:word_count - 1
        inverse = QR_EXP[mod(255 - (word_count - 1 - index), 255) + 1]
        gf_evaluate(locator, inverse) == 0 && push!(positions, index)
    end
    length(positions) != locator_length && return (syndromes, nothing, Int[])
    omega = zeros(Int, degree)
    for (index, syndrome) in enumerate(syndromes)
        for offset in 0:min(locator_length, degree - index)
            omega[index + offset] = xor(omega[index + offset], gf_multiply(syndrome, locator[offset + 1]))
        end
    end
    derivative = zeros(Int, locator_length)
    for exponent in 1:2:locator_length
        derivative[exponent] = locator[exponent + 1]
    end
    corrected = copy(received)
    for index in positions
        location = QR_EXP[mod(word_count - 1 - index, 255) + 1]
        inverse = QR_EXP[mod(255 - (word_count - 1 - index), 255) + 1]
        denominator = gf_evaluate(derivative, inverse)
        denominator == 0 && return (syndromes, nothing, Int[])
        magnitude = gf_multiply(location, gf_divide(gf_evaluate(omega, inverse), denominator))
        corrected[index + 1] = xor(corrected[index + 1], magnitude)
    end
    any(!iszero, rs_syndromes(corrected, degree)) && return (syndromes, nothing, Int[])
    changed = [index for index in positions if corrected[index + 1] != received[index + 1]]
    return syndromes, corrected, changed
end
