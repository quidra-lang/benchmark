source("board.R")
source("dictionary_trie.R")
source("scoring.R")
source("move_generator.R")
source("game.R")

VOWELS <- c("A","E","I","O","U")
STRATEGIES <- c("score","tiles","equity")
words <- function(...) paste(...,collapse=" ")
attributes_text <- function(...) {
  items <- list(...)
  paste(paste0(names(items),"=",vapply(items,as.character,character(1))),collapse=" ")
}
valid_name <- function(value) grepl("^[a-z0-9_]{1,20}$",value)
valid_number <- function(value,minimum,maximum) {
  if (!grepl("^(0|[1-9][0-9]*)$",value)) return(FALSE)
  upper <- as.character(maximum)
  if (nchar(value) > nchar(upper) || (nchar(value) == nchar(upper) && value > upper)) return(FALSE)
  as.integer(value) >= minimum
}
characters <- function(value) strsplit(value,"",fixed=TRUE)[[1L]]
valid_rack <- function(value) nchar(value) >= 1L && nchar(value) <= RACK_SIZE && all(characters(value) %in% TILE_ORDER)
collection <- function(value) if (nzchar(value)) paste(
    sort(characters(value),method="radix"),
    collapse=""
) else "-"
tile_kind <- function(letter) ifelse(letter %in% LETTERS,letter,"?")
remove_tiles <- function(rack,removed) {
  counts <- rack_counts(rack)
  for (letter in characters(removed)) counts[tile_index(letter)] <- counts[tile_index(letter)]-1L
  paste(sort(rep(TILE_ORDER,counts),method="radix"),collapse="")
}
notation <- function(e) paste(move_position(e$move),e$move$word)
strategy_sort <- function(moves,strategy="score") {
  if (!length(moves)) return(moves)
  prefix <- if (strategy == "tiles") -vapply(
      moves,
      function(e) length(e$new_tiles),
      integer(1)
  ) else if (strategy == "equity") -vapply(
      moves,
      function(e) e$score+e$value,
      integer(1)
  ) else rep(0L,length(moves))
  indices <- order(
      prefix,
      -vapply(moves,function(e) e$score,integer(1)),
      vapply(moves,function(e) e$move$row,integer(1)),
      vapply(moves,function(e) e$move$column,integer(1)),
      vapply(moves,function(e) e$move$direction,integer(1)),
      vapply(moves,function(e) e$move$word,character(1)),
      method="radix"
  )
  moves[indices]
}
new_totals <- function() new.env(hash=TRUE,parent=emptyenv())
counter <- function(totals,key) if (is.null(totals[[key]])) 0L else totals[[key]]
bump <- function(totals,key,amount=1L) totals[[key]] <- counter(totals,key)+amount
counter_text <- function(totals,keys) paste(
    vapply(keys,function(key) paste0(key,"=",counter(totals,key)),character(1)),
    collapse=" "
)
read_inputs <- function() {
  values <- counts <- weights <- integer(27L)
  for (line in readLines("input/tiles.txt",warn=FALSE)) {
    if (!nzchar(line) || startsWith(line,"#")) next
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    i <- tile_index(f[1L])
    values[i] <- as.integer(f[2L])
    counts[i] <- as.integer(f[3L])
    weights[i] <- as.integer(f[4L])
  }
  trie <- new_trie()
  statistics <- new_totals()
  lengths <- integer(15L)
  for (line in readLines("input/dictionary.txt",warn=FALSE)) {
    if (!nzchar(line) || startsWith(line,"#")) next
    bump(statistics,"lines")
    if (!grepl("^[A-Z]{2,15}$",line)) bump(
        statistics,
        "skipped"
    ) else if (add_word(trie,line)) lengths[nchar(line)] <- lengths[nchar(line)]+1L else bump(
        statistics,
        "duplicates"
    )
  }
  jobs <- list()
  current <- NULL
  for (line in readLines("input/jobs.txt",warn=FALSE)) {
    if (is.null(current)) {
      if (nzchar(line) && !startsWith(line,"#")) current <- line
    } else if (line == "END") {
      jobs[[length(jobs)+1L]] <- current
      current <- NULL
    } else current <- c(current,line)
  }
  dictionary_lines <- c(
      paste(
          "DICTIONARY",
          attributes_text(
              lines=counter(statistics,"lines"),
              words=trie$words,
              skipped=counter(statistics,"skipped"),
              duplicates=counter(statistics,"duplicates"),
              nodes=length(trie$children)
          )
      ),
      paste0("lengths",paste0(" ",which(lengths > 0L),"=",lengths[lengths > 0L],collapse=""))
  )
  a <- list(
      values=values,
      counts=counts,
      weights=weights,
      trie=trie,
      topn_totals=new_totals(),
      validation_totals=new_totals(),
      game_totals=new_totals()
  )
  list(program=a,jobs=jobs,dictionary_lines=dictionary_lines)
}
make_board <- function(rows) matrix(
    unlist(strsplit(rows,"",fixed=TRUE),use.names=FALSE),
    BOARD_SIZE,
    BOARD_SIZE,
    byrow=TRUE
)
used_tiles <- function(board) {
  occupied <- board[board != "."]
  tabulate(tile_index(tile_kind(occupied)),nbins=27L)
}
tile_error <- function(a,board,rack) {
  counts <- used_tiles(board)+rack_counts(rack)
  for (i in seq_along(TILE_ORDER)) if (counts[i] > a$counts[i]) return(paste("too many",TILE_ORDER[i]))
  NULL
}
unseen <- function(a,board,rack) paste(
    rep(TILE_ORDER,a$counts-used_tiles(board)-rack_counts(rack)),
    collapse=""
)
board_error <- function(a,rows,rack) {
  if (length(rows) != BOARD_SIZE) return(paste("board rows",length(rows)))
  for (i in seq_along(rows)) if (!grepl("^[.A-Za-z]{15}$",rows[i])) return(paste("bad board row",i))
  board <- make_board(rows)
  error <- tile_error(a,board,rack)
  if (!is.null(error)) return(error)
  if (any(board != ".") && board[CENTER[1L],CENTER[2L]] == ".") return("center empty")
  if (!connected(board)) return("disconnected")
  for (word in board_words(board)) if (!has_word(a$trie,toupper(word$word))) return(words(
      "unknown word",
      word$word,
      "at",
      move_position(word)
  ))
  NULL
}
job_error <- function(a,job,seen) {
  f <- strsplit(job[1L]," ",fixed=TRUE)[[1L]]
  kind <- f[1L]
  name <- f[2L]
  if (!valid_name(name)) return("bad name")
  if (name %in% seen) return("duplicate name")
  if (kind == "TOPN") {
    if (!valid_number(f[3L],1L,99L)) return("bad count")
    if (!(f[4L] %in% STRATEGIES)) return("bad order")
    rack <- strsplit(job[2L]," ",fixed=TRUE)[[1L]][2L]
    if (!valid_rack(rack)) return("bad rack")
    return(board_error(a,job[-seq_len(3L)],rack))
  }
  if (kind == "VALIDATE") {
    rows <- character()
    for (line in job[-seq_len(2L)]) {
      if (startsWith(line,"MOVE")) break
      rows <- c(rows,line)
    }
    return(board_error(a,rows,""))
  }
  if (!valid_number(f[3L],1L,2147483646L)) return("bad seed")
  if (length(job)-1L < 2L || length(job)-1L > 4L) return(paste("bad player count",length(job)-1L))
  names <- character()
  for (i in seq_len(length(job)-1L)) {
    player <- strsplit(job[i+1L]," ",fixed=TRUE)[[1L]]
    if (!valid_name(player[2L]) || !(player[3L] %in% STRATEGIES) || (kind == "GAME" && !valid_number(
        player[4L],
        0L,
        99L
    ))) return(paste("bad player",i))
    if (player[2L] %in% names) return(paste("duplicate player",i))
    names <- c(names,player[2L])
  }
  NULL
}
leave_value <- function(a,rack) {
  counts <- rack_counts(rack)
  duplicates <- sum(pmax(0L,counts[seq_len(26L)]-1L))
  vowels <- sum(counts[tile_index(VOWELS)])
  consonants <- sum(counts[which(!(LETTERS %in% VOWELS))])
  sum(a$weights[tile_index(characters(rack))])-4L*duplicates-3L*max(0L,abs(vowels-consonants)-1L)
}
best_leave <- function(a,rack) {
  letters <- characters(rack)
  candidates <- character()
  for (mask in seq_len(bitwShiftL(1L,length(letters))-1L)-1L) {
    chosen <- letters[vapply(
        seq_along(letters),
        function(i) bitwAnd(mask,bitwShiftL(1L,i-1L)) != 0L,
        logical(1)
    )]
    candidates <- c(candidates,paste(sort(chosen,method="radix"),collapse=""))
  }
  candidates <- unique(candidates)
  values <- vapply(candidates,function(k) leave_value(a,k),integer(1))
  candidates[order(-values,-nchar(candidates),candidates,method="radix")[1L]]
}
evaluate_move <- function(a,board,rack,move) {
  scored <- score_move(board,move,a$values)
  removed <- paste(vapply(scored$new_tiles,function(t) tile_kind(t$letter),character(1)),collapse="")
  leave <- remove_tiles(rack,removed)
  word_list <- paste(
      vapply(scored$words,function(w) paste0(w$word$word,":",w$score),character(1)),
      collapse=","
  )
  list(
      move=move,
      score=scored$score,
      new_tiles=scored$new_tiles,
      words=word_list,
      leave=leave,
      value=leave_value(a,leave)
  )
}
legal_moves <- function(a,board,rack) strategy_sort(lapply(
    generate_moves(board,rack,a$trie),
    function(m) evaluate_move(a,board,rack,m)
))
position_summary <- function(board) {
  listed <- board_words(board)
  occupied <- board_tiles(board)
  longest <- if (length(listed)) listed[[which.max(vapply(
      listed,
      function(w) nchar(w$word),
      integer(1)
  ))]]$word else "-"
  blanks <- sum(vapply(occupied,function(t) t$letter %in% letters,logical(1)))
  counts <- vapply(
      c("#","*","^","+"),
      function(p) sum(vapply(occupied,function(t) substr(PREMIUMS[t$row],t$column,t$column) == p,logical(1))),
      integer(1)
  )
  paste(
      "position",
      attributes_text(
          tiles=length(occupied),
          words=length(listed),
          longest=longest,
          blanks=blanks,
          premiums=paste0("TW:",counts[1L],",DW:",counts[2L],",TL:",counts[3L],",DL:",counts[4L])
      )
  )
}
topn <- function(a,job) {
  f <- strsplit(job[1L]," ",fixed=TRUE)[[1L]]
  name <- f[2L]
  n <- as.integer(f[3L])
  order <- f[4L]
  rack <- strsplit(job[2L]," ",fixed=TRUE)[[1L]][2L]
  board <- make_board(job[-seq_len(3L)])
  moves <- legal_moves(a,board,rack)
  shown <- head(strategy_sort(moves,order),n)
  hidden <- unseen(a,board,rack)
  checks <- list(cross_checks(board,a$trie),cross_checks(transpose_board(board),a$trie))
  statistics <- vapply(
      checks,
      function(check) paste(length(check),sum(lengths(check) == 0L),sum(lengths(check)),sep=","),
      character(1)
  )
  tiles <- characters(rack)
  vowels <- sum(tiles %in% VOWELS)
  consonants <- sum(tiles %in% LETTERS & !(tiles %in% VOWELS))
  across <- sum(vapply(moves,function(m) m$move$direction == 0L,logical(1)))
  bingos <- sum(vapply(moves,function(m) length(m$new_tiles) == RACK_SIZE,logical(1)))
  blanks <- sum(vapply(
      moves,
      function(m) any(vapply(m$new_tiles,function(t) t$letter %in% letters,logical(1))),
      logical(1)
  ))
  lines <- c(
      words("TOPN",name,attributes_text(n=n,order=order,rack=collection(rack))),
      paste("board",attributes_text(tiles=length(board_tiles(board)),anchors=length(anchors(board)))),
      paste("unseen",attributes_text(count=nchar(hidden),tiles=collection(hidden))),
      paste(
          "rack",
          attributes_text(
              vowels=vowels,
              consonants=consonants,
              blanks=sum(tiles == "?"),
              value=collection_points(rack,a$values)
          )
      ),
      paste("checks",attributes_text(across=statistics[1L],down=statistics[2L])),
      paste(
          "moves",
          attributes_text(
              total=length(moves),
              across=across,
              down=length(moves)-across,
              bingos=bingos,
              blanks=blanks
          )
      )
  )
  scores <- vapply(seq_len(RACK_SIZE),function(t) {
    matching <- vapply(Filter(function(m) length(m$new_tiles) == t,moves),function(m) m$score,integer(1))
    paste0(t,"=",if (length(matching)) max(matching) else "-")
  },character(1))
  lines <- c(lines,paste("best_by_tiles",paste(scores,collapse=" ")))
  keep <- best_leave(a,rack)
  lines <- c(lines,paste("exchange",attributes_text(keep=collection(keep),value=leave_value(a,keep))))
  found <- anagrams(a$trie,rack)
  found <- found[order(-nchar(found),found,method="radix")]
  lines <- c(
      lines,
      paste(
          "anagrams",
          attributes_text(
              total=length(found),
              top=if (length(found)) paste(head(found,10L),collapse=",") else "-"
          )
      )
  )
  for (word in board_words(board)) {
    if (nchar(word$word) < 3L) next
    front <- paste(
        LETTERS[vapply(LETTERS,function(l) has_word(a$trie,paste0(l,toupper(word$word))),logical(1))],
        collapse=""
    )
    back <- paste(
        LETTERS[vapply(LETTERS,function(l) has_word(a$trie,paste0(toupper(word$word),l)),logical(1))],
        collapse=""
    )
    if (nzchar(front) || nzchar(back)) lines <- c(
        lines,
        words(
            "hook",
            move_position(word),
            word$word,
            attributes_text(front=if (nzchar(front)) front else "-",back=if (nzchar(back)) back else "-")
        )
    )
  }
  nets <- integer()
  if (nchar(hidden) >= 1L && nchar(hidden) <= RACK_SIZE && length(shown)) {
    for (move in shown) {
      replies <- legal_moves(a,apply_move(board,move$new_tiles),hidden)
      nets <- c(nets,move$score-if (length(replies)) replies[[1L]]$score else 0L)
    }
    best <- which.max(nets)
    lines <- c(lines,paste("endgame",attributes_text(opponent=collection(hidden),best=best,net=nets[best])))
  }
  for (i in seq_along(shown)) {
    m <- shown[[i]]
    line <- words(
        i,
        notation(m),
        attributes_text(score=m$score,tiles=length(m$new_tiles),leave=collection(m$leave),value=m$value)
    )
    if (length(nets)) line <- paste0(line," net=",nets[i])
    lines <- c(lines,paste0(line," words=",m$words))
  }
  bump(a$topn_totals,"moves",length(moves))
  bump(a$topn_totals,"bingos",bingos)
  lines
}
record_error <- function(a,board,player,rack,action) {
  invalid <- function(reason) list(error=reason,move=NULL)
  valid <- function(move=NULL) list(error=NULL,move=move)
  if (!valid_name(player)) return(invalid("bad player"))
  if (!valid_rack(rack)) return(invalid("bad rack"))
  error <- tile_error(a,board,rack)
  if (!is.null(error)) return(invalid(error))
  if (length(action) == 1L && action[1L] == "PASS") return(valid())
  if (action[1L] == "EXCHANGE") {
    returned <- action[2L]
    if (!valid_rack(returned)) return(invalid("bad exchange"))
    available <- rack_counts(rack)
    requested <- rack_counts(returned)
    for (l in characters(returned)) if (requested[tile_index(l)] > available[tile_index(l)]) return(invalid(paste(
        "rack lacks",
        l
    )))
    return(valid())
  }
  parsed <- parse_position(action[1L])
  if (is.null(parsed)) return(invalid("bad position"))
  word <- action[2L]
  if (!grepl("^[A-Za-z]{2,15}$",word)) return(invalid("bad word"))
  move <- c(parsed,list(word=word))
  cells <- move_cells(move)
  if (any(vapply(cells,function(t) !inside(t$row,t$column),logical(1)))) return(invalid("off board"))
  for (tile in cells) if (!(board[tile$row,tile$column] %in% c(".",tile$letter))) return(invalid(paste(
      "mismatch at",
      square_name(tile$row,tile$column)
  )))
  dr <- move$direction
  dc <- 1L-move$direction
  before <- c(move$row-dr,move$column-dc)
  after <- c(move$row+dr*nchar(word),move$column+dc*nchar(word))
  if (any(vapply(
      list(before,after),
      function(p) inside(p[1L],p[2L]) && board[p[1L],p[2L]] != ".",
      logical(1)
  ))) return(invalid("not whole word"))
  new_tiles <- placement(board,move)
  if (!length(new_tiles)) return(invalid("no new tiles"))
  available <- rack_counts(rack)
  for (tile in new_tiles) {
    kind <- tile_kind(tile$letter)
    i <- tile_index(kind)
    if (available[i] == 0L) return(invalid(paste("rack lacks",kind)))
    available[i] <- available[i]-1L
  }
  if (!any(board != ".")) {
    if (!any(vapply(
        new_tiles,
        function(t) t$row == CENTER[1L] && t$column == CENTER[2L],
        logical(1)
    ))) return(invalid("center not covered"))
  } else {
    touching <- any(vapply(
        new_tiles,
        function(t) any(vapply(neighbors(t$row,t$column),function(p) board[p[1L],p[2L]] != ".",logical(1))),
        logical(1)
    ))
    if (!touching) return(invalid("not connected"))
  }
  for (formed in c(
      list(move),
      cross_words(board,move)
  )) if (!has_word(a$trie,toupper(formed$word))) return(invalid(words(
      "unknown word",
      formed$word,
      "at",
      move_position(formed)
  )))
  valid(move)
}
validate_job <- function(a,job) {
  name <- strsplit(job[1L]," ",fixed=TRUE)[[1L]][2L]
  board <- make_board(job[seq.int(3L,2L+BOARD_SIZE)])
  records <- job[-seq_len(2L+BOARD_SIZE)]
  lines <- paste("VALIDATE",name)
  player_order <- character()
  players <- list()
  totals <- new_totals()
  for (i in seq_along(records)) {
    f <- strsplit(records[i]," ",fixed=TRUE)[[1L]]
    player <- f[2L]
    rack <- f[3L]
    action <- f[-seq_len(3L)]
    prefix <- words("move",i,player,paste(action,collapse=" "))
    checked <- record_error(a,board,player,rack,action)
    error <- checked$error
    move <- checked$move
    if (is.null(error) || error != "bad player") {
      if (is.null(players[[player]])) {
        players[[player]] <- new_totals()
        player_order <- c(player_order,player)
      }
      bump(players[[player]],"moves")
    }
    if (!is.null(error)) {
      lines <- c(lines,paste(prefix,"invalid",error))
      bump(totals,"invalid")
      next
    }
    legal <- legal_moves(a,board,rack)
    best <- if (length(legal)) legal[[1L]]$score else 0L
    score <- 0L
    evaluated <- NULL
    rank <- 0L
    if (!is.null(move)) {
      evaluated <- evaluate_move(a,board,rack,move)
      score <- evaluated$score
      target <- placement_key(evaluated$new_tiles)
      rank <- which(vapply(legal,function(e) placement_key(e$new_tiles) == target,logical(1)))[1L]
    }
    statistics <- players[[player]]
    bump(statistics,"valid")
    bump(statistics,"score",score)
    bump(statistics,"loss",best-score)
    bump(totals,"valid")
    bump(totals,"score",score)
    bump(totals,"loss",best-score)
    bump(totals,"best",best)
    if (is.null(move)) lines <- c(
        lines,
        paste(
            prefix,
            attributes_text(score=0L,total=counter(statistics,"score"),moves=length(legal),best=best)
        )
    ) else {
      lines <- c(
          lines,
          paste(
              prefix,
              attributes_text(
                  score=score,
                  total=counter(statistics,"score"),
                  tiles=length(evaluated$new_tiles),
                  rank=paste(rank,length(legal),sep="/"),
                  best=best,
                  words=evaluated$words
              )
          )
      )
      board <- apply_move(board,evaluated$new_tiles)
    }
  }
  for (player in player_order) lines <- c(
      lines,
      words("player",player,counter_text(players[[player]],c("moves","valid","score","loss")))
  )
  lines <- c(
      lines,
      paste("total",counter_text(totals,c("valid","invalid","score","best","loss"))),
      position_summary(board),
      board_display(board)
  )
  bump(a$validation_totals,"moves",length(records))
  for (key in c("valid","invalid","loss")) bump(a$validation_totals,key,counter(totals,key))
  lines
}
ordinary_game <- function(a,job) {
  f <- strsplit(job[1L]," ",fixed=TRUE)[[1L]]
  name <- f[2L]
  seed <- as.integer(f[3L])
  random <- new_minstd(seed)
  bag <- make_bag(a$counts,random)
  board <- matrix(".",BOARD_SIZE,BOARD_SIZE)
  players <- list()
  lines <- words("GAME",name,attributes_text(seed=seed,players=length(job)-1L))
  for (i in seq_len(length(job)-1L)) {
    f <- strsplit(job[i+1L]," ",fixed=TRUE)[[1L]]
    p <- list(
        name=f[2L],
        strategy=f[3L],
        threshold=as.integer(f[4L]),
        rack=draw_tiles(bag,RACK_SIZE),
        score=0L,
        statistics=new_totals()
    )
    players[[i]] <- p
    lines <- c(lines,words("player",i,p$name,attributes_text(strategy=p$strategy,threshold=p$threshold)))
  }
  turn <- consecutive <- outgoing <- 0L
  highlight <- NULL
  repeat {
    index <- turn %% length(players)+1L
    player <- players[[index]]
    turn <- turn+1L
    rack <- player$rack
    statistics <- player$statistics
    legal <- legal_moves(a,board,rack)
    candidate <- if (length(legal)) strategy_sort(legal,player$strategy)[[1L]] else NULL
    prefix <- words("turn",turn,player$name,attributes_text(rack=collection(rack),moves=length(legal)))
    if (!is.null(candidate) && !(candidate$score < player$threshold && length(bag$tiles) >= RACK_SIZE)) {
      best <- legal[[1L]]$score
      board <- apply_move(board,candidate$new_tiles)
      drawn <- draw_tiles(bag,RACK_SIZE-nchar(candidate$leave))
      player$score <- player$score+candidate$score
      player$rack <- paste0(candidate$leave,drawn)
      bump(statistics,"plays")
      bump(statistics,"bingos",as.integer(length(candidate$new_tiles) == RACK_SIZE))
      statistics$top <- max(counter(statistics,"top"),candidate$score)
      bump(statistics,"loss",best-candidate$score)
      consecutive <- 0L
      if (is.null(highlight) || candidate$score > highlight$move$score) highlight <- list(
          turn=turn,
          player=player$name,
          move=candidate
      )
      lines <- c(
          lines,
          words(
              prefix,
              paste0("best=",best),
              "play",
              notation(candidate),
              attributes_text(
                  score=candidate$score,
                  total=player$score,
                  draw=collection(drawn),
                  bag=length(bag$tiles)
              )
          )
      )
      players[[index]] <- player
      if (!nzchar(player$rack) && !length(bag$tiles)) {
        outgoing <- index
        break
      }
    } else if (length(bag$tiles) >= RACK_SIZE) {
      keep <- best_leave(a,rack)
      returned <- remove_tiles(rack,keep)
      drawn <- exchange_tiles(bag,returned,random)
      player$rack <- paste0(keep,drawn)
      bump(statistics,"exchanges")
      consecutive <- consecutive+1L
      lines <- c(
          lines,
          words(
              prefix,
              "exchange",
              attributes_text(keep=collection(keep),draw=collection(drawn),bag=length(bag$tiles))
          )
      )
      players[[index]] <- player
    } else {
      bump(statistics,"passes")
      consecutive <- consecutive+1L
      lines <- c(lines,words(prefix,"pass",attributes_text(bag=length(bag$tiles))))
    }
    if (consecutive == 6L) break
  }
  ending <- if (outgoing == 0L) attributes_text(reason="scoreless",turns=turn) else attributes_text(
      reason="out",
      player=players[[outgoing]]$name,
      turns=turn
  )
  lines <- c(lines,paste("end",ending))
  adjustments <- -vapply(players,function(p) collection_points(p$rack,a$values),integer(1))
  if (outgoing != 0L) adjustments[outgoing] <- sum(vapply(
      players[-outgoing],
      function(p) collection_points(p$rack,a$values),
      integer(1)
  ))
  final_scores <- vapply(players,function(p) p$score,integer(1))+adjustments
  for (i in seq_along(players)) {
    p <- players[[i]]
    adjustment <- adjustments[i]
    adjusted <- if (adjustment > 0L) paste0("+",adjustment) else as.character(adjustment)
    lines <- c(
        lines,
        words(
            "final",
            p$name,
            attributes_text(score=p$score,rack=collection(p$rack),adjust=adjusted,total=final_scores[i])
        )
    )
  }
  standings <- order(-final_scores,seq_along(players))
  for (rank in seq_along(standings)) {
    i <- standings[rank]
    p <- players[[i]]
    lines <- c(
        lines,
        words(
            "standing",
            rank,
            p$name,
            paste0("total=",final_scores[i]),
            counter_text(p$statistics,c("plays","bingos","exchanges","passes","top","loss"))
        )
    )
  }
  winners <- vapply(players[which(final_scores == max(final_scores))],function(p) p$name,character(1))
  lines <- c(lines,paste("winner",paste(winners,collapse=",")))
  if (!is.null(highlight)) lines <- c(
      lines,
      words(
          "highlight",
          attributes_text(turn=highlight$turn,player=highlight$player),
          "play",
          notation(highlight$move),
          paste0("score=",highlight$move$score)
      )
  )
  lines <- c(lines,position_summary(board),board_display(board))
  bump(a$game_totals,"turns",turn)
  for (p in players) for (key in c("plays","exchanges","passes","bingos")) bump(
      a$game_totals,
      key,
      counter(p$statistics,key)
  )
  lines
}
duplicate_game <- function(a,job) {
  f <- strsplit(job[1L]," ",fixed=TRUE)[[1L]]
  name <- f[2L]
  seed <- as.integer(f[3L])
  random <- new_minstd(seed)
  bag <- make_bag(a$counts,random)
  board <- matrix(".",BOARD_SIZE,BOARD_SIZE)
  rack <- draw_tiles(bag,RACK_SIZE)
  players <- lapply(strsplit(job[-1L]," ",fixed=TRUE),function(f) f[-1L])
  totals <- integer(length(players))
  lines <- words("DUPLICATE",name,attributes_text(seed=seed,players=length(players)))
  for (i in seq_along(players)) lines <- c(
      lines,
      words("player",i,players[[i]][1L],paste0("strategy=",players[[i]][2L]))
  )
  round_number <- master_total <- 0L
  reason <- "stuck"
  repeat {
    legal <- legal_moves(a,board,rack)
    if (!length(legal)) break
    round_number <- round_number+1L
    master <- legal[[1L]]
    choices <- lapply(players,function(p) strategy_sort(legal,p[2L])[[1L]])
    totals <- totals+vapply(choices,function(m) m$score,integer(1))
    master_total <- master_total+master$score
    picks <- paste(vapply(choices,function(m) m$score,integer(1)),collapse=",")
    lines <- c(
        lines,
        words(
            "round",
            round_number,
            attributes_text(rack=collection(rack),moves=length(legal)),
            "master",
            notation(master),
            attributes_text(score=master$score,picks=picks)
        )
    )
    board <- apply_move(board,master$new_tiles)
    rack <- paste0(master$leave,draw_tiles(bag,RACK_SIZE-nchar(master$leave)))
    if (!nzchar(rack)) {
      reason <- "out"
      break
    }
  }
  ending <- attributes_text(reason=reason,rounds=round_number)
  if (reason == "stuck") ending <- paste0(ending," rack=",collection(rack))
  lines <- c(lines,paste("end",ending),paste0("master total=",master_total))
  for (i in seq_along(players)) {
    percent <- if (master_total >= 1L) (100L*totals[i]) %/% master_total else 0L
    lines <- c(lines,words("final",players[[i]][1L],attributes_text(total=totals[i],percent=percent)))
  }
  winners <- vapply(players[which(totals == max(totals))],function(p) p[1L],character(1))
  lines <- c(lines,paste("winner",paste(winners,collapse=",")),position_summary(board),board_display(board))
  bump(a$game_totals,"rounds",round_number)
  lines
}
main <- function() {
  invisible(Sys.setlocale("LC_COLLATE","C"))
  input <- read_inputs()
  a <- input$program
  move_blocks <- list(input$dictionary_lines)
  validation_blocks <- game_blocks <- list()
  seen <- character()
  for (job in input$jobs) {
    f <- strsplit(job[1L]," ",fixed=TRUE)[[1L]]
    kind <- f[1L]
    name <- f[2L]
    totals <- if (kind == "TOPN") a$topn_totals else if (kind == "VALIDATE") a$validation_totals else a$game_totals
    key <- if (kind %in% c("TOPN","VALIDATE")) "jobs" else if (kind == "GAME") "games" else "duplicates"
    bump(totals,key)
    error <- job_error(a,job,seen)
    seen <- union(seen,name)
    if (!is.null(error)) {
      block <- c(paste(kind,name),paste("error",error))
      bump(totals,"errors")
    } else block <- switch(
        kind,
        TOPN=topn(a,job),
        VALIDATE=validate_job(a,job),
        GAME=ordinary_game(a,job),
        DUPLICATE=duplicate_game(a,job)
    )
    if (kind == "TOPN") {
      move_blocks[[length(move_blocks)+1L]] <- block
    } else if (kind == "VALIDATE") {
      validation_blocks[[length(validation_blocks)+1L]] <- block
    } else {
      game_blocks[[length(game_blocks)+1L]] <- block
    }
  }
  move_blocks[[length(move_blocks)+1L]] <- paste(
      "SUMMARY",
      counter_text(a$topn_totals,c("jobs","errors","moves","bingos"))
  )
  validation_blocks[[length(validation_blocks)+1L]] <- paste(
      "SUMMARY",
      counter_text(a$validation_totals,c("jobs","errors","moves","valid","invalid","loss"))
  )
  game_blocks[[length(game_blocks)+1L]] <- paste(
      "SUMMARY",
      counter_text(
          a$game_totals,
          c("games","duplicates","errors","turns","rounds","plays","exchanges","passes","bingos")
      )
  )
  dir.create("output",showWarnings=FALSE)
  outputs <- list("moves.txt"=move_blocks,"validation.txt"=validation_blocks,"game.txt"=game_blocks)
  for (filename in names(outputs)) {
    text <- paste(
        vapply(outputs[[filename]],function(block) paste(block,collapse="\n"),character(1)),
        collapse="\n\n"
    )
    connection <- file(paste0("output/",filename),"wb")
    writeChar(paste0(text,"\n"),connection,eos=NULL,useBytes=TRUE)
    close(connection)
  }
}
main()
