RACK_SIZE <- 7L
BINGO_BONUS <- 50L
move_cells <- function(move) {
  letters <- strsplit(move$word,"",fixed=TRUE)[[1L]]
  lapply(
      seq_along(letters),
      function(i) list(
          row=move$row+move$direction*(i-1L),
          column=move$column+(1L-move$direction)*(i-1L),
          letter=letters[i]
      )
  )
}
placement <- function(board,move) Filter(function(t) board[t$row,t$column] == ".",move_cells(move))
apply_move <- function(board,new_tiles) {
  result <- board
  for (tile in new_tiles) result[tile$row,tile$column] <- tile$letter
  result
}
cross_words <- function(board,move) {
  new_tiles <- placement(board,move)
  after <- apply_move(board,new_tiles)
  result <- list()
  for (tile in new_tiles) {
    word <- run_at(after,tile$row,tile$column,1L-move$direction)
    if (nchar(word$word) >= 2L) result[[length(result)+1L]] <- word
  }
  result
}
word_score <- function(board,word,values) {
  score <- 0L
  multiplier <- 1L
  for (tile in move_cells(word)) {
    r <- tile$row
    c <- tile$column
    l <- tile$letter
    value <- if (l %in% LETTERS) values[tile_index(l)] else 0L
    if (board[r,c] == ".") {
      premium <- substr(PREMIUMS[r],c,c)
      value <- value*(if (premium == "+") 2L else if (premium == "^") 3L else 1L)
      multiplier <- multiplier*(if (premium == "*") 2L else if (premium == "#") 3L else 1L)
    }
    score <- score+value
  }
  score*multiplier
}
score_move <- function(board,move,values) {
  words <- c(list(move),cross_words(board,move))
  scores <- vapply(words,function(word) word_score(board,word,values),integer(1))
  new_tiles <- placement(board,move)
  list(
      score=sum(scores)+if (length(new_tiles) == RACK_SIZE) BINGO_BONUS else 0L,
      new_tiles=new_tiles,
      words=lapply(seq_along(words),function(i) list(word=words[[i]],score=scores[i]))
  )
}
