const QR_DATA, QR_FUNCTION, QR_FORMAT, QR_VERSION = 0, 1, 2, 3

function polynomial_remainder(value, divisor)
    while value != 0 && ndigits(value; base=2) >= ndigits(divisor; base=2)
        value = xor(value, divisor << (ndigits(value; base=2) - ndigits(divisor; base=2)))
    end
    return value
end

function format_information(level, mask)
    indicator = Dict("L" => 1, "M" => 0, "Q" => 3, "H" => 2)[level]
    shifted = (8 * indicator + mask) << 10
    return xor(shifted + polynomial_remainder(shifted, 1335), 21522)
end

function version_information(version)
    shifted = version << 12
    return shifted + polynomial_remainder(shifted, 7973)
end

function format_positions(side)
    first_copy = [(8, index) for index in 0:5]
    append!(first_copy, [(8, 7), (8, 8), (7, 8)])
    append!(first_copy, [(14 - index, 8) for index in 9:14])
    second_copy = [(side - 1 - index, 8) for index in 0:7]
    append!(second_copy, [(8, side - 15 + index) for index in 8:14])
    return first_copy, second_copy
end

function version_positions(side)
    first_copy = [(side - 11 + index % 3, index ÷ 3) for index in 0:17]
    second_copy = [(index ÷ 3, side - 11 + index % 3) for index in 0:17]
    return first_copy, second_copy
end

function write_matrix_value!(symbol, positions, value)
    for (index, (x, y)) in enumerate(positions)
        symbol[y + 1, x + 1] = (value >> (index - 1)) & 1
    end
end

function read_matrix_value(symbol, positions)
    value = 0
    for (index, (x, y)) in enumerate(positions)
        value |= symbol[y + 1, x + 1] << (index - 1)
    end
    return value
end

function function_matrix(version, alignments)
    side = 17 + 4 * version
    symbol = zeros(Int, side, side)
    areas = zeros(Int, side, side)
    for (cx, cy) in ((3, 3), (side - 4, 3), (3, side - 4))
        for dy in -4:4, dx in -4:4
            x, y = cx + dx, cy + dy
            if 0 <= x < side && 0 <= y < side
                distance = max(abs(dx), abs(dy))
                symbol[y + 1, x + 1] = Int(distance in (0, 1, 3))
                areas[y + 1, x + 1] = QR_FUNCTION
            end
        end
    end
    for index in 8:side - 9
        symbol[index + 1, 7] = symbol[7, index + 1] = Int(iseven(index))
        areas[index + 1, 7] = areas[7, index + 1] = QR_FUNCTION
    end
    if !isempty(alignments)
        low, high = first(alignments), last(alignments)
        excluded = Set([(low, low), (low, high), (high, low)])
        for cy in alignments, cx in alignments
            (cx, cy) in excluded && continue
            for dy in -2:2, dx in -2:2
                symbol[cy + dy + 1, cx + dx + 1] = Int(max(abs(dx), abs(dy)) != 1)
                areas[cy + dy + 1, cx + dx + 1] = QR_FUNCTION
            end
        end
    end
    symbol[side - 7, 9] = 1
    areas[side - 7, 9] = QR_FUNCTION
    for positions in format_positions(side), (x, y) in positions
        areas[y + 1, x + 1] = QR_FORMAT
        symbol[y + 1, x + 1] = 0
    end
    if version >= 7
        for positions in version_positions(side)
            for (x, y) in positions
                areas[y + 1, x + 1] = QR_VERSION
            end
            write_matrix_value!(symbol, positions, version_information(version))
        end
    end
    return symbol, areas
end

function reading_order(areas)
    side = size(areas, 1)
    right_columns = vcat(collect(side - 1:-2:8), [5, 3, 1])
    positions = Tuple{Int,Int}[]
    for (pair, right) in enumerate(right_columns)
        rows = isodd(pair) ? (side - 1:-1:0) : (0:side - 1)
        for y in rows, x in (right, right - 1)
            areas[y + 1, x + 1] == QR_DATA && push!(positions, (x, y))
        end
    end
    return positions
end
