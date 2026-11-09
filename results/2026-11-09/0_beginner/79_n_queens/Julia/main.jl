function solve_queens(n)
    columns = fill(-1, n)
    first_solution = Int[]
    solutions = 0
    function place(row)
        if row == n
            solutions += 1
            isempty(first_solution) && append!(first_solution, columns)
            return
        end
        for column = 0:(n-1)
            if all(
                previous ->
                    columns[previous+1] != column &&
                    abs(columns[previous+1]-column) != row-previous,
                0:(row-1),
            )
                columns[row+1] = column
                place(row+1)
            end
        end
    end
    place(0)
    return solutions, first_solution
end

function main()
    first_eight = Int[]
    for n = 4:8
        solutions, first_solution = solve_queens(n)
        println("N=", n, ": ", solutions, " solutions")
        n == 8 && (first_eight = first_solution)
    end
    for column in first_eight
        println(repeat(".", column), "Q", repeat(".", 7-column))
    end
end

main()
