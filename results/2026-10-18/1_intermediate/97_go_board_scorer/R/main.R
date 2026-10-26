columns <- strsplit('ABCDEFGHJKLMNOPQRST', '', fixed = TRUE)[[1]]
handicap_points <- list(
  '9' = strsplit('C3 G7 C7 G3 C5 G5 E3 E7 E5', ' ')[[1]],
  '13' = strsplit('D4 K10 D10 K4 D7 K7 G4 G10 G7', ' ')[[1]],
  '19' = strsplit('D4 Q16 D16 Q4 D10 Q10 K4 K16 K10', ' ')[[1]]
)
arity <- c(
  BOARD = 2,
  KOMI = 1,
  SUPERKO = 1,
  HANDICAP = 1,
  PLAY = 2,
  PASS = 1,
  REPLAY = 1,
  UNDO = 0,
  SHOW = 0,
  MAP = 0,
  STATUS = 0,
  CAPTURES = 0,
  HISTORY = 0,
  MOVES = 0,
  GROUP = 1,
  GROUPS = 0,
  ATARI = 0,
  LEGAL = 1,
  EYES = 1,
  SAFE = 1,
  LADDER = 1,
  DEAD = 1,
  REGIONS = 0,
  SCORE = 1
)
other <- function(c) if (c == 'B') 'W' else 'B'
half <- function(x) {
  paste0(if (x < 0) '-' else '', abs(x) %/% 2, if (abs(x) %% 2) '.5' else '.0')
}
emit <- function(...) {
  cat(
    paste(unlist(list(...), use.names = FALSE), collapse = ' '),
    '\n',
    sep = ''
  )
}
parse_komi <- function(s) {
  if (!grepl('^-?(0|[1-9][0-9]*)(\\.[05])?$', s)) {
    return(NA_real_)
  }
  parts <- strsplit(sub('^-', '', s), '.', fixed = TRUE)[[1]]
  whole <- as.numeric(parts[1])
  if (whole > 100) {
    return(NA_real_)
  }
  value <- 2 * whole + if (length(parts) == 2 && parts[2] == '5') 1 else 0
  if (startsWith(s, '-')) {
    if (value == 0) {
      return(NA_real_)
    }
    -value
  } else {
    value
  }
}
adjacent <- function(p, n, diagonal = FALSE) {
  r <- (p - 1) %/% n
  c <- (p - 1) %% n
  steps <- if (diagonal) {
    matrix(c(-1, -1, -1, 1, 1, -1, 1, 1), ncol = 2, byrow = TRUE)
  } else {
    matrix(c(-1, 0, 1, 0, 0, -1, 0, 1), ncol = 2, byrow = TRUE)
  }
  rr <- r + steps[, 1]
  cc <- c + steps[, 2]
  ok <- rr >= 0 & rr < n & cc >= 0 & cc < n
  rr[ok] * n + cc[ok] + 1L
}
flood <- function(b, n, p, allowed) {
  seen <- rep(FALSE, length(b))
  seen[p] <- TRUE
  todo <- p
  while (length(todo)) {
    q <- todo[length(todo)]
    todo <- todo[-length(todo)]
    for (t in adjacent(q, n)) {
      if (!seen[t] && b[t] %in% allowed) {
        seen[t] <- TRUE
        todo <- c(todo, t)
      }
    }
  }
  which(seen)
}
group <- function(b, n, p) {
  stones <- flood(b, n, p, b[p])
  liberties <- sort(unique(unlist(
    lapply(stones, function(q) {
      ns <- adjacent(q, n)
      ns[b[ns] == '.']
    }),
    use.names = FALSE
  )))
  list(
    color = b[p],
    first = min(stones),
    stones = stones,
    liberties = liberties
  )
}
groups <- function(b, n, color = NULL) {
  out <- list()
  seen <- rep(FALSE, length(b))
  for (p in seq_along(b)) {
    if (b[p] != '.' && !seen[p] && (is.null(color) || b[p] == color)) {
      g <- group(b, n, p)
      seen[g$stones] <- TRUE
      out[[length(out) + 1]] <- g
    }
  }
  out
}
placement <- function(b, n, c, p) {
  if (b[p] != '.') {
    return(list(board = b, captured = 0, reason = 'occupied'))
  }
  next_board <- b
  next_board[p] <- c
  captured <- 0
  seen <- rep(FALSE, length(b))
  for (q in adjacent(p, n)) {
    if (next_board[q] == other(c) && !seen[q]) {
      g <- group(next_board, n, q)
      seen[g$stones] <- TRUE
      if (!length(g$liberties)) {
        next_board[g$stones] <- '.'
        captured <- captured + length(g$stones)
      }
    }
  }
  list(
    board = next_board,
    captured = captured,
    reason = if (!length(group(next_board, n, p)$liberties)) 'suicide' else ''
  )
}
regions <- function(b, n) {
  out <- list()
  seen <- rep(FALSE, length(b))
  for (p in seq_along(b)) {
    if (b[p] == '.' && !seen[p]) {
      points <- flood(b, n, p, '.')
      seen[points] <- TRUE
      border <- unique(unlist(
        lapply(points, function(q) b[adjacent(q, n)]),
        use.names = FALSE
      ))
      border <- setdiff(border, '.')
      out[[length(out) + 1]] <- list(
        first = p,
        points = points,
        owner = if (length(border) == 1) border else 'neutral'
      )
    }
  }
  out
}
safe_groups <- function(b, n, c) {
  own <- groups(b, n, c)
  areas <- list()
  seen <- rep(FALSE, length(b))
  for (p in seq_along(b)) {
    if (b[p] != c && !seen[p]) {
      area <- flood(b, n, p, c('.', other(c)))
      seen[area] <- TRUE
      empty <- area[b[area] == '.']
      touch <- vital <- integer()
      for (i in seq_along(own)) {
        if (
          any(vapply(
            area,
            function(q) any(adjacent(q, n) %in% own[[i]]$stones),
            logical(1)
          ))
        ) {
          touch <- c(touch, i)
        }
        if (all(empty %in% own[[i]]$liberties)) vital <- c(vital, i)
      }
      areas[[length(areas) + 1]] <- list(touch = touch, vital = vital)
    }
  }
  s <- seq_along(own)
  t <- seq_along(areas)
  repeat {
    before <- length(s) + length(t)
    s <- s[vapply(
      s,
      function(i) {
        sum(vapply(t, function(j) i %in% areas[[j]]$vital, logical(1))) >= 2
      },
      logical(1)
    )]
    t <- t[vapply(t, function(j) all(areas[[j]]$touch %in% s), logical(1))]
    if (before == length(s) + length(t)) break
  }
  own[s]
}
ladder <- function(b, n, p) {
  defender <- b[p]
  attacker <- other(defender)
  memo <- new.env(parent = emptyenv())
  read_position <- function(current, depth, defending) {
    if (depth >= 40) {
      return(list(success = defending, move = 0L))
    }
    key <- paste0(paste(current, collapse = ''), ':', depth, ':', defending)
    if (exists(key, envir = memo, inherits = FALSE)) {
      return(memo[[key]])
    }
    g <- group(current, n, p)
    candidates <- g$liberties
    seen <- rep(FALSE, length(current))
    if (defending) {
      for (q in g$stones) {
        for (t in adjacent(q, n)) {
          if (current[t] == attacker && !seen[t]) {
            e <- group(current, n, t)
            seen[e$stones] <- TRUE
            if (length(e$liberties) == 1) {
              candidates <- union(candidates, e$liberties)
            }
          }
        }
      }
    }
    for (q in sort(candidates)) {
      next_board <- placement(
        current,
        n,
        if (defending) defender else attacker,
        q
      )
      if (next_board$reason != '') {
        next
      }
      if (defending) {
        count <- length(group(next_board$board, n, p)$liberties)
        success <- count >= 3 ||
          (count == 2 &&
            !read_position(next_board$board, depth + 1, FALSE)$success)
      } else {
        success <- !read_position(next_board$board, depth + 1, TRUE)$success
      }
      if (success) {
        memo[[key]] <- list(success = TRUE, move = q)
        return(memo[[key]])
      }
    }
    memo[[key]] <- list(success = FALSE, move = 0L)
    memo[[key]]
  }
  count <- length(group(b, n, p)$liberties)
  if (count >= 3) {
    return(list(status = 'safe', move = 0L))
  }
  result <- read_position(b, 0, count == 1)
  list(
    status = if (if (count == 1) result$success else !result$success) {
      'escapes'
    } else {
      'captured'
    },
    move = result$move
  )
}
reset <- function(g, n, k) {
  g$n <- n
  g$komi <- k
  g$board <- rep('.', n * n)
  g$turn <- 'B'
  g$captures <- c(B = 0, W = 0)
  g$passes <- 0
  g$over <- FALSE
  g$handicap <- integer()
  g$history <- list()
  g$positions <- list(g$board)
  g$dead <- integer()
}
point <- function(g, s) {
  if (!grepl('^[A-HJ-T]([1-9]|1[0-9])$', s)) {
    return(0L)
  }
  c <- match(substr(s, 1, 1), columns)
  r <- as.integer(substring(s, 2))
  if (c <= g$n && r <= g$n) (r - 1) * g$n + c else 0L
}
point_name <- function(g, p) {
  paste0(columns[(p - 1) %% g$n + 1], (p - 1) %/% g$n + 1)
}
sgf <- function(g, p) {
  paste0(
    intToUtf8(97 + (p - 1) %% g$n),
    intToUtf8(97 + g$n - 1 - (p - 1) %/% g$n)
  )
}
check <- function(g, c, p) {
  result <- placement(g$board, g$n, c, p)
  if (
    result$reason == '' &&
      length(g$positions) >= 2 &&
      identical(result$board, g$positions[[length(g$positions) - 1]])
  ) {
    result$reason <- 'ko'
  }
  if (
    result$reason == '' &&
      g$superko &&
      any(vapply(
        g$positions,
        function(old) identical(old, result$board),
        logical(1)
      ))
  ) {
    result$reason <- 'superko'
  }
  result
}
play <- function(g, c, p, checked = NULL) {
  before <- list(
    board = g$board,
    turn = g$turn,
    captures = g$captures,
    passes = g$passes,
    over = g$over
  )
  captured <- 0
  if (p == 0) {
    g$passes <- g$passes + 1
    if (g$passes == 2) g$over <- TRUE
  } else {
    r <- if (is.null(checked)) check(g, c, p) else checked
    g$board <- r$board
    captured <- r$captured
    g$captures[c] <- g$captures[c] + captured
    g$passes <- 0
  }
  g$turn <- other(c)
  g$history[[length(g$history) + 1]] <- list(
    color = c,
    point = p,
    captured = captured,
    before = before
  )
  g$positions[[length(g$positions) + 1]] <- g$board
  g$dead <- integer()
  captured
}
clean <- function(g) {
  b <- g$board
  b[g$dead] <- '.'
  b
}
show_board <- function(g, map = FALSE) {
  b <- if (map) clean(g) else g$board
  chars <- b
  points <- handicap_points[[as.character(g$n)]]
  indices <- if (g$n == 19) seq_len(9) else c(1, 2, 3, 4, 9)
  stars <- vapply(points[indices], function(s) point(g, s), numeric(1))
  if (map) {
    for (r in regions(b, g$n)) {
      chars[r$points] <- if (r$owner == 'B') {
        'x'
      } else if (r$owner == 'W') {
        'o'
      } else {
        '.'
      }
    }
  }
  for (p in seq_along(b)) {
    if (b[p] != '.') {
      c <- if (b[p] == 'B') 'X' else 'O'
      chars[p] <- if (!map && p %in% g$dead) tolower(c) else c
    } else if (!map) {
      chars[p] <- if (p %in% stars) '+' else '.'
    }
  }
  header <- paste0('   ', paste(columns[seq_len(g$n)], collapse = ' '))
  emit(header)
  for (r in seq(g$n, 1)) {
    emit(
      sprintf('%2d', r),
      paste(chars[((r - 1) * g$n + 1):(r * g$n)], collapse = ' '),
      r
    )
  }
  emit(header)
}
score <- function(g, method) {
  b <- clean(g)
  territory <- c(B = 0, W = 0)
  total <- c(B = 0, W = 0)
  for (r in regions(b, g$n)) {
    if (r$owner != 'neutral') {
      territory[r$owner] <- territory[r$owner] + length(r$points)
    }
  }
  for (c in c('B', 'W')) {
    if (method == 'AREA') {
      stones <- sum(b == c)
      total[c] <- 2 * (stones + territory[c]) + if (c == 'W') g$komi else 0
      fields <- c(c, 'stones', stones, 'territory', territory[c])
    } else {
      prisoners <- g$captures[c] + sum(g$board[g$dead] == other(c))
      total[c] <- 2 * (territory[c] + prisoners) + if (c == 'W') g$komi else 0
      fields <- c(c, 'territory', territory[c], 'prisoners', prisoners)
    }
    if (c == 'W') {
      fields <- c(fields, 'komi', half(g$komi))
    }
    emit(c(fields, 'total', half(total[c])))
  }
  d <- total['B'] - total['W']
  emit(
    'result',
    if (d > 0) {
      paste0('B+', half(d))
    } else if (d < 0) {
      paste0('W+', half(-d))
    } else {
      'Draw'
    }
  )
}
execute <- function(g, line) {
  words <- strsplit(line, ' ', fixed = TRUE)[[1]]
  c <- words[1]
  a <- words[-1]
  if (!c %in% names(arity)) {
    emit('ERROR unknown command')
    return()
  }
  if (length(a) != arity[[c]]) {
    emit('ERROR bad arguments')
    return()
  }
  valid <- switch(
    c,
    BOARD = a[1] %in% c('9', '13', '19') && !is.na(parse_komi(a[2])),
    KOMI = !is.na(parse_komi(a[1])),
    SUPERKO = a[1] %in% c('ON', 'OFF'),
    HANDICAP = grepl('^[2-9]$', a[1]),
    PLAY = ,
    PASS = ,
    LEGAL = ,
    EYES = ,
    SAFE = a[1] %in% c('B', 'W'),
    SCORE = a[1] %in% c('AREA', 'TERRITORY'),
    TRUE
  )
  if (!valid) {
    emit('ERROR bad arguments')
    return()
  }
  p <- 0L
  if (c %in% c('PLAY', 'GROUP', 'LADDER', 'DEAD')) {
    p <- point(g, a[if (c == 'PLAY') 2 else 1])
    if (p == 0) {
      emit('ERROR bad point')
      return()
    }
  }
  records <- list()
  if (c == 'REPLAY') {
    if (!grepl('^(;[BW]\\[[a-z]{0,2}\\])+$', a[1])) {
      emit('ERROR bad sequence')
      return()
    }
    matches <- regmatches(a[1], gregexpr(';[BW]\\[[a-z]*\\]', a[1]))[[1]]
    for (record in matches) {
      text <- substr(record, 4, nchar(record) - 1)
      if (
        nchar(text) > 0 &&
          (nchar(text) != 2 || any(utf8ToInt(text) - 97 >= g$n))
      ) {
        emit('ERROR bad sequence')
        return()
      }
      q <- if (text == '') {
        0
      } else {
        codes <- utf8ToInt(text)
        (g$n - 1 - (codes[2] - 97)) * g$n + codes[1] - 96
      }
      records[[length(records) + 1]] <- list(
        color = substr(record, 2, 2),
        point = q
      )
    }
  }
  if (c %in% c('PLAY', 'PASS', 'REPLAY') && g$over) {
    emit('ERROR game over')
    return()
  }
  if (c == 'BOARD') {
    reset(g, as.integer(a[1]), parse_komi(a[2]))
    emit('board', g$n, 'komi', half(g$komi))
  } else if (c == 'KOMI') {
    g$komi <- parse_komi(a[1])
    emit('komi', half(g$komi))
  } else if (c == 'SUPERKO') {
    g$superko <- a[1] == 'ON'
    emit('superko', if (g$superko) 'on' else 'off')
  } else if (c == 'HANDICAP') {
    if (length(g$history) || any(g$board != '.')) {
      emit('ERROR handicap not allowed')
      return()
    }
    k <- as.integer(a[1])
    indices <- if (k == 5) {
      c(1, 2, 3, 4, 9)
    } else if (k == 7) {
      c(1, 2, 3, 4, 5, 6, 9)
    } else {
      seq_len(k)
    }
    g$handicap <- vapply(
      handicap_points[[as.character(g$n)]][indices],
      function(s) point(g, s),
      numeric(1)
    )
    g$board[g$handicap] <- 'B'
    g$turn <- 'W'
    g$positions <- list(g$board)
    g$dead <- integer()
    emit('handicap', k, point_name(g, g$handicap))
  } else if (c == 'PLAY') {
    next_board <- check(g, a[1], p)
    reason <- if (a[1] != g$turn) 'turn' else next_board$reason
    if (reason != '') {
      emit('ILLEGAL', a[1], a[2], reason)
    } else {
      captured <- play(g, a[1], p, next_board)
      emit(
        a[1],
        a[2],
        if (captured > 0) c('captures', captured) else character()
      )
    }
  } else if (c == 'PASS') {
    if (a[1] != g$turn) {
      emit('ILLEGAL', a[1], 'pass turn')
    } else {
      play(g, a[1], 0)
      emit(a[1], 'pass')
      if (g$over) emit('game over')
    }
  } else if (c == 'REPLAY') {
    played <- 0
    stopped <- character()
    for (record in records) {
      col <- record$color
      q <- record$point
      checked <- if (q == 0) NULL else check(g, col, q)
      reason <- if (g$over) {
        'game over'
      } else if (col != g$turn) {
        'turn'
      } else if (is.null(checked)) {
        ''
      } else {
        checked$reason
      }
      if (reason != '') {
        stopped <- c(
          'stopped',
          col,
          if (q == 0) 'pass' else point_name(g, q),
          reason
        )
        break
      }
      play(g, col, q, checked)
      played <- played + 1
    }
    emit('replay', played, 'moves', stopped)
    if (g$over) emit('game over')
  } else if (c == 'UNDO') {
    if (!length(g$history)) {
      emit('ERROR nothing to undo')
      return()
    }
    m <- g$history[[length(g$history)]]
    g$history <- g$history[-length(g$history)]
    for (key in names(m$before)) {
      g[[key]] <- m$before[[key]]
    }
    g$positions <- g$positions[-length(g$positions)]
    g$dead <- integer()
    emit('undo', m$color, if (m$point == 0) 'pass' else point_name(g, m$point))
  } else if (c %in% c('SHOW', 'MAP')) {
    show_board(g, c == 'MAP')
  } else if (c == 'STATUS') {
    emit(
      'size',
      g$n,
      'komi',
      half(g$komi),
      'handicap',
      length(g$handicap),
      'superko',
      if (g$superko) 'on' else 'off'
    )
    emit(
      'moves',
      length(g$history),
      if (g$over) 'game over' else c('next', g$turn, 'passes', g$passes)
    )
  } else if (c == 'CAPTURES') {
    emit('captures B', g$captures['B'], 'W', g$captures['W'])
  } else if (c == 'HISTORY') {
    emit('history', length(g$history))
    for (i in seq_along(g$history)) {
      m <- g$history[[i]]
      emit(
        i,
        m$color,
        if (m$point == 0) 'pass' else point_name(g, m$point),
        if (m$captured > 0) c('captures', m$captured) else character()
      )
    }
  } else if (c == 'MOVES') {
    s <- paste0('(;GM[1]FF[4]SZ[', g$n, ']KM[', half(g$komi), ']')
    if (length(g$handicap)) {
      s <- paste0(s, 'HA[', length(g$handicap), ']AB')
      for (q in g$handicap) {
        s <- paste0(s, '[', sgf(g, q), ']')
      }
    }
    for (m in g$history) {
      s <- paste0(
        s,
        ';',
        m$color,
        '[',
        if (m$point == 0) '' else sgf(g, m$point),
        ']'
      )
    }
    emit(paste0(s, ')'))
  } else if (c %in% c('GROUP', 'DEAD', 'LADDER')) {
    if (g$board[p] == '.') {
      emit('ERROR no stone')
      return()
    }
    gr <- group(g$board, g$n, p)
    if (c == 'GROUP') {
      emit(
        'group',
        gr$color,
        point_name(g, gr$first),
        'size',
        length(gr$stones),
        'liberties',
        length(gr$liberties)
      )
      emit('stones', point_name(g, gr$stones))
      emit('liberties', point_name(g, gr$liberties))
    } else if (c == 'DEAD') {
      alive <- p %in% g$dead
      g$dead <- if (alive) {
        setdiff(g$dead, gr$stones)
      } else {
        union(g$dead, gr$stones)
      }
      emit(
        if (alive) 'alive' else 'dead',
        gr$color,
        point_name(g, gr$first),
        'size',
        length(gr$stones)
      )
    } else {
      result <- ladder(g$board, g$n, p)
      emit(
        'ladder',
        a[1],
        result$status,
        if (result$move == 0) character() else point_name(g, result$move)
      )
    }
  } else if (c == 'GROUPS') {
    gs <- groups(g$board, g$n)
    emit('groups', length(gs))
    for (gr in gs) {
      emit(
        gr$color,
        point_name(g, gr$first),
        'size',
        length(gr$stones),
        'liberties',
        length(gr$liberties),
        if (gr$first %in% g$dead) 'dead' else character()
      )
    }
  } else if (c == 'ATARI') {
    gs <- Filter(function(gr) length(gr$liberties) == 1, groups(g$board, g$n))
    if (!length(gs)) {
      emit('atari none')
    }
    for (gr in gs) {
      emit(
        'atari',
        gr$color,
        point_name(g, gr$first),
        'size',
        length(gr$stones),
        'at',
        point_name(g, gr$liberties)
      )
    }
  } else if (c == 'LEGAL') {
    rejected <- list()
    count <- 0
    for (q in seq_along(g$board)) {
      if (g$board[q] == '.') {
        why <- check(g, a[1], q)$reason
        if (why == '') {
          count <- count + 1
        } else {
          rejected[[length(rejected) + 1]] <- c(point_name(g, q), why)
        }
      }
    }
    emit('legal', a[1], count)
    for (row in rejected) {
      emit(row)
    }
  } else if (c == 'EYES') {
    found <- list()
    for (q in seq_along(g$board)) {
      if (g$board[q] == '.') {
        ns <- adjacent(q, g$n)
        if (all(g$board[ns] == a[1])) {
          enemies <- sum(g$board[adjacent(q, g$n, TRUE)] == other(a[1]))
          found[[length(found) + 1]] <- c(
            point_name(g, q),
            if (enemies <= if (length(ns) == 4) 1 else 0) 'real' else 'false'
          )
        }
      }
    }
    emit('eyes', a[1], length(found))
    for (row in found) {
      emit(row)
    }
  } else if (c == 'SAFE') {
    gs <- safe_groups(g$board, g$n, a[1])
    emit('safe', a[1], length(gs))
    for (gr in gs) {
      emit(point_name(g, gr$first), 'size', length(gr$stones))
    }
  } else if (c == 'REGIONS') {
    rs <- regions(clean(g), g$n)
    emit('regions', length(rs))
    for (r in rs) {
      emit(point_name(g, r$first), 'size', length(r$points), r$owner)
    }
  } else if (c == 'SCORE') {
    score(g, a[1])
  }
}
input <- file('stdin', 'r')
count <- as.integer(readLines(input, n = 1))
game <- new.env(parent = emptyenv())
game$superko <- FALSE
reset(game, 19L, 13)
for (i in seq_len(count)) {
  execute(game, readLines(input, n = 1))
}
