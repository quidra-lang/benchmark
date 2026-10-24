function outcome(board)
    lines = [collect(row) for row in board]
    append!(lines,[[board[row][column] for row in 1:3] for column in 1:3])
    push!(lines,[board[i][i] for i in 1:3])
    push!(lines,[board[i][4-i] for i in 1:3])
    for line in lines
        if line[1] != '.' && all(==(line[1]),line)
            return string(line[1]," wins")
        end
    end
    return any(occursin('.',row) for row in board) ? "in progress" : "draw"
end
boards = [["XXX","OO.","O.X"],["X.O",".X.","O.."],["XO.",".OX","XO."],["XOX","XOO","OXX"],["X.O","XO.","O.X"],["XOX","OXO","OXX"]]
for (number,board) in enumerate(boards)
    println("board ",number,": ",outcome(board))
end
