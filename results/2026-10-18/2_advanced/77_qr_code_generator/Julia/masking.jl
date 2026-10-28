function mask_condition(mask, x, y)
    mask == 0 && return (x + y) % 2 == 0
    mask == 1 && return y % 2 == 0
    mask == 2 && return x % 3 == 0
    mask == 3 && return (x + y) % 3 == 0
    mask == 4 && return (y ÷ 2 + x ÷ 3) % 2 == 0
    mask == 5 && return (x * y) % 2 + (x * y) % 3 == 0
    mask == 6 && return ((x * y) % 2 + (x * y) % 3) % 2 == 0
    return ((x + y) % 2 + (x * y) % 3) % 2 == 0
end

function apply_mask(symbol, positions, mask)
    result = copy(symbol)
    for (x, y) in positions
        mask_condition(mask, x, y) && (result[y + 1, x + 1] = xor(result[y + 1, x + 1], 1))
    end
    return result
end

function mask_penalties(symbol)
    side = size(symbol, 1)
    n1, n2, n3 = 0, 0, 0
    patterns = ([1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0], [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1])
    lines = [collect(symbol[y, :]) for y in 1:side]
    append!(lines, [collect(symbol[:, x]) for x in 1:side])
    for line in lines
        run = 1
        for index in 2:side
            if line[index] == line[index - 1]
                run += 1
            else
                run >= 5 && (n1 += run - 2)
                run = 1
            end
        end
        run >= 5 && (n1 += run - 2)
        for index in 1:side - 10
            line[index:index + 10] in patterns && (n3 += 40)
        end
    end
    for y in 1:side - 1, x in 1:side - 1
        symbol[y, x] == symbol[y, x + 1] == symbol[y + 1, x] == symbol[y + 1, x + 1] && (n2 += 3)
    end
    n4 = 10 * (abs(20 * sum(symbol) - 10 * side * side) ÷ (side * side))
    return n1, n2, n3, n4
end
