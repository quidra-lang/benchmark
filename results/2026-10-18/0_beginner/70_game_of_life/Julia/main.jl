function main()
    initial = [".#......","..#.....","###.....","........","........","........",".....###","........"]
    board = [initial[row][column] == '#' for row in 1:8, column in 1:8]
    for generation in 0:4
        println("generation ",generation)
        for row in 1:8
            println(join([board[row,column] ? '#' : '.' for column in 1:8]))
        end
        generation == 4 && break
        following = falses(8,8)
        for row in 1:8, column in 1:8
            neighbors = 0
            for dr in -1:1, dc in -1:1
                dr == 0 && dc == 0 && continue
                r,c = row+dr,column+dc
                if 1 <= r <= 8 && 1 <= c <= 8
                    neighbors += board[r,c]
                end
            end
            following[row,column] = neighbors == 3 || (board[row,column] && neighbors == 2)
        end
        board = following
    end
    println("alive: ",count(board))
end
main()
