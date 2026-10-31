const PREMIUMS = [
    "#..+...#...+..#",
    ".*...^...^...*.",
    "..*...+.+...*..",
    "+..*...+...*..+",
    "....*.....*....",
    ".^...^...^...^.",
    "..+...+.+...+..",
    "#..+...*...+..#",
    "..+...+.+...+..",
    ".^...^...^...^.",
    "....*.....*....",
    "+..*...+...*..+",
    "..*...+.+...*..",
    ".*...^...^...*.",
    "#..+...#...+..#"
]

const BOARD_SIZE = 15
const CENTER = (8,8)
const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const COLUMNS = "ABCDEFGHIJKLMNO"
inside(row,column) = 1<=row<=BOARD_SIZE && 1<=column<=BOARD_SIZE
square_name(row,column) = "$(COLUMNS[column])$row"
move_position(move) = move.direction==0 ? "$(move.row)$(COLUMNS[move.column])" : "$(COLUMNS[move.column])$(move.row)"
function parse_position(text)
    if occursin(r"^([1-9]|1[0-5])[A-O]$",text)
        return (row=parse(Int,text[1:end-1]),column=Int(text[end])-Int('A')+1,direction=0)
    elseif occursin(r"^[A-O]([1-9]|1[0-5])$",text)
        return (row=parse(Int,text[2:end]),column=Int(text[1])-Int('A')+1,direction=1)
    end
    nothing
end
transpose_board(board) = permutedims(board)
board_tiles(board) = [(r,c,board[r,c]) for r in 1:BOARD_SIZE for c in 1:BOARD_SIZE if board[r,c]!='.']
neighbors(row,column) = [(r,c) for (r,c) in (
    (row-1,column),
    (row+1,column),
    (row,column-1),
    (row,column+1)
) if inside(r,c)]
function run_at(board,row,column,direction)
    dr,dc = direction,1-direction
    while inside(row-dr,column-dc) && board[row-dr,column-dc]!='.'
        row,column = row-dr,column-dc
    end
    first_row,first_column,letters = row,column,Char[]
    while inside(row,column) && board[row,column]!='.'
        push!(letters,board[row,column])
        row,column = row+dr,column+dc
    end
    (row=first_row,column=first_column,direction=direction,word=join(letters))
end
function board_words(board)
    result = NamedTuple[]
    for direction in 0:1,line in 1:BOARD_SIZE
        offset = 1
        while offset<=BOARD_SIZE
            row,column = direction==0 ? (line,offset) : (offset,line)
            if board[row,column]=='.'
                offset += 1
                continue
            end
            word = run_at(board,row,column,direction)
            length(word.word)>=2 && push!(result,word)
            offset += length(word.word)
        end
    end
    result
end
function connected(board)
    occupied = Set((r,c) for (r,c,_) in board_tiles(board))
    isempty(occupied) && return true
    pending = [first(occupied)]
    seen = Set(pending)
    while !isempty(pending)
        r,c = pop!(pending)
        for neighbor in neighbors(r,c)
            if neighbor in occupied && !(neighbor in seen)
                push!(seen,neighbor)
                push!(pending,neighbor)
            end
        end
    end
    seen==occupied
end
function board_display(board)
    lines = ["   "*join(COLUMNS,' ')]
    for row in 1:BOARD_SIZE
        letters = [board[row,column]=='.' ? PREMIUMS[row][column] : board[
            row,
            column
        ] for column in 1:BOARD_SIZE]
        push!(lines,lpad(string(row),2)*" "*join(letters,' '))
    end
    lines
end
