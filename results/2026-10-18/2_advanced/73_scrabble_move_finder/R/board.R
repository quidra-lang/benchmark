PREMIUMS <- c(
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
)

BOARD_SIZE <- 15L
CENTER <- c(8L,8L)
COLUMNS <- LETTERS[seq_len(15L)]
inside <- function(row,column) row >= 1L && row <= BOARD_SIZE && column >= 1L && column <= BOARD_SIZE
square_name <- function(row,column) paste0(COLUMNS[column],row)
move_position <- function(move) if (move$direction == 0L) paste0(move$row,COLUMNS[move$column]) else paste0(
    COLUMNS[move$column],
    move$row
)
parse_position <- function(text) {
  if (grepl("^([1-9]|1[0-5])[A-O]$",text)) return(list(
      row=as.integer(substr(text,1L,nchar(text)-1L)),
      column=match(substr(text,nchar(text),nchar(text)),COLUMNS),
      direction=0L
  ))
  if (grepl("^[A-O]([1-9]|1[0-5])$",text)) return(list(
      row=as.integer(substring(text,2L)),
      column=match(substr(text,1L,1L),COLUMNS),
      direction=1L
  ))
  NULL
}
transpose_board <- function(board) t(board)
board_tiles <- function(board) {
  result <- list()
  for (r in seq_len(BOARD_SIZE)) for (c in seq_len(BOARD_SIZE)) if (board[
      r,
      c
  ] != ".") result[[length(result)+1L]] <- list(
      row=r,
      column=c,
      letter=board[r,c]
  )
  result
}
neighbors <- function(row,column) {
  points <- list(c(row-1L,column),c(row+1L,column),c(row,column-1L),c(row,column+1L))
  Filter(function(p) inside(p[1L],p[2L]),points)
}
run_at <- function(board,row,column,direction) {
  dr <- direction
  dc <- 1L-direction
  while (inside(row-dr,column-dc) && board[row-dr,column-dc] != ".") {
    row <- row-dr
    column <- column-dc
  }
  first_row <- row
  first_column <- column
  letters <- character()
  while (inside(row,column) && board[row,column] != ".") {
    letters <- c(letters,board[row,column])
    row <- row+dr
    column <- column+dc
  }
  list(row=first_row,column=first_column,direction=direction,word=paste(letters,collapse=""))
}
board_words <- function(board) {
  result <- list()
  for (direction in 0L:1L) for (line in seq_len(BOARD_SIZE)) {
    offset <- 1L
    while (offset <= BOARD_SIZE) {
      row <- if (direction == 0L) line else offset
      column <- if (direction == 0L) offset else line
      if (board[row,column] == ".") {
        offset <- offset+1L
        next
      }
      word <- run_at(board,row,column,direction)
      if (nchar(word$word) >= 2L) result[[length(result)+1L]] <- word
      offset <- offset+nchar(word$word)
    }
  }
  result
}
connected <- function(board) {
  occupied <- board != "."
  if (!any(occupied)) return(TRUE)
  first <- which(occupied,arr.ind=TRUE)[1L,]
  pending <- list(as.integer(first))
  seen <- matrix(FALSE,BOARD_SIZE,BOARD_SIZE)
  seen[first[1L],first[2L]] <- TRUE
  while (length(pending)) {
    point <- pending[[length(pending)]]
    pending <- pending[-length(pending)]
    for (neighbor in neighbors(point[1L],point[2L])) if (occupied[neighbor[1L],neighbor[2L]] && !seen[
        neighbor[1L],
        neighbor[2L]
    ]) {
      seen[neighbor[1L],neighbor[2L]] <- TRUE
      pending[[length(pending)+1L]] <- neighbor
    }
  }
  all(seen == occupied)
}
board_display <- function(board) {
  lines <- paste0("   ",paste(COLUMNS,collapse=" "))
  for (row in seq_len(BOARD_SIZE)) {
    premium <- strsplit(PREMIUMS[row],"",fixed=TRUE)[[1L]]
    letters <- ifelse(board[row,] == ".",premium,board[row,])
    lines <- c(lines,paste0(sprintf("%2d",row)," ",paste(letters,collapse=" ")))
  }
  lines
}
