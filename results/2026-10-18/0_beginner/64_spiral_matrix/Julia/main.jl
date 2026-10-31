using Printf

function main()
    matrix = zeros(Int, 5, 6)
    directions = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    row, column, direction = 1, 1, 1
    for value = 1:30
        matrix[row, column] = value
        value == 30 && break
        dr, dc = directions[direction]
        next_row, next_column = row+dr, column+dc
        if !(1 <= next_row <= 5 && 1 <= next_column <= 6) ||
           matrix[next_row, next_column] != 0
            direction = mod1(direction+1, 4)
            dr, dc = directions[direction]
        end
        row += dr
        column += dc
    end
    for row in eachrow(matrix)
        println(join(@sprintf("%3d", value) for value in row))
    end
end

main()
