marker <- function(tag) {
  x <- new.env(parent = emptyenv())
  x$tag <- tag
  x
}
NIL <- marker('nil')
VOID <- marker('void')
UNINIT <- marker('uninitialized')
is_kind <- function(v, k) is.environment(v) && identical(v$tag, k)
symbols <- new.env(parent = emptyenv())
sym <- function(name) {
  if (!exists(name, symbols, inherits = FALSE)) {
    x <- marker('symbol')
    x$name <- name
    assign(name, x, symbols)
  }
  get(name, symbols, inherits = FALSE)
}
pair <- function(a, b) {
  x <- marker('pair')
  x$car <- a
  x$cdr <- b
  x
}
make_list <- function(a, tail = NIL) {
  for (i in rev(seq_along(a))) {
    tail <- pair(a[[i]], tail)
  }
  tail
}
items <- function(v) {
  a <- list()
  while (is_kind(v, 'pair')) {
    a[[length(a) + 1L]] <- v$car
    v <- v$cdr
  }
  if (identical(v, NIL)) a else NULL
}
repr <- function(v, quoted = TRUE) {
  if (identical(v, NIL)) {
    return('()')
  }
  if (identical(v, VOID)) {
    return('#<void>')
  }
  if (is.logical(v)) {
    return(if (v) '#t' else '#f')
  }
  if (is.numeric(v)) {
    return(sprintf('%.0f', v))
  }
  if (is.character(v)) {
    if (!quoted) {
      return(v)
    }
    chars <- strsplit(v, '', fixed = TRUE)[[1]]
    s <- vapply(
      chars,
      function(c) {
        if (c == '\\') {
          '\\\\'
        } else if (c == '"') {
          '\\"'
        } else if (c == '\n') {
          '\\n'
        } else {
          c
        }
      },
      ''
    )
    return(paste0('"', paste0(s, collapse = ''), '"'))
  }
  if (is_kind(v, 'symbol')) {
    return(v$name)
  }
  if (is_kind(v, 'procedure')) {
    return(
      if (is.null(v$name)) {
        '#<procedure>'
      } else {
        paste0('#<procedure ', v$name, '>')
      }
    )
  }
  a <- character()
  while (is_kind(v, 'pair')) {
    a <- c(a, repr(v$car, quoted))
    v <- v$cdr
  }
  if (!identical(v, NIL)) {
    a <- c(a, '.', repr(v, quoted))
  }
  paste0('(', paste(a, collapse = ' '), ')')
}
fail <- function(s) stop(s, call. = FALSE)
same <- function(a, b, deep = FALSE) {
  if (deep && is_kind(a, 'pair') && is_kind(b, 'pair')) {
    return(same(a$car, b$car, TRUE) && same(a$cdr, b$cdr, TRUE))
  }
  identical(a, b)
}
scope <- function(parent = NULL) {
  e <- new.env(parent = emptyenv())
  e$frame <- new.env(parent = emptyenv())
  e$parent <- parent
  e
}
find <- function(e, name) {
  while (!is.null(e)) {
    if (exists(name, e$frame, inherits = FALSE)) {
      return(e)
    }
    e <- e$parent
  }
  fail(paste0('unbound variable: ', name))
}
lookup <- function(e, name) {
  v <- get(name, find(e, name)$frame, inherits = FALSE)
  if (identical(v, UNINIT)) {
    fail(paste0('uninitialized variable: ', name))
  }
  v
}
parameters <- function(v) {
  names <- character()
  while (is_kind(v, 'pair')) {
    if (!is_kind(v$car, 'symbol')) {
      return(NULL)
    }
    names <- c(names, v$car$name)
    v <- v$cdr
  }
  rest <- if (is_kind(v, 'symbol')) v$name else NULL
  if (!identical(v, NIL) && is.null(rest)) {
    return(NULL)
  }
  all <- c(names, rest)
  if (anyDuplicated(all)) {
    return(NULL)
  }
  list(names = names, rest = rest)
}
compound <- function(p, b, e, name = NULL) {
  f <- marker('procedure')
  f$name <- name
  f$minimum <- length(p$names)
  f$rest <- p$rest
  f$variadic <- !is.null(p$rest)
  f$params <- p$names
  f$body <- b
  f$env <- e
  f$fn <- NULL
  f
}
bindings <- function(v, unique) {
  a <- items(v)
  if (is.null(a)) {
    return(NULL)
  }
  bs <- list()
  names <- character()
  for (x in a) {
    b <- items(x)
    if (is.null(b) || length(b) != 2L || !is_kind(b[[1]], 'symbol')) {
      return(NULL)
    }
    names <- c(names, b[[1]]$name)
    bs[[length(bs) + 1L]] <- list(b[[1]]$name, b[[2]])
  }
  if (unique && anyDuplicated(names)) {
    return(NULL)
  }
  bs
}
shape <- function(ok, x) if (!ok) fail(paste0('bad syntax: ', repr(x)))
body <- function(a, e) {
  v <- VOID
  for (x in a) {
    v <- evaluate(x, e)
  }
  v
}
call_proc <- function(f, a) {
  if (length(a) < f$minimum || (!f$variadic && length(a) != f$minimum)) {
    fail(paste0(
      if (is.null(f$name)) 'lambda' else f$name,
      ': wrong number of arguments (expected ',
      if (f$variadic) 'at least ' else '',
      f$minimum,
      ', got ',
      length(a),
      ')'
    ))
  }
  if (!is.null(f$fn)) {
    return(f$fn(a))
  }
  e <- scope(f$env)
  for (i in seq_along(f$params)) {
    assign(f$params[i], a[[i]], e$frame)
  }
  if (!is.null(f$rest)) {
    assign(f$rest, make_list(tail(a, length(a) - f$minimum)), e$frame)
  }
  body(f$body, e)
}
evaluate <- function(x, e) {
  if (is_kind(x, 'symbol')) {
    return(lookup(e, x$name))
  }
  if (!is_kind(x, 'pair')) {
    shape(!identical(x, NIL), x)
    return(x)
  }
  a <- items(x)
  shape(!is.null(a), x)
  n <- length(a)
  h <- if (is_kind(a[[1]], 'symbol')) a[[1]]$name else ''
  if (h == 'quote') {
    shape(n == 2L, x)
    return(a[[2]])
  }
  if (h == 'if') {
    shape(n %in% c(3L, 4L), x)
    return(
      if (!identical(evaluate(a[[2]], e), FALSE)) {
        evaluate(a[[3]], e)
      } else if (n == 4L) {
        evaluate(a[[4]], e)
      } else {
        VOID
      }
    )
  }
  if (h == 'begin') {
    return(body(a[-1L], e))
  }
  if (h == 'lambda') {
    p <- if (n >= 3L) parameters(a[[2]]) else NULL
    shape(!is.null(p), x)
    return(compound(p, a[-c(1L, 2L)], e))
  }
  if (h == 'define') {
    if (n > 1L && is_kind(a[[2]], 'symbol')) {
      shape(n == 3L, x)
      v <- evaluate(a[[3]], e)
      if (is_kind(v, 'procedure') && is.null(v$fn) && is.null(v$name)) {
        v$name <- a[[2]]$name
      }
      assign(a[[2]]$name, v, e$frame)
    } else {
      t <- if (n > 1L) a[[2]] else NIL
      p <- if (n >= 3L && is_kind(t, 'pair') && is_kind(t$car, 'symbol')) {
        parameters(t$cdr)
      } else {
        NULL
      }
      shape(!is.null(p), x)
      assign(t$car$name, compound(p, a[-c(1L, 2L)], e, t$car$name), e$frame)
    }
    return(VOID)
  }
  if (h == 'set!') {
    shape(n == 3L && is_kind(a[[2]], 'symbol'), x)
    v <- evaluate(a[[3]], e)
    assign(a[[2]]$name, v, find(e, a[[2]]$name)$frame)
    return(VOID)
  }
  if (h %in% c('let', 'let*', 'letrec')) {
    named <- h == 'let' && n > 1L && is_kind(a[[2]], 'symbol')
    at <- if (named) 3L else 2L
    bs <- if (n >= at + 1L) bindings(a[[at]], h != 'let*') else NULL
    shape(!is.null(bs), x)
    s <- scope(e)
    if (h == 'let*') {
      if (length(bs)) {
        s <- e
      }
      for (b in bs) {
        v <- evaluate(b[[2]], s)
        s <- scope(s)
        assign(b[[1]], v, s$frame)
      }
    } else if (h == 'letrec') {
      for (b in bs) {
        assign(b[[1]], UNINIT, s$frame)
      }
      for (b in bs) {
        assign(b[[1]], evaluate(b[[2]], s), s$frame)
      }
    } else {
      vs <- lapply(bs, function(b) evaluate(b[[2]], e))
      if (named) {
        f <- compound(
          list(names = vapply(bs, `[[`, '', 1L), rest = NULL),
          a[-seq_len(3L)],
          s,
          a[[2]]$name
        )
        assign(a[[2]]$name, f, s$frame)
        return(call_proc(f, vs))
      }
      for (i in seq_along(bs)) {
        assign(bs[[i]][[1]], vs[[i]], s$frame)
      }
    }
    return(body(a[-seq_len(at)], s))
  }
  if (h == 'cond') {
    cs <- lapply(a[-1L], items)
    for (i in seq_along(cs)) {
      c <- cs[[i]]
      shape(!is.null(c) && length(c) > 0L, x)
      if (identical(c[[1]], sym('else'))) {
        shape(length(c) >= 2L && i == length(cs), x)
      }
    }
    for (c in cs) {
      if (identical(c[[1]], sym('else'))) {
        return(body(c[-1L], e))
      }
      v <- evaluate(c[[1]], e)
      if (!identical(v, FALSE)) {
        return(if (length(c) == 1L) v else body(c[-1L], e))
      }
    }
    return(VOID)
  }
  if (h == 'and') {
    v <- TRUE
    for (z in a[-1L]) {
      v <- evaluate(z, e)
      if (identical(v, FALSE)) break
    }
    return(v)
  }
  if (h == 'or') {
    for (z in a[-1L]) {
      v <- evaluate(z, e)
      if (!identical(v, FALSE)) return(v)
    }
    return(FALSE)
  }
  if (h %in% c('when', 'unless')) {
    shape(n >= 3L, x)
    return(
      if ((!identical(evaluate(a[[2]], e), FALSE)) == (h == 'when')) {
        body(a[-c(1L, 2L)], e)
      } else {
        VOID
      }
    )
  }
  f <- evaluate(a[[1]], e)
  args <- lapply(a[-1L], function(z) evaluate(z, e))
  if (!is_kind(f, 'procedure')) {
    fail(paste0('not a procedure: ', repr(f)))
  }
  call_proc(f, args)
}
mid <- FALSE
write_text <- function(s) {
  cat(s, sep = '')
  if (nchar(s) > 0L) mid <<- !endsWith(s, '\n')
}
write_line <- function(s) {
  if (mid) {
    write_text('\n')
  }
  write_text(paste0(s, '\n'))
}
expect <- function(n, v, k) {
  ok <- switch(
    k,
    integer = is.numeric(v),
    string = is.character(v),
    pair = is_kind(v, 'pair'),
    procedure = is_kind(v, 'procedure'),
    list = !is.null(items(v))
  )
  if (!ok) {
    fail(paste0(n, ': expected ', k, ', got ', repr(v)))
  }
  v
}
global_env <- function() {
  e <- scope()
  add <- function(n, m, r, fn) {
    f <- marker('procedure')
    f$name <- n
    f$minimum <- m
    f$variadic <- r
    f$fn <- fn
    assign(n, f, e$frame)
  }
  for (name in c(
    '+',
    '*',
    '-',
    'quotient',
    'remainder',
    'modulo',
    'abs',
    'min',
    'max',
    'gcd',
    '=',
    '<',
    '>',
    '<=',
    '>='
  )) {
    local({
      n <- name
      fixed <- if (n %in% c('quotient', 'remainder', 'modulo')) {
        2L
      } else if (n == 'abs') {
        1L
      } else {
        -1L
      }
      add(
        n,
        if (fixed >= 0L) {
          fixed
        } else if (n %in% c('+', '*', 'gcd')) {
          0L
        } else {
          1L
        },
        fixed < 0L,
        function(a) {
          z <- vapply(a, function(v) expect(n, v, 'integer'), 0)
          if (n == '+') {
            return(sum(z))
          }
          if (n == '*') {
            return(prod(z))
          }
          if (n == '-') {
            return(if (length(z) == 1L) -z[1] else z[1] - sum(z[-1L]))
          }
          if (n == 'abs') {
            return(abs(z[1]))
          }
          if (n == 'min') {
            return(min(z))
          }
          if (n == 'max') {
            return(max(z))
          }
          if (n == 'gcd') {
            g <- 0
            for (b in abs(z)) {
              while (b != 0) {
                r <- g %% b
                g <- b
                b <- r
              }
            }
            return(g)
          }
          if (n %in% c('quotient', 'remainder', 'modulo')) {
            if (z[2] == 0) {
              fail(paste0(n, ': division by zero'))
            }
            q <- trunc(z[1] / z[2])
            return(
              if (n == 'quotient') {
                q
              } else if (n == 'modulo') {
                z[1] %% z[2]
              } else {
                z[1] - z[2] * q
              }
            )
          }
          if (length(z) < 2L) {
            return(TRUE)
          }
          l <- head(z, -1L)
          r <- tail(z, -1L)
          all(switch(
            n,
            '=' = l == r,
            '<' = l < r,
            '>' = l > r,
            '<=' = l <= r,
            '>=' = l >= r
          ))
        }
      )
    })
  }
  add('not', 1L, FALSE, function(a) identical(a[[1]], FALSE))
  add('eq?', 2L, FALSE, function(a) same(a[[1]], a[[2]]))
  add('equal?', 2L, FALSE, function(a) same(a[[1]], a[[2]], TRUE))
  for (name in c(
    'null?',
    'pair?',
    'list?',
    'number?',
    'symbol?',
    'procedure?'
  )) {
    local({
      n <- name
      add(n, 1L, FALSE, function(a) {
        switch(
          n,
          'null?' = identical(a[[1]], NIL),
          'pair?' = is_kind(a[[1]], 'pair'),
          'list?' = !is.null(items(a[[1]])),
          'number?' = is.numeric(a[[1]]),
          'symbol?' = is_kind(a[[1]], 'symbol'),
          'procedure?' = is_kind(a[[1]], 'procedure')
        )
      })
    })
  }
  add('cons', 2L, FALSE, function(a) pair(a[[1]], a[[2]]))
  add('list', 0L, TRUE, make_list)
  for (name in c('car', 'cdr', 'cadr')) {
    local({
      n <- name
      add(n, 1L, FALSE, function(a) {
        p <- expect(n, a[[1]], 'pair')
        if (n == 'car') {
          p$car
        } else if (n == 'cdr') {
          p$cdr
        } else {
          expect(n, p$cdr, 'pair')$car
        }
      })
    })
  }
  for (name in c('length', 'reverse', 'list-ref')) {
    local({
      n <- name
      add(n, if (n == 'list-ref') 2L else 1L, FALSE, function(a) {
        z <- items(expect(n, a[[1]], 'list'))
        if (n == 'length') {
          return(as.numeric(length(z)))
        }
        if (n == 'reverse') {
          return(make_list(rev(z)))
        }
        k <- expect(n, a[[2]], 'integer')
        if (k < 0 || k >= length(z)) {
          fail(paste0('list-ref: index out of range: ', repr(k)))
        }
        z[[k + 1]]
      })
    })
  }
  add('append', 0L, TRUE, function(a) {
    if (!length(a)) {
      return(NIL)
    }
    z <- list()
    for (v in head(a, -1L)) {
      z <- c(z, items(expect('append', v, 'list')))
    }
    make_list(z, a[[length(a)]])
  })
  for (name in c('map', 'filter', 'fold-left', 'apply')) {
    local({
      n <- name
      add(n, if (n == 'fold-left') 3L else 2L, n != 'filter', function(a) {
        f <- expect(n, a[[1]], 'procedure')
        if (n == 'apply') {
          return(call_proc(
            f,
            c(a[-c(1L, length(a))], items(expect(n, a[[length(a)]], 'list')))
          ))
        }
        first <- if (n == 'fold-left') 2L else 1L
        ls <- lapply(a[-seq_len(first)], function(v) {
          items(expect(n, v, 'list'))
        })
        count <- min(vapply(ls, length, 0L))
        out <- list()
        acc <- a[[2]]
        for (i in seq_len(count)) {
          if (n == 'filter') {
            if (!identical(call_proc(f, list(ls[[1]][[i]])), FALSE)) {
              out[[length(out) + 1L]] <- ls[[1]][[i]]
            }
          } else {
            args <- lapply(ls, `[[`, i)
            if (n == 'fold-left') {
              args <- c(list(acc), args)
            }
            v <- call_proc(f, args)
            if (n == 'map') out[[length(out) + 1L]] <- v else acc <- v
          }
        }
        if (n == 'fold-left') acc else make_list(out)
      })
    })
  }
  add('string-append', 0L, TRUE, function(a) {
    paste0(
      vapply(a, function(v) expect('string-append', v, 'string'), ''),
      collapse = ''
    )
  })
  add('number->string', 1L, FALSE, function(a) {
    repr(expect('number->string', a[[1]], 'integer'))
  })
  add('display', 1L, FALSE, function(a) {
    write_text(repr(a[[1]], FALSE))
    VOID
  })
  add('newline', 0L, FALSE, function(a) {
    write_text('\n')
    VOID
  })
  add('error', 1L, TRUE, function(a) {
    s <- expect('error', a[[1]], 'string')
    for (v in a[-1L]) {
      s <- paste0(s, ' ', repr(v))
    }
    fail(s)
  })
  e
}
lines <- readLines(file('stdin'), warn = FALSE)
last <- match('(exit)', lines)
if (!is.na(last)) {
  lines <- head(lines, last - 1L)
}
row <- 1L
column <- 1L
skip_line <- function() {
  row <<- row + 1L
  column <<- 1L
}
at_end <- function() {
  while (row <= length(lines)) {
    s <- lines[row]
    while (substr(s, column, column) == ' ' && column <= nchar(s)) {
      column <<- column + 1L
    }
    if (column <= nchar(s) && substr(s, column, column) != ';') {
      return(FALSE)
    }
    skip_line()
  }
  TRUE
}
next_token <- function() {
  if (at_end()) {
    fail('unexpected end of input')
  }
  s <- lines[row]
  c <- substr(s, column, column)
  column <<- column + 1L
  if (c %in% c('(', ')', "'")) {
    return(list(c, NULL))
  }
  if (c == '"') {
    v <- ''
    while (column <= nchar(s)) {
      c <- substr(s, column, column)
      column <<- column + 1L
      if (c == '"') {
        return(list('v', v))
      }
      if (c == '\\') {
        if (column > nchar(s)) {
          break
        }
        c <- substr(s, column, column)
        column <<- column + 1L
        if (!c %in% c('"', '\\', 'n')) {
          fail('bad escape')
        }
        if (c == 'n') c <- '\n'
      }
      v <- paste0(v, c)
    }
    fail('unterminated string')
  }
  start <- column - 1L
  while (
    column <= nchar(s) &&
      !substr(s, column, column) %in% c(' ', '(', ')', "'", '"', ';')
  ) {
    column <<- column + 1L
  }
  a <- substr(s, start, column - 1L)
  if (a == '.') {
    return(list('.', NULL))
  }
  if (grepl('^[+-]?[0-9]+$', a)) {
    return(list('v', as.numeric(a)))
  }
  if (a %in% c('#t', '#f')) {
    return(list('v', a == '#t'))
  }
  if (startsWith(a, '#')) {
    fail(paste0('bad token: ', a))
  }
  list('v', sym(a))
}
datum <- function(t = next_token()) {
  if (t[[1]] == 'v') {
    return(t[[2]])
  }
  if (t[[1]] == "'") {
    return(make_list(list(sym('quote'), datum())))
  }
  if (t[[1]] != '(') {
    fail(paste0('unexpected ', t[[1]]))
  }
  a <- list()
  repeat {
    t <- next_token()
    if (t[[1]] == ')') {
      return(make_list(a))
    }
    if (t[[1]] == '.' && length(a)) {
      tail <- datum()
      if (next_token()[[1]] != ')') {
        fail('expected )')
      }
      return(make_list(a, tail))
    }
    a[[length(a) + 1L]] <- datum(t)
  }
}
e <- global_env()
while (!at_end()) {
  result <- tryCatch(list(ok = TRUE, x = datum()), error = function(err) {
    list(ok = FALSE, message = conditionMessage(err))
  })
  if (!result$ok) {
    write_line(paste0('Error: read: ', result$message))
    if (result$message == 'unexpected end of input') {
      break
    }
    skip_line()
    next
  }
  tryCatch(
    {
      v <- evaluate(result$x, e)
      if (!identical(v, VOID)) write_line(repr(v))
    },
    error = function(err) write_line(paste0('Error: ', conditionMessage(err)))
  )
}
if (mid) {
  write_text('\n')
}
