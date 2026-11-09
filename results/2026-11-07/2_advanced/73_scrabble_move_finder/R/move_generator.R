anchors <- function(board) {
  if (!any(board != ".")) return(list(CENTER))
  result <- list()
  for (r in seq_len(BOARD_SIZE)) for (c in seq_len(BOARD_SIZE)) if (board[r,c] == "." && any(vapply(
      neighbors(r,c),
      function(p) board[p[1L],p[2L]] != ".",
      logical(1)
  ))) result[[length(result)+1L]] <- c(r,c)
  result
}
cross_checks <- function(board,trie) {
  result <- list()
  for (r in seq_len(BOARD_SIZE)) for (c in seq_len(BOARD_SIZE)) {
    if (board[r,c] != ".") next
    first <- last <- r
    while (first > 1L && board[first-1L,c] != ".") first <- first-1L
    while (last < BOARD_SIZE && board[last+1L,c] != ".") last <- last+1L
    if (first == last) next
    prefix <- if (first < r) toupper(paste(board[seq.int(first,r-1L),c],collapse="")) else ""
    suffix <- if (r < last) toupper(paste(board[seq.int(r+1L,last),c],collapse="")) else ""
    allowed <- LETTERS[vapply(LETTERS,function(l) has_word(trie,paste0(prefix,l,suffix)),logical(1))]
    result[[paste(r,c,sep=",")]] <- allowed
  }
  result
}
across_moves <- function(board,rack,trie,anchor_squares,checks) {
  result <- list()
  counts <- rack_counts(rack)
  anchor_keys <- vapply(anchor_squares,function(p) paste(p,collapse=","),character(1))
  anchor_squares <- anchor_squares[order(
      vapply(anchor_squares,function(p) p[1L],integer(1)),
      vapply(anchor_squares,function(p) p[2L],integer(1))
  )]
  for (point in anchor_squares) {
    row <- point[1L]
    anchor <- point[2L]
    extend <- function(node,column,word,start) {
      empty <- column > BOARD_SIZE || board[row,column] == "."
      if (empty && column > anchor && trie$terminal[node]) result[[length(result)+1L]] <<- list(
          row=row,
          column=start,
          direction=0L,
          word=word
      )
      if (column > BOARD_SIZE) return(invisible(NULL))
      if (!empty) {
        letter <- board[row,column]
        child <- trie$children[[node]][tile_index(toupper(letter))]
        if (child != 0L) extend(child,column+1L,paste0(word,letter),start)
        return(invisible(NULL))
      }
      key <- paste(row,column,sep=",")
      constrained <- key %in% names(checks)
      allowed <- checks[[key]]
      for (i in which(trie$children[[node]] != 0L)) {
        letter <- LETTERS[i]
        if (constrained && !(letter %in% allowed)) next
        child <- trie$children[[node]][i]
        for (tile in c(i,27L)) if (counts[tile] > 0L) {
          counts[tile] <<- counts[tile]-1L
          written <- if (tile == 27L) tolower(letter) else letter
          extend(child,column+1L,paste0(word,written),start)
          counts[tile] <<- counts[tile]+1L
        }
      }
      invisible(NULL)
    }
    left_part <- function(node,prefix,remaining) {
      extend(node,anchor,prefix,anchor-nchar(prefix))
      if (remaining == 0L) return(invisible(NULL))
      for (i in which(trie$children[[node]] != 0L)) for (tile in c(i,27L)) if (counts[tile] > 0L) {
        counts[tile] <<- counts[tile]-1L
        written <- if (tile == 27L) tolower(LETTERS[i]) else LETTERS[i]
        left_part(trie$children[[node]][i],paste0(prefix,written),remaining-1L)
        counts[tile] <<- counts[tile]+1L
      }
      invisible(NULL)
    }
    if (anchor > 1L && board[row,anchor-1L] != ".") {
      first <- anchor-1L
      while (first > 1L && board[row,first-1L] != ".") first <- first-1L
      prefix <- paste(board[row,seq.int(first,anchor-1L)],collapse="")
      node <- prefix_node(trie,toupper(prefix))
      if (node != 0L) extend(node,anchor,prefix,first)
    } else {
      first <- anchor-1L
      while (first >= 1L && board[row,first] == "." && !(paste(
          row,
          first,
          sep=","
      ) %in% anchor_keys)) first <- first-1L
      left_part(1L,"",anchor-first-1L)
    }
  }
  result
}
placement_key <- function(new_tiles) {
  indices <- order(
      vapply(new_tiles,function(t) t$row,integer(1)),
      vapply(new_tiles,function(t) t$column,integer(1)),
      vapply(new_tiles,function(t) t$letter,character(1)),
      method="radix"
  )
  paste(
      vapply(new_tiles[indices],function(t) paste(t$row,t$column,t$letter,sep=":"),character(1)),
      collapse=";"
  )
}
generate_moves <- function(board,rack,trie) {
  anchor_squares <- anchors(board)
  across <- across_moves(board,rack,trie,anchor_squares,cross_checks(board,trie))
  transposed <- transpose_board(board)
  down <- across_moves(transposed,rack,trie,lapply(anchor_squares,rev),cross_checks(transposed,trie))
  candidates <- c(across,lapply(down,function(m) list(row=m$column,column=m$row,direction=1L,word=m$word)))
  result <- list()
  keys <- character()
  for (move in candidates) {
    new_tiles <- placement(board,move)
    if (length(new_tiles) == 1L && move$direction == 1L) {
      tile <- new_tiles[[1L]]
      if (nchar(run_at(apply_move(board,new_tiles),tile$row,tile$column,0L)$word) >= 2L) next
    }
    key <- placement_key(new_tiles)
    index <- match(key,keys)
    if (is.na(index)) {
      keys <- c(keys,key)
      result[[length(result)+1L]] <- move
    } else result[[index]] <- move
  }
  result
}
