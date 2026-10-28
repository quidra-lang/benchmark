const RACK_SIZE = 7
const BINGO_BONUS = 50
function move_cells(move)
    [(
        move.row+move.direction*(i-1),
        move.column+(1-move.direction)*(i-1),
        letter
    ) for (i,letter) in enumerate(move.word)]
end
placement(board,move) = [(r,c,l) for (r,c,l) in move_cells(move) if board[r,c]=='.']
function apply_move(board,new_tiles)
    result = copy(board)
    for (r,c,l) in new_tiles
        result[r,c] = l
    end
    result
end
function cross_words(board,move)
    new_tiles = placement(board,move)
    after = apply_move(board,new_tiles)
    result = NamedTuple[]
    for (r,c,_) in new_tiles
        word = run_at(after,r,c,1-move.direction)
        length(word.word)>=2 && push!(result,word)
    end
    result
end
function word_score(board,word,values)
    score,multiplier = 0,1
    for (r,c,l) in move_cells(word)
        value = isuppercase(l) ? values[tile_index(l)] : 0
        if board[r,c]=='.'
            premium = PREMIUMS[r][c]
            value *= premium=='+' ? 2 : premium=='^' ? 3 : 1
            multiplier *= premium=='*' ? 2 : premium=='#' ? 3 : 1
        end
        score += value
    end
    score*multiplier
end
function score_move(board,move,values)
    words = [move]
    append!(words,cross_words(board,move))
    scores = [word_score(board,w,values) for w in words]
    new_tiles = placement(board,move)
    (
        score=sum(scores)+(length(new_tiles)==RACK_SIZE ? BINGO_BONUS : 0),
        new_tiles=new_tiles,
        words=collect(zip(words,scores))
    )
end
