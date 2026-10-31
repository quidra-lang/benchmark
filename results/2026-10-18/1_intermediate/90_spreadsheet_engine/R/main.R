EMPTY <- list("Z")
INVALID <- list("X")
num <- function(n) list("N", as.numeric(n))
text <- function(s) list("S", s)
err <- function(s) list("E", s)
fail <- function(s) stop(s, call. = FALSE)
ref <- function(c, r, f = 0L) {
  list("R", as.integer(c), as.integer(r), as.integer(f))
}
id <- function(r) r[[3]] * 26L + r[[2]] + 1L
label <- function(i) {
  paste0(intToUtf8(65L + (i - 1L) %% 26L), (i - 1L) %/% 26L + 1L)
}
inside <- function(r) r[[2]] >= 0 && r[[2]] < 26 && r[[3]] >= 0 && r[[3]] < 99
make_range <- function(a, b) {
  c <- a[[2]]
  r <- a[[3]]
  d <- b[[2]]
  t <- b[[3]]
  ac <- bitwAnd(a[[4]], 1L)
  ar <- bitwAnd(a[[4]], 2L)
  bc <- bitwAnd(b[[4]], 1L)
  br <- bitwAnd(b[[4]], 2L)
  if (c > d) {
    z <- c
    c <- d
    d <- z
    z <- ac
    ac <- bc
    bc <- z
  }
  if (r > t) {
    z <- r
    r <- t
    t <- z
    z <- ar
    ar <- br
    br <- z
  }
  list("G", ref(c, r, ac + ar), ref(d, t, bc + br))
}
address <- function(s) {
  if (!grepl("^[A-Z][1-9][0-9]?$", s)) {
    fail("bad address")
  }
  ref(utf8ToInt(substr(s, 1, 1)) - 65L, as.integer(substring(s, 2)) - 1L)
}
area <- function(s) {
  p <- regexpr(":", s, fixed = TRUE)[1]
  if (p < 0) {
    a <- address(s)
    return(make_range(a, a))
  }
  a <- address(substr(s, 1, p - 1))
  b <- address(substring(s, p + 1))
  make_range(a, b)
}
cells <- function(g) {
  as.integer(unlist(lapply(g[[2]][[3]]:g[[3]][[3]], function(r) {
    r * 26 + (g[[2]][[2]]:g[[3]][[2]]) + 1
  })))
}
contains <- function(g, r) {
  r[[2]] >= g[[2]][[2]] &&
    r[[2]] <= g[[3]][[2]] &&
    r[[3]] >= g[[2]][[3]] &&
    r[[3]] <= g[[3]][[3]]
}
levels <- list(
  c("=", "<>", "<", "<=", ">", ">="),
  "&",
  c("+", "-"),
  c("*", "/")
)
precedence <- function(op) {
  which(vapply(levels, function(xs) op %in% xs, logical(1)))[1]
}
parse_formula <- function(s) {
  tokens <- list()
  i <- 2L
  n <- nchar(s)
  syntax <- function(p) fail(paste("syntax error at", p))
  add <- function(x, p) {
    tokens[[length(tokens) + 1L]] <<- list(x, p)
  }
  while (i <= n) {
    p <- i
    ch <- substr(s, i, i)
    if (ch == " ") {
      i <- i + 1L
      next
    }
    if (grepl("[0-9]", ch)) {
      w <- regmatches(substring(s, i), regexpr("^[0-9]+", substring(s, i)))
      if (nchar(w) >= 10) {
        syntax(p)
      }
      add(num(as.numeric(w)), p)
      i <- i + nchar(w)
    } else if (ch == '"') {
      j <- i + 1L
      while (j <= n && substr(s, j, j) != '"') {
        j <- j + 1L
      }
      if (j > n) {
        syntax(p)
      }
      add(text(substr(s, i + 1L, j - 1L)), p)
      i <- j + 1L
    } else if (grepl("[A-Za-z$]", ch)) {
      w <- toupper(regmatches(
        substring(s, i),
        regexpr("^[A-Za-z0-9$]+", substring(s, i))
      ))
      i <- i + nchar(w)
      m <- regmatches(w, regexec("^(\\$?)([A-Z])(\\$?)([1-9][0-9]?)$", w))[[1]]
      if (length(m)) {
        x <- ref(
          utf8ToInt(m[3]) - 65L,
          as.integer(m[5]) - 1L,
          as.integer(m[2] != "") + 2L * as.integer(m[4] != "")
        )
      } else if (grepl("^[A-Z][A-Z0-9]*$", w)) {
        x <- list(if (grepl("^ *\\(", substring(s, i))) "C" else "W", w)
      } else {
        syntax(p)
      }
      add(x, p)
    } else {
      op <- substr(s, i, i + 1L)
      if (!op %in% c("<>", "<=", ">=")) {
        op <- ch
      }
      if (!ch %in% strsplit("+-*/&(),:=<>", "", fixed = TRUE)[[1]]) {
        syntax(p)
      }
      add(list("T", op), p)
      i <- i + nchar(op)
    }
  }
  add(list("END"), n + 1L)
  i <- 1L
  take <- function(op) {
    if (identical(tokens[[i]][[1]], list("T", op))) {
      i <<- i + 1L
      TRUE
    } else {
      FALSE
    }
  }
  expect <- function(op) {
    if (!take(op)) syntax(tokens[[i]][[2]])
  }
  expression <- function(level = 1L) {
    if (level == 5L) {
      return(primary())
    }
    a <- expression(level + 1L)
    while (
      tokens[[i]][[1]][[1]] == "T" && tokens[[i]][[1]][[2]] %in% levels[[level]]
    ) {
      op <- tokens[[i]][[1]][[2]]
      i <<- i + 1L
      a <- list("B", op, a, expression(level + 1L))
    }
    a
  }
  primary <- function() {
    if (take("-")) {
      return(list("U", primary()))
    }
    x <- tokens[[i]][[1]]
    p <- tokens[[i]][[2]]
    i <<- i + 1L
    if (x[[1]] %in% c("N", "S", "W")) {
      return(x)
    }
    if (x[[1]] == "R") {
      if (!take(":")) {
        return(x)
      }
      if (tokens[[i]][[1]][[1]] != "R") {
        syntax(tokens[[i]][[2]])
      }
      b <- tokens[[i]][[1]]
      i <<- i + 1L
      return(make_range(x, b))
    }
    if (x[[1]] == "C") {
      expect("(")
      args <- list()
      if (!take(")")) {
        args[[1]] <- expression()
        while (take(",")) {
          args[[length(args) + 1L]] <- expression()
        }
        expect(")")
      }
      return(list("F", x[[2]], args))
    }
    if (identical(x, list("T", "("))) {
      a <- expression()
      expect(")")
      return(a)
    }
    syntax(p)
  }
  tree <- expression()
  if (tokens[[i]][[1]][[1]] != "END") {
    syntax(tokens[[i]][[2]])
  }
  tree
}
decimal <- function(n) sprintf("%.0f", if (n == 0) 0 else n)
canonical <- function(x) {
  switch(
    x[[1]],
    N = decimal(x[[2]]),
    S = paste0('"', x[[2]], '"'),
    W = x[[2]],
    X = "#REF!",
    R = paste0(
      if (bitwAnd(x[[4]], 1L)) "$" else "",
      intToUtf8(65L + x[[2]]),
      if (bitwAnd(x[[4]], 2L)) "$" else "",
      x[[3]] + 1L
    ),
    G = paste0(canonical(x[[2]]), ":", canonical(x[[3]])),
    F = paste0(
      x[[2]],
      "(",
      paste(vapply(x[[3]], canonical, ""), collapse = ","),
      ")"
    ),
    U = paste0(
      "-",
      if (x[[2]][[1]] == "B") {
        paste0("(", canonical(x[[2]]), ")")
      } else {
        canonical(x[[2]])
      }
    ),
    B = {
      a <- canonical(x[[3]])
      b <- canonical(x[[4]])
      if (x[[3]][[1]] == "B" && precedence(x[[3]][[2]]) < precedence(x[[2]])) {
        a <- paste0("(", a, ")")
      }
      if (x[[4]][[1]] == "B" && precedence(x[[4]][[2]]) <= precedence(x[[2]])) {
        b <- paste0("(", b, ")")
      }
      paste0(a, x[[2]], b)
    }
  )
}
display <- function(x) {
  if (x[[1]] == "Z") {
    ""
  } else if (x[[1]] == "N") {
    decimal(x[[2]])
  } else {
    x[[2]]
  }
}
notation <- function(x) {
  if (x[[1]] == "Z") {
    "(empty)"
  } else if (x[[1]] == "=") {
    paste0("=", canonical(x[[2]]))
  } else if (x[[1]] == "S") {
    paste0('"', x[[2]], '"')
  } else {
    display(x)
  }
}
to_number <- function(x) {
  if (x[[1]] == "Z") {
    num(0)
  } else if (x[[1]] %in% c("S", "G")) {
    err("#VALUE!")
  } else {
    x
  }
}
to_string <- function(x) {
  if (x[[1]] == "Z") {
    text("")
  } else if (x[[1]] == "N") {
    text(decimal(x[[2]]))
  } else if (x[[1]] == "G") {
    err("#VALUE!")
  } else {
    x
  }
}
rewrite <- function(x, f) {
  switch(
    x[[1]],
    R = f(x),
    G = f(x),
    F = list("F", x[[2]], lapply(x[[3]], rewrite, f)),
    B = list("B", x[[2]], rewrite(x[[3]], f), rewrite(x[[4]], f)),
    U = list("U", rewrite(x[[2]], f)),
    "=" = list("=", rewrite(x[[2]], f)),
    x
  )
}
dependencies <- function(x) {
  switch(
    x[[1]],
    R = id(x),
    G = cells(x),
    F = unique(as.integer(unlist(lapply(x[[3]], dependencies)))),
    B = union(dependencies(x[[3]]), dependencies(x[[4]])),
    U = dependencies(x[[2]]),
    "=" = dependencies(x[[2]]),
    integer()
  )
}
grid <- function() rep(list(EMPTY), 2574L)
sheet <- new.env()
sheet$contents <- grid()
sheet$values <- grid()
sheet$deps <- rep(list(integer()), 2574L)
sheet$history <- list()
evaluate <- function(x) {
  k <- x[[1]]
  if (k %in% c("N", "S", "G")) {
    return(x)
  }
  if (k == "R") {
    return(sheet$values[[id(x)]])
  }
  if (k == "W") {
    return(err("#NAME?"))
  }
  if (k == "X") {
    return(err("#REF!"))
  }
  if (k == "U") {
    a <- to_number(evaluate(x[[2]]))
    return(if (a[[1]] == "E") a else num(-a[[2]]))
  }
  if (k == "F") {
    return(call_function(x[[2]], x[[3]]))
  }
  a <- evaluate(x[[3]])
  b <- evaluate(x[[4]])
  op <- x[[2]]
  if (a[[1]] == "E") {
    return(a)
  }
  if (b[[1]] == "E") {
    return(b)
  }
  if (precedence(op) == 1L) {
    if (a[[1]] == "G" || b[[1]] == "G") {
      return(err("#VALUE!"))
    }
    blank <- if (a[[1]] == "S" || b[[1]] == "S") text("") else num(0)
    if (a[[1]] == "Z") {
      a <- blank
    }
    if (b[[1]] == "Z") {
      b <- blank
    }
    if (a[[1]] != b[[1]]) {
      c <- if (a[[1]] == "N") -1 else 1
    } else if (a[[1]] == "N") {
      c <- sign(a[[2]] - b[[2]])
    } else {
      aa <- utf8ToInt(a[[2]])
      bb <- utf8ToInt(b[[2]])
      c <- sign(length(aa) - length(bb))
      for (j in seq_len(min(length(aa), length(bb)))) {
        if (aa[j] != bb[j]) {
          c <- sign(aa[j] - bb[j])
          break
        }
      }
    }
    return(num(as.integer(switch(
      op,
      "=" = c == 0,
      "<>" = c != 0,
      "<" = c < 0,
      "<=" = c <= 0,
      ">" = c > 0,
      ">=" = c >= 0
    ))))
  }
  convert <- if (op == "&") to_string else to_number
  a <- convert(a)
  b <- convert(b)
  if (a[[1]] == "E") {
    return(a)
  }
  if (b[[1]] == "E") {
    return(b)
  }
  switch(
    op,
    "&" = text(paste0(a[[2]], b[[2]])),
    "+" = num(a[[2]] + b[[2]]),
    "-" = num(a[[2]] - b[[2]]),
    "*" = num(a[[2]] * b[[2]]),
    "/" = if (b[[2]] == 0) err("#DIV/0!") else num(trunc(a[[2]] / b[[2]]))
  )
}
call_function <- function(name, args) {
  if (
    name %in% c("SUM", "MIN", "MAX", "COUNT", "AVERAGE", "AND", "OR", "CONCAT")
  ) {
    if (!length(args)) {
      return(err("#VALUE!"))
    }
    items <- list()
    for (a in args) {
      v <- evaluate(a)
      items <- c(items, if (v[[1]] == "G") sheet$values[cells(v)] else list(v))
    }
    ns <- vapply(
      Filter(function(v) v[[1]] == "N", items),
      function(v) v[[2]],
      numeric(1)
    )
    if (name == "COUNT") {
      return(num(length(ns)))
    }
    for (v in items) {
      if (v[[1]] == "E") return(v)
    }
    return(switch(
      name,
      SUM = num(sum(ns)),
      MIN = num(if (length(ns)) min(ns) else 0),
      MAX = num(if (length(ns)) max(ns) else 0),
      AVERAGE = if (length(ns)) {
        num(trunc(sum(ns) / length(ns)))
      } else {
        err("#DIV/0!")
      },
      AND = if (length(ns)) num(as.integer(all(ns != 0))) else err("#VALUE!"),
      OR = if (length(ns)) num(as.integer(any(ns != 0))) else err("#VALUE!"),
      CONCAT = text(paste(
        vapply(items, function(v) to_string(v)[[2]], ""),
        collapse = ""
      ))
    ))
  }
  if (name == "IF") {
    if (!length(args) %in% c(2L, 3L)) {
      return(err("#VALUE!"))
    }
    c <- to_number(evaluate(args[[1]]))
    if (c[[1]] == "E") {
      return(c)
    }
    return(
      if (c[[2]] != 0) {
        evaluate(args[[2]])
      } else if (length(args) == 3L) {
        evaluate(args[[3]])
      } else {
        num(0)
      }
    )
  }
  if (!name %in% c("ABS", "NOT", "LEN")) {
    return(err("#NAME?"))
  }
  if (length(args) != 1L) {
    return(err("#VALUE!"))
  }
  v <- evaluate(args[[1]])
  v <- if (name == "LEN") to_string(v) else to_number(v)
  if (v[[1]] == "E") {
    v
  } else {
    num(
      if (name == "LEN") {
        nchar(v[[2]])
      } else if (name == "ABS") {
        abs(v[[2]])
      } else {
        as.integer(v[[2]] == 0)
      }
    )
  }
}
recalculate <- function() {
  sheet$deps <- lapply(sheet$contents, function(x) {
    if (x[[1]] == "=") dependencies(x[[2]]) else integer()
  })
  sheet$values <- lapply(sheet$contents, function(x) {
    if (x[[1]] == "=") EMPTY else x
  })
  indices <- rep(-1L, 2574L)
  low <- integer(2574L)
  on <- cyclic <- done <- rep(FALSE, 2574L)
  stack <- integer()
  serial <- 0L
  visit <- function(i) {
    indices[i] <<- serial
    low[i] <<- serial
    serial <<- serial + 1L
    stack <<- c(stack, i)
    on[i] <<- TRUE
    for (j in sheet$deps[[i]]) {
      if (sheet$contents[[j]][[1]] == "=") {
        if (indices[j] < 0) {
          visit(j)
          low[i] <<- min(low[i], low[j])
        } else if (on[j]) {
          low[i] <<- min(low[i], indices[j])
        }
      }
    }
    if (low[i] == indices[i]) {
      part <- integer()
      repeat {
        j <- tail(stack, 1L)
        stack <<- head(stack, -1L)
        on[j] <<- FALSE
        part <- c(part, j)
        if (j == i) break
      }
      if (length(part) > 1L || i %in% sheet$deps[[i]]) cyclic[part] <<- TRUE
    }
  }
  for (i in seq_len(2574L)) {
    if (sheet$contents[[i]][[1]] == "=" && indices[i] < 0) visit(i)
  }
  calculate <- function(i) {
    if (sheet$contents[[i]][[1]] != "=" || done[i]) {
      return()
    }
    done[i] <<- TRUE
    if (cyclic[i]) {
      sheet$values[[i]] <- err("#CYCLE!")
      return()
    }
    for (j in sheet$deps[[i]]) {
      calculate(j)
    }
    v <- evaluate(sheet$contents[[i]][[2]])
    sheet$values[[i]] <- if (v[[1]] == "Z") {
      num(0)
    } else if (v[[1]] == "G") {
      err("#VALUE!")
    } else {
      v
    }
  }
  for (i in seq_len(2574L)) {
    calculate(i)
  }
}
replace_contents <- function(next_grid) {
  old <- sheet$values
  sheet$contents <- next_grid
  recalculate()
  sum(vapply(
    seq_len(2574L),
    function(i) !identical(old[[i]], sheet$values[[i]]),
    logical(1)
  ))
}
describe <- function(i) {
  paste0(
    label(i),
    ": ",
    notation(sheet$contents[[i]]),
    " -> ",
    notation(sheet$values[[i]])
  )
}
split_first <- function(s) {
  p <- regexpr(" ", s, fixed = TRUE)[1]
  if (p < 0) c(s, "") else c(substr(s, 1, p - 1), substring(s, p + 1))
}
execute <- function(line) {
  parts <- split_first(line)
  name <- parts[1]
  rest <- parts[2]
  if (name == "SHOW") {
    return(describe(id(address(rest))))
  }
  if (name == "LIST") {
    ids <- which(vapply(sheet$contents, function(x) x[[1]] != "Z", logical(1)))
    return(if (length(ids)) vapply(ids, describe, "") else "(no cells)")
  }
  if (name == "DEPS") {
    i <- id(address(rest))
    format <- function(xs) {
      if (length(xs)) {
        paste(vapply(sort(xs), label, ""), collapse = ",")
      } else {
        "none"
      }
    }
    ds <- which(vapply(sheet$deps, function(xs) i %in% xs, logical(1)))
    return(paste0(
      rest,
      ": precedents=",
      format(sheet$deps[[i]]),
      " dependents=",
      format(ds)
    ))
  }
  if (name == "PRINT") {
    g <- area(rest)
    rs <- g[[2]][[3]]:g[[3]][[3]]
    cs <- g[[2]][[2]]:g[[3]][[2]]
    rw <- nchar(as.character(g[[3]][[3]] + 1L))
    ws <- vapply(
      cs,
      function(c) {
        max(
          1L,
          vapply(
            rs,
            function(r) nchar(display(sheet$values[[r * 26 + c + 1L]])),
            integer(1)
          )
        )
      },
      integer(1)
    )
    sep <- paste0(
      "+",
      strrep("-", rw),
      "+",
      paste0(strrep("-", ws), "+", collapse = "")
    )
    pad <- function(s, w, right = FALSE) {
      if (right) {
        paste0(strrep(" ", w - nchar(s)), s)
      } else {
        paste0(s, strrep(" ", w - nchar(s)))
      }
    }
    head <- paste0(
      "|",
      strrep(" ", rw),
      "|",
      paste(
        vapply(
          seq_along(cs),
          function(j) paste0(pad(intToUtf8(65L + cs[j]), ws[j]), "|"),
          ""
        ),
        collapse = ""
      )
    )
    out <- c(sep, head, sep)
    for (r in rs) {
      out <- c(
        out,
        paste0(
          "|",
          pad(as.character(r + 1L), rw, TRUE),
          "|",
          paste(
            vapply(
              seq_along(cs),
              function(j) {
                v <- sheet$values[[r * 26 + cs[j] + 1L]]
                paste0(pad(display(v), ws[j], v[[1]] == "N"), "|")
              },
              ""
            ),
            collapse = ""
          )
        )
      )
    }
    return(c(out, sep))
  }
  if (name == "UNDO") {
    n <- length(sheet$history)
    if (!n) {
      fail("nothing to undo")
    }
    entry <- sheet$history[[n]]
    sheet$history <- head(sheet$history, -1L)
    return(paste0(
      "UNDO ",
      entry[[1]],
      " changed=",
      replace_contents(entry[[2]])
    ))
  }
  next_grid <- sheet$contents
  target <- -1L
  if (name == "SET") {
    p <- split_first(rest)
    target <- id(address(p[1]))
    s <- p[2]
    if (startsWith(s, "=")) {
      next_grid[[target]] <- list("=", parse_formula(s))
    } else if (grepl('^"[^"]*"$', s)) {
      next_grid[[target]] <- text(substr(s, 2, nchar(s) - 1))
    } else if (grepl("^(0|-?[1-9][0-9]{0,8})$", s)) {
      next_grid[[target]] <- num(as.numeric(s))
    } else {
      fail("bad value")
    }
  } else if (name == "CLEAR") {
    for (i in cells(area(rest))) {
      next_grid[[i]] <- EMPTY
    }
  } else if (name %in% c("COPY", "MOVE")) {
    p <- split_first(rest)
    source <- area(p[1])
    dest <- address(p[2])
    dc <- dest[[2]] - source[[2]][[2]]
    dr <- dest[[3]] - source[[2]][[3]]
    shift <- function(r, relative) {
      ref(
        r[[2]] + if (relative && bitwAnd(r[[4]], 1L) != 0) 0 else dc,
        r[[3]] + if (relative && bitwAnd(r[[4]], 2L) != 0) 0 else dr,
        r[[4]]
      )
    }
    destination <- make_range(
      shift(source[[2]], FALSE),
      shift(source[[3]], FALSE)
    )
    if (!inside(destination[[2]]) || !inside(destination[[3]])) {
      fail("out of grid")
    }
    transform <- function(x) {
      if (x[[1]] == "R") {
        if (name == "COPY") {
          r <- shift(x, TRUE)
          return(if (inside(r)) r else INVALID)
        }
        return(
          if (contains(source, x)) {
            shift(x, FALSE)
          } else if (contains(destination, x)) {
            INVALID
          } else {
            x
          }
        )
      }
      if (
        name == "MOVE" &&
          !(contains(source, x[[2]]) && contains(source, x[[3]]))
      ) {
        return(x)
      }
      a <- shift(x[[2]], name == "COPY")
      b <- shift(x[[3]], name == "COPY")
      if (inside(a) && inside(b)) make_range(a, b) else INVALID
    }
    if (name == "MOVE") {
      next_grid <- lapply(next_grid, rewrite, transform)
    }
    ids <- cells(source)
    moving <- lapply(ids, function(i) {
      if (name == "COPY") {
        rewrite(sheet$contents[[i]], transform)
      } else {
        next_grid[[i]]
      }
    })
    if (name == "MOVE") {
      for (i in ids) {
        next_grid[[i]] <- EMPTY
      }
    }
    for (j in seq_along(ids)) {
      next_grid[[ids[j] + dr * 26 + dc]] <- moving[[j]]
    }
  } else if (name %in% c("INSERTROW", "DELETEROW", "INSERTCOL", "DELETECOL")) {
    row <- endsWith(name, "ROW")
    insert <- startsWith(name, "INSERT")
    if (!grepl(if (row) "^[1-9][0-9]?$" else "^[A-Z]$", rest)) {
      fail("bad address")
    }
    at <- if (row) as.integer(rest) - 1L else utf8ToInt(rest) - 65L
    limit <- if (row) 99L else 26L
    axis <- function(x) x[[if (row) 3L else 2L]]
    change <- function(x, v) {
      if (row) ref(x[[2]], v, x[[4]]) else ref(v, x[[3]], x[[4]])
    }
    if (insert) {
      for (i in seq_len(2574L)) {
        if (
          sheet$contents[[i]][[1]] != "Z" &&
            (if (row) (i - 1L) %/% 26L else (i - 1L) %% 26L) == limit - 1L
        ) {
          fail(paste("last", if (row) "row" else "column", "not empty"))
        }
      }
    }
    transform <- function(x) {
      if (x[[1]] == "R") {
        v <- axis(x)
        if (!insert && v == at) {
          return(INVALID)
        }
        n <- v + if (insert) as.integer(v >= at) else -as.integer(v > at)
        return(if (n >= limit) INVALID else change(x, n))
      }
      a <- axis(x[[2]])
      b <- axis(x[[3]])
      if (!insert && a == at && b == at) {
        return(INVALID)
      }
      u <- a + if (insert) as.integer(a >= at) else -as.integer(a > at)
      v <- b + if (insert) as.integer(b >= at) else -as.integer(b >= at)
      if (v >= limit) {
        INVALID
      } else {
        make_range(change(x[[2]], u), change(x[[3]], v))
      }
    }
    next_grid <- grid()
    for (i in seq_len(2574L)) {
      if (sheet$contents[[i]][[1]] != "Z") {
        r <- ref((i - 1L) %% 26L, (i - 1L) %/% 26L)
        v <- axis(r)
        if (!insert && v == at) {
          next
        }
        t <- change(
          r,
          v + if (insert) as.integer(v >= at) else -as.integer(v > at)
        )
        next_grid[[id(t)]] <- rewrite(sheet$contents[[i]], transform)
      }
    }
  } else {
    fail("unknown command")
  }
  sheet$history[[length(sheet$history) + 1L]] <- list(name, sheet$contents)
  changed <- replace_contents(next_grid)
  paste0(
    name,
    if (name == "SET") {
      paste0(" ", label(target), "=", notation(sheet$values[[target]]))
    } else {
      ""
    },
    " changed=",
    changed
  )
}
lines <- readLines(file("stdin"), warn = FALSE)
for (i in seq_len(as.integer(lines[1]))) {
  out <- tryCatch(execute(lines[i + 1L]), error = function(e) {
    paste("ERROR", conditionMessage(e))
  })
  cat(paste(out, collapse = "\n"), "\n", sep = "")
}
