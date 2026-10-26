functions <- c('sin', 'cos', 'tan', 'exp', 'ln', 'sqrt')
fail <- function(s) stop(s, call. = FALSE)
rational <- function(p, q = 1) {
  if (q == 0) {
    fail('division by zero')
  }
  if (q < 0) {
    p <- -p
    q <- -q
  }
  a <- abs(p)
  b <- q
  while (b != 0) {
    t <- a %% b
    a <- b
    b <- t
  }
  c(p / a, q / a)
}
qadd <- function(a, b) rational(a[1] * b[2] + b[1] * a[2], a[2] * b[2])
qmul <- function(a, b) rational(a[1] * b[1], a[2] * b[2])
qneg <- function(a) c(-a[1], a[2])
num <- function(p, q = 1) {
  list(
    kind = 5,
    q = if (length(p) == 2) p else rational(p, q),
    name = '',
    args = list()
  )
}
node <- function(k, a = list(), s = '') {
  list(kind = k, q = c(0, 1), name = s, args = a)
}
zero <- num(0)
one <- num(1)
minus <- num(-1)
half <- num(1, 2)
compare <- function(a, b) {
  if (a$kind != b$kind) {
    return(sign(a$kind - b$kind))
  }
  if (a$kind == 5) {
    return(sign(a$q[1] * b$q[2] - b$q[1] * a$q[2]))
  }
  if (a$name != b$name) {
    x <- utf8ToInt(a$name)
    y <- utf8ToInt(b$name)
    for (i in seq_len(min(length(x), length(y)))) {
      if (x[i] != y[i]) return(sign(x[i] - y[i]))
    }
    return(sign(length(x) - length(y)))
  }
  for (i in seq_len(min(length(a$args), length(b$args)))) {
    c <- compare(a$args[[i]], b$args[[i]])
    if (c != 0) return(c)
  }
  sign(length(a$args) - length(b$args))
}
equal <- function(a, b) compare(a, b) == 0
integer_form <- function(f) f$kind == 5 && f$q[2] == 1
negative <- function(f) {
  f$kind == 3 && f$args[[2]]$kind == 5 && f$args[[2]]$q[1] < 0
}
base_of <- function(f) if (f$kind == 3) f$args[[1]] else f
exponent_of <- function(f) if (f$kind == 3) f$args[[2]] else one
coefficient <- function(f) {
  if (f$kind == 5) {
    return(list(f$q, list()))
  }
  if (f$kind == 2) {
    return(
      if (f$args[[1]]$kind == 5) {
        list(f$args[[1]]$q, f$args[-1])
      } else {
        list(c(1, 1), f$args)
      }
    )
  }
  list(c(1, 1), list(f))
}
product <- function(c, a) {
  if (!length(a)) {
    return(num(c))
  }
  if (c[1] != c[2]) {
    a <- c(list(num(c)), a)
  }
  if (length(a) == 1) a[[1]] else node(2, a)
}
sort_forms <- function(a, cmp) {
  if (length(a) < 2) {
    return(a)
  }
  for (i in 2:length(a)) {
    v <- a[[i]]
    j <- i - 1
    while (j >= 1 && cmp(a[[j]], v) > 0) {
      a[[j + 1]] <- a[[j]]
      j <- j - 1
    }
    a[[j + 1]] <- v
  }
  a
}
find_form <- function(a, b) {
  for (i in seq_along(a)) {
    if (equal(a[[i]], b)) return(i)
  }
  0L
}
exponent_compare <- function(a, b) {
  if (a$kind == 5 && b$kind != 5) {
    return(-1)
  }
  if (a$kind != 5 && b$kind == 5) {
    return(1)
  }
  compare(a, b)
}
term_compare <- function(a, b) {
  x <- coefficient(a)[[2]]
  y <- coefficient(b)[[2]]
  bases <- list()
  for (f in c(x, y)) {
    b <- base_of(f)
    if (!find_form(bases, b)) bases[[length(bases) + 1]] <- b
  }
  for (b in sort_forms(bases, compare)) {
    u <- zero
    v <- zero
    for (f in x) {
      if (equal(base_of(f), b)) u <- exponent_of(f)
    }
    for (f in y) {
      if (equal(base_of(f), b)) v <- exponent_of(f)
    }
    c <- exponent_compare(v, u)
    if (c != 0) return(c)
  }
  0
}
add <- function(operands) {
  terms <- list()
  for (f in operands) {
    if (f$kind == 1) {
      terms <- c(terms, f$args)
    } else if (
      f$kind == 2 &&
        length(f$args) == 2 &&
        f$args[[1]]$kind == 5 &&
        f$args[[2]]$kind == 1
    ) {
      terms <- c(
        terms,
        lapply(f$args[[2]]$args, function(t) mul(list(f$args[[1]], t)))
      )
    } else {
      terms[[length(terms) + 1]] <- f
    }
  }
  keys <- list()
  values <- list()
  for (f in terms) {
    parts <- coefficient(f)
    co <- parts[[1]]
    m <- parts[[2]]
    i <- 0L
    for (j in seq_along(keys)) {
      if (
        length(m) == length(keys[[j]]) &&
          all(vapply(
            seq_along(m),
            function(k) equal(m[[k]], keys[[j]][[k]]),
            logical(1)
          ))
      ) {
        i <- j
        break
      }
    }
    if (i == 0) {
      keys[[length(keys) + 1]] <- m
      values[[length(values) + 1]] <- co
    } else {
      values[[i]] <- qadd(values[[i]], co)
    }
  }
  built <- list()
  for (i in seq_along(keys)) {
    if (values[[i]][1] != 0) {
      built[[length(built) + 1]] <- product(values[[i]], keys[[i]])
    }
  }
  built <- sort_forms(built, term_compare)
  if (!length(built)) {
    zero
  } else if (length(built) == 1) {
    built[[1]]
  } else {
    node(1, built)
  }
}
mul <- function(operands) {
  co <- c(1, 1)
  bases <- list()
  groups <- list()
  factors <- list()
  for (f in operands) {
    factors <- c(factors, if (f$kind == 2) f$args else list(f))
  }
  for (f in factors) {
    if (f$kind == 5) {
      co <- qmul(co, f$q)
    } else {
      b <- base_of(f)
      i <- find_form(bases, b)
      if (i == 0) {
        bases[[length(bases) + 1]] <- b
        groups[[length(groups) + 1]] <- list(f)
      } else {
        groups[[i]][[length(groups[[i]]) + 1]] <- f
      }
    }
  }
  if (co[1] == 0) {
    return(zero)
  }
  results <- lapply(seq_along(groups), function(i) {
    if (length(groups[[i]]) == 1) {
      groups[[i]][[1]]
    } else {
      power(bases[[i]], add(lapply(groups[[i]], exponent_of)))
    }
  })
  regroup <- FALSE
  seen <- list()
  for (f in results) {
    b <- base_of(f)
    if (f$kind %in% c(2, 5) || find_form(seen, b) > 0) {
      regroup <- TRUE
    }
    seen[[length(seen) + 1]] <- b
  }
  if (regroup) {
    return(mul(c(list(num(co)), results)))
  }
  product(
    co,
    sort_forms(results, function(a, b) compare(base_of(a), base_of(b)))
  )
}
integer_root <- function(v, d) {
  if (v == 1) {
    return(1)
  }
  if (d > 20) {
    return(NA_real_)
  }
  r <- round(v^(1 / d))
  for (s in seq(max(0, r - 1), r + 1)) {
    if (s^d == v) return(s)
  }
  NA_real_
}
rational_power <- function(b, n) {
  if (n < 0) {
    b <- rational(b[2], b[1])
    n <- -n
  }
  r <- c(1, 1)
  while (n > 0) {
    if (n %% 2) {
      r <- qmul(r, b)
    }
    n <- n %/% 2
    if (n > 0) b <- qmul(b, b)
  }
  num(r)
}
power <- function(b, x) {
  if (equal(x, zero)) {
    return(one)
  }
  if (equal(x, one)) {
    return(b)
  }
  if (b$kind == 5) {
    if (equal(b, one)) {
      return(one)
    }
    if (x$kind != 5) {
      return(node(3, list(b, x)))
    }
    if (b$q[1] == 0) {
      if (x$q[1] > 0) {
        return(zero)
      }
      fail('division by zero')
    }
    if (integer_form(x)) {
      return(rational_power(b$q, x$q[1]))
    }
    if (b$q[1] > 0) {
      s <- integer_root(b$q[1], x$q[2])
      t <- integer_root(b$q[2], x$q[2])
      if (!is.na(s) && !is.na(t)) return(rational_power(rational(s, t), x$q[1]))
    }
  } else if (integer_form(x)) {
    if (b$kind == 3) {
      return(power(b$args[[1]], mul(list(b$args[[2]], x))))
    }
    if (b$kind == 2) return(mul(lapply(b$args, function(f) power(f, x))))
  }
  node(3, list(b, x))
}
apply_function <- function(s, a) {
  if (s == 'sqrt') {
    return(power(a, half))
  }
  if (equal(a, zero) && s %in% c('sin', 'tan')) {
    return(zero)
  }
  if (equal(a, zero) && s %in% c('cos', 'exp')) {
    return(one)
  }
  if (equal(a, one) && s == 'ln') {
    return(zero)
  }
  if (s %in% c('sin', 'cos', 'tan') && coefficient(a)[[1]][1] < 0) {
    r <- apply_function(s, mul(list(minus, a)))
    return(if (s == 'cos') r else mul(list(minus, r)))
  }
  if (
    a$kind == 4 &&
      ((s == 'exp' && a$name == 'ln') || (s == 'ln' && a$name == 'exp'))
  ) {
    return(a$args[[1]])
  }
  node(4, list(a), s)
}
variables <- function(f) {
  if (f$kind == 0) {
    return(f$name)
  }
  sort(
    unique(unlist(lapply(f$args, variables), use.names = FALSE)),
    method = 'radix'
  )
}
derivative <- function(f, v) {
  if (f$kind == 5) {
    return(zero)
  }
  if (f$kind == 0) {
    return(if (f$name == v) one else zero)
  }
  if (f$kind == 1) {
    return(add(lapply(f$args, function(t) derivative(t, v))))
  }
  if (f$kind == 2) {
    return(add(lapply(seq_along(f$args), function(i) {
      a <- f$args
      a[[i]] <- derivative(a[[i]], v)
      mul(a)
    })))
  }
  if (f$kind == 3) {
    b <- f$args[[1]]
    x <- f$args[[2]]
    if (!v %in% variables(x)) {
      return(mul(list(x, power(b, add(list(x, minus))), derivative(b, v))))
    }
    if (!v %in% variables(b)) {
      return(mul(list(f, apply_function('ln', b), derivative(x, v))))
    }
    return(mul(list(
      f,
      add(list(
        mul(list(derivative(x, v), apply_function('ln', b))),
        mul(list(x, derivative(b, v), power(b, minus)))
      ))
    )))
  }
  a <- f$args[[1]]
  h <- switch(
    f$name,
    sin = apply_function('cos', a),
    cos = mul(list(minus, apply_function('sin', a))),
    tan = power(apply_function('cos', a), num(-2)),
    exp = f,
    ln = power(a, minus)
  )
  mul(list(h, derivative(a, v)))
}
rebuild <- function(f, a) {
  switch(
    as.character(f$kind),
    '1' = add(a),
    '2' = mul(a),
    '3' = power(a[[1]], a[[2]]),
    '4' = apply_function(f$name, a[[1]])
  )
}
substitute_form <- function(f, m) {
  if (f$kind == 0) {
    return(if (!is.null(m[[f$name]])) m[[f$name]] else f)
  }
  if (f$kind == 5) {
    return(f)
  }
  rebuild(f, lapply(f$args, function(t) substitute_form(t, m)))
}
terms <- function(f) if (f$kind == 1) f$args else list(f)
distribute <- function(a, b) {
  r <- list()
  for (x in terms(a)) {
    for (y in terms(b)) {
      r[[length(r) + 1]] <- mul(list(x, y))
    }
  }
  add(r)
}
expand <- function(f) {
  if (f$kind %in% c(0, 5)) {
    return(f)
  }
  a <- lapply(f$args, expand)
  if (f$kind == 2) {
    return(Reduce(distribute, a))
  }
  if (
    f$kind == 3 && a[[1]]$kind == 1 && integer_form(a[[2]]) && a[[2]]$q[1] > 0
  ) {
    r <- a[[1]]
    for (i in seq_len(a[[2]]$q[1] - 1)) {
      r <- distribute(r, a[[1]])
    }
    return(r)
  }
  rebuild(f, a)
}
numeric_value <- function(f) {
  if (f$kind == 5) {
    return(f$q[1] / f$q[2])
  }
  if (f$kind == 1) {
    return(Reduce(function(r, t) r + numeric_value(t), f$args, init = 0))
  }
  if (f$kind == 2) {
    return(Reduce(function(r, t) r * numeric_value(t), f$args, init = 1))
  }
  if (f$kind == 3) {
    u <- numeric_value(f$args[[1]])
    z <- numeric_value(f$args[[2]])
    integral <- if (f$args[[2]]$kind == 5) {
      integer_form(f$args[[2]])
    } else {
      z == trunc(z)
    }
    if (u < 0 && !integral) {
      fail('domain error')
    }
    return(if (equal(f$args[[2]], half)) sqrt(u) else u^z)
  }
  a <- numeric_value(f$args[[1]])
  if (f$name == 'ln' && a <= 0) {
    fail('domain error')
  }
  switch(
    f$name,
    sin = sin(a),
    cos = cos(a),
    tan = tan(a),
    exp = exp(a),
    ln = log(a)
  )
}
atomic <- function(f) {
  f$kind %in%
    c(0, 4) ||
    (integer_form(f) && f$q[1] >= 0) ||
    (f$kind == 3 && equal(f$args[[2]], half))
}
atom <- function(f) {
  if (atomic(f)) show_form(f) else paste0('(', show_form(f), ')')
}
show_power <- function(b, x) {
  if (equal(x, half)) {
    paste0('sqrt(', show_form(b), ')')
  } else {
    paste0(atom(b), '^', atom(x))
  }
}
factor_text <- function(f) {
  if (f$kind == 1) {
    paste0('(', show_form(f), ')')
  } else if (f$kind == 3) {
    show_power(f$args[[1]], f$args[[2]])
  } else {
    show_form(f)
  }
}
quotient <- function(co, a) {
  p <- abs(co[1])
  q <- co[2]
  top <- if (p != 1) sprintf('%.0f', p) else character()
  bottom <- if (q != 1) sprintf('%.0f', q) else character()
  for (f in a) {
    if (negative(f)) {
      r <- num(qneg(f$args[[2]]$q))
      bottom <- c(
        bottom,
        if (equal(r, one)) {
          factor_text(f$args[[1]])
        } else {
          show_power(f$args[[1]], r)
        }
      )
    } else {
      top <- c(top, factor_text(f))
    }
  }
  s <- if (!length(top)) '1' else paste(top, collapse = '*')
  if (length(bottom) == 1) {
    s <- paste0(s, '/', bottom)
  } else if (length(bottom) > 1) {
    s <- paste0(s, '/(', paste(bottom, collapse = '*'), ')')
  }
  paste0(if (co[1] < 0) '-' else '', s)
}
show_form <- function(f) {
  if (f$kind == 5) {
    return(paste0(
      sprintf('%.0f', f$q[1]),
      if (f$q[2] == 1) '' else paste0('/', sprintf('%.0f', f$q[2]))
    ))
  }
  if (f$kind == 0) {
    return(f$name)
  }
  if (f$kind == 4) {
    return(paste0(f$name, '(', show_form(f$args[[1]]), ')'))
  }
  if (f$kind == 3) {
    return(
      if (negative(f)) {
        quotient(c(1, 1), list(f))
      } else {
        show_power(f$args[[1]], f$args[[2]])
      }
    )
  }
  if (f$kind == 2) {
    parts <- coefficient(f)
    return(quotient(parts[[1]], parts[[2]]))
  }
  Reduce(
    function(a, b) {
      paste0(
        a,
        if (startsWith(b, '-')) {
          paste0(' - ', substring(b, 2))
        } else {
          paste0(' + ', b)
        }
      )
    },
    lapply(f$args, show_form)
  )
}
parse_form <- function(text, names) {
  tokens <- character()
  p <- 1
  while (p <= nchar(text)) {
    tail <- substring(text, p)
    c <- substr(tail, 1, 1)
    if (c == ' ') {
      p <- p + 1
      next
    }
    pattern <- if (grepl('[0-9]', c)) {
      '^[0-9]+'
    } else if (grepl('[a-z]', c)) {
      '^[a-z][a-z0-9]*'
    } else if (grepl('[A-Z]', c)) {
      '^[A-Z][A-Z0-9]*'
    } else {
      ''
    }
    if (pattern != '') {
      t <- regmatches(tail, regexpr(pattern, tail))
    } else if (c %in% c('+', '-', '*', '/', '^', '(', ')')) {
      t <- c
    } else {
      fail(paste0("invalid character '", c, "'"))
    }
    tokens <- c(tokens, t)
    p <- p + nchar(t)
  }
  p <- 1L
  peek <- function() if (p <= length(tokens)) tokens[p] else ''
  unexpected <- function() {
    fail(
      if (p > length(tokens)) {
        'unexpected end of expression'
      } else {
        paste0("unexpected '", peek(), "'")
      }
    )
  }
  accept <- function(s) {
    if (peek() != s) {
      return(FALSE)
    }
    p <<- p + 1L
    TRUE
  }
  expect <- function(s) if (!accept(s)) unexpected()
  atom_tree <- function() {
    t <- peek()
    if (t == '') {
      unexpected()
    }
    if (accept('(')) {
      a <- expression()
      expect(')')
      return(a)
    }
    if (!grepl('^[a-zA-Z0-9]', t)) {
      unexpected()
    }
    p <<- p + 1L
    if (grepl('^[0-9]', t)) {
      return(list(value = num(as.numeric(t))))
    }
    if (grepl('^[A-Z]', t)) {
      if (!exists(t, envir = names, inherits = FALSE)) {
        fail(paste0("undefined name '", t, "'"))
      }
      return(list(value = names[[t]]))
    }
    if (!t %in% functions) {
      return(list(value = node(0, list(), t)))
    }
    expect('(')
    a <- expression()
    expect(')')
    list(op = t, args = list(a))
  }
  unary <- function() {
    if (accept('-')) {
      return(list(op = 'neg', args = list(unary())))
    }
    a <- atom_tree()
    if (accept('^')) list(op = '^', args = list(a, unary())) else a
  }
  term <- function() {
    a <- unary()
    while (peek() %in% c('*', '/')) {
      op <- peek()
      p <<- p + 1L
      a <- list(op = op, args = list(a, unary()))
    }
    a
  }
  expression <- function() {
    a <- term()
    while (peek() %in% c('+', '-')) {
      op <- peek()
      p <<- p + 1L
      a <- list(op = op, args = list(a, term()))
    }
    a
  }
  evaluate <- function(t) {
    if (!is.null(t$value)) {
      return(t$value)
    }
    a <- lapply(t$args, evaluate)
    switch(
      t$op,
      '+' = add(a),
      '-' = add(list(a[[1]], mul(list(minus, a[[2]])))),
      '*' = mul(a),
      '/' = mul(list(a[[1]], power(a[[2]], minus))),
      '^' = power(a[[1]], a[[2]]),
      neg = mul(list(minus, a[[1]])),
      apply_function(t$op, a[[1]])
    )
  }
  t <- expression()
  if (p <= length(tokens)) {
    unexpected()
  }
  evaluate(t)
}
variable <- function(s) grepl('^[a-z][a-z0-9]*$', s) && !s %in% functions
rational_literal <- function(s) grepl('^-?[0-9]+(/[0-9]+)?$', s)
literal <- function(s) {
  if (!rational_literal(s)) {
    fail(paste0("invalid number '", s, "'"))
  }
  a <- as.numeric(strsplit(s, '/', fixed = TRUE)[[1]])
  num(a[1], if (length(a) == 1) 1 else a[2])
}
split_at <- function(s, d) strsplit(paste0(s, d), d, fixed = TRUE)[[1]]
trim <- function(s) gsub('^ +| +$', '', s)
signatures <- c(
  SIMPLIFY = 'e',
  EXPAND = 'e',
  DIFF = 'ev',
  DIFFN = 'evn',
  GRAD = 'e',
  HESSIAN = 'e',
  IMPLICIT = 'evv',
  SUBST = 'eve',
  EVAL = 'ea',
  TANGENT = 'evc',
  LIMIT = 'evc',
  TAYLOR = 'evcn'
)
command <- function(line, names) {
  p <- regexpr(' ', line, fixed = TRUE)[1]
  c <- if (p < 0) line else substr(line, 1, p - 1)
  arg <- if (p < 0) '' else substring(line, p + 1)
  if (c == 'LET') {
    i <- regexpr('=', arg, fixed = TRUE)[1]
    if (i < 0) {
      fail('wrong number of arguments')
    }
    s <- trim(substr(arg, 1, i - 1))
    if (!grepl('^[A-Z][A-Z0-9]*$', s)) {
      fail(paste0("invalid name '", s, "'"))
    }
    f <- parse_form(trim(substring(arg, i + 1)), names)
    names[[s]] <- f
    return(paste0(s, ' = ', show_form(f)))
  }
  if (!c %in% names(signatures)) {
    fail(paste('unknown command', c))
  }
  fields <- if (p < 0) {
    character()
  } else {
    vapply(split_at(arg, ';'), trim, character(1))
  }
  sig <- signatures[[c]]
  if (
    if (c == 'EVAL') {
      !length(fields) %in% c(1, 2)
    } else {
      length(fields) != nchar(sig)
    }
  ) {
    fail('wrong number of arguments')
  }
  a <- list()
  for (i in seq_along(fields)) {
    s <- fields[i]
    kind <- substr(sig, i, i)
    a[[i]] <- switch(
      kind,
      e = parse_form(s, names),
      v = {
        if (!variable(s)) {
          fail(paste0("invalid variable '", s, "'"))
        }
        s
      },
      n = {
        if (!grepl('^[1-8]$', s)) {
          fail(paste0("invalid order '", s, "'"))
        }
        as.integer(s)
      },
      c = literal(s),
      s
    )
  }
  f <- a[[1]]
  v <- if (length(a) >= 2) a[[2]] else ''
  x <- if (length(a) >= 3) a[[3]] else zero
  if (c == 'SIMPLIFY') {
    return(paste0('simplified: ', show_form(f)))
  }
  if (c == 'EXPAND') {
    return(paste0('expanded: ', show_form(expand(f))))
  }
  if (c == 'DIFF') {
    return(paste0('d/d', v, ' = ', show_form(derivative(f, v))))
  }
  if (c == 'DIFFN') {
    out <- character()
    for (k in seq_len(x)) {
      f <- derivative(f, v)
      out <- c(out, paste0('d^', k, '/d', v, '^', k, ' = ', show_form(f)))
    }
    return(out)
  }
  if (c %in% c('GRAD', 'HESSIAN')) {
    vs <- variables(f)
    if (!length(vs)) {
      return('no variables')
    }
    out <- character()
    for (i in seq_along(vs)) {
      d <- derivative(f, vs[i])
      if (c == 'GRAD') {
        out <- c(out, paste0('d/d', vs[i], ' = ', show_form(d)))
      } else {
        for (j in i:length(vs)) {
          out <- c(
            out,
            paste0(
              'd2/d',
              vs[i],
              'd',
              vs[j],
              ' = ',
              show_form(derivative(d, vs[j]))
            )
          )
        }
      }
    }
    return(out)
  }
  if (c == 'IMPLICIT') {
    if (v == x) {
      fail('same variable')
    }
    return(paste0(
      'd',
      x,
      '/d',
      v,
      ' = ',
      show_form(mul(list(
        minus,
        derivative(f, v),
        power(derivative(f, x), minus)
      )))
    ))
  }
  point <- setNames(list(x), v)
  if (c == 'SUBST') {
    return(paste0('substituted: ', show_form(substitute_form(f, point))))
  }
  if (c == 'EVAL') {
    values <- list()
    for (word in strsplit(v, ' ', fixed = TRUE)[[1]]) {
      if (word == '') {
        next
      }
      pair <- strsplit(word, '=', fixed = TRUE)[[1]]
      if (
        length(pair) != 2 || !variable(pair[1]) || !rational_literal(pair[2])
      ) {
        fail(paste0("invalid assignment '", word, "'"))
      }
      q <- literal(pair[2])
      if (!is.null(values[[pair[1]]])) {
        fail(paste('duplicate variable', pair[1]))
      }
      values[[pair[1]]] <- q
    }
    for (s in variables(f)) {
      if (is.null(values[[s]])) fail(paste('no value for', s))
    }
    r <- substitute_form(f, values)
    return(
      if (r$kind == 5) {
        paste0('exact: ', show_form(r))
      } else {
        sprintf('approx: %.6f', numeric_value(r))
      }
    )
  }
  if (c == 'TANGENT') {
    m <- substitute_form(derivative(f, v), point)
    y <- substitute_form(f, point)
    z <- node(0, list(), v)
    t <- paste0(
      'tangent: y = ',
      show_form(add(list(mul(list(m, z)), y, mul(list(num(qneg(x$q)), m)))))
    )
    if (equal(m, zero)) {
      return(c(t, paste0('normal: ', v, ' = ', show_form(x))))
    }
    k <- power(m, minus)
    return(c(
      t,
      paste0(
        'normal: y = ',
        show_form(add(list(mul(list(minus, k, z)), y, mul(list(x, k)))))
      )
    ))
  }
  if (c == 'LIMIT') {
    top <- list()
    bottom <- list()
    for (t in if (f$kind == 2) f$args else list(f)) {
      if (negative(t)) {
        bottom[[length(bottom) + 1]] <- power(
          t$args[[1]],
          num(qneg(t$args[[2]]$q))
        )
      } else {
        top[[length(top) + 1]] <- t
      }
    }
    g <- mul(top)
    h <- mul(bottom)
    for (k in 0:5) {
      u <- substitute_form(g, point)
      b <- substitute_form(h, point)
      if (!equal(b, zero)) {
        return(paste0('limit: ', show_form(mul(list(u, power(b, minus))))))
      }
      if (!equal(u, zero)) {
        return('limit: unbounded')
      }
      if (k < 5) {
        g <- derivative(g, v)
        h <- derivative(h, v)
      }
    }
    return('limit: unknown')
  }
  n <- a[[4]]
  ds <- list(f)
  for (i in seq_len(n)) {
    ds[[length(ds) + 1]] <- derivative(ds[[length(ds)]], v)
  }
  ps <- list()
  fac <- 1
  for (k in 0:n) {
    if (k > 0) {
      fac <- fac * k
    }
    co <- mul(list(substitute_form(ds[[k + 1]], point), num(1, fac)))
    ps[[length(ps) + 1]] <- mul(list(
      co,
      power(add(list(node(0, list(), v), num(qneg(x$q)))), num(k))
    ))
  }
  paste0('taylor: ', show_form(expand(add(ps))))
}
input <- file('stdin', 'r')
count <- as.integer(readLines(input, n = 1))
definitions <- new.env(parent = emptyenv())
for (i in seq_len(count)) {
  line <- readLines(input, n = 1)
  output <- tryCatch(command(line, definitions), error = function(e) {
    paste0('error: ', conditionMessage(e))
  })
  cat(paste0(output, '\n'), sep = '')
}
