function main()
    puzzle = ["800025000","070080005","260400070","000001900","010000040","600200000","900010000","700000004","020000036"]
    board = [Int(puzzle[row][column])-Int('0') for row in 1:9, column in 1:9]
    placements = Ref(0)
    function solve()
        for row in 1:9, column in 1:9
            if board[row,column] == 0
                for digit in 1:9
                    digit in board[row,:] && continue
                    digit in board[:,column] && continue
                    block_row,block_column = 3*div(row-1,3)+1,3*div(column-1,3)+1
                    digit in board[block_row:block_row+2,block_column:block_column+2] && continue
                    board[row,column] = digit
                    placements[] += 1
                    solve() && return true
                    board[row,column] = 0
                end
                return false
            end
        end
        return true
    end
    solve()
    for row in eachrow(board)
        println(join(row," "))
    end
    println("placements: ",placements[])
end
main()
