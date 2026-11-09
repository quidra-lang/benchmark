num <- function(x) sprintf('%.0f', x)
yes <- function(b) if (b) 'yes' else 'no'
say <- function(...) cat(paste0(...), '\n', sep = '')
mark <- function(m) {
  paste0('(', paste(ifelse(m < 0, 'w', num(m)), collapse = ','), ')')
}
listed <- function(a) if (length(a)) paste(a, collapse = ' ') else 'none'
bad <- function(s) stop(s, call. = FALSE)
number <- function(s, lo, hi) {
  if (!grepl('^(0|[1-9][0-9]{0,9})$', s)) {
    return(NA_real_)
  }
  n <- as.numeric(s)
  if (n >= lo && n <= hi) n else NA_real_
}
visit <- function(adj, start) {
  seen <- rep(FALSE, length(adj))
  queue <- start
  seen[start] <- TRUE
  cursor <- 1L
  while (cursor <= length(queue)) {
    for (v in adj[[queue[cursor]]]) {
      if (!seen[v]) {
        seen[v] <- TRUE
        queue <- c(queue, v)
      }
    }
    cursor <- cursor + 1L
  }
  seen
}
lexless <- function(a, b) {
  i <- which(a != b)
  length(i) > 0 && a[i[1]] < b[i[1]]
}
gcd <- function(a, b) {
  while (b != 0) {
    r <- a %% b
    a <- b
    b <- r
  }
  abs(a)
}
flows <- function(a) {
  n <- nrow(a)
  m <- ncol(a)
  rows <- lapply(seq_len(n), function(i) c(a[i, ], as.numeric(seq_len(n) == i)))
  for (j in seq_len(m)) {
    collected <- Filter(function(r) r[j] == 0, rows)
    for (r in rows) {
      if (r[j] > 0) {
        for (s in rows) {
          if (s[j] < 0) {
            v <- -s[j] * r + r[j] * s
            d <- Reduce(gcd, v, init = 0)
            collected[[length(collected) + 1L]] <- v / d
          }
        }
      }
    }
    keys <- vapply(collected, paste, character(1), collapse = ',')
    unique_rows <- collected[!duplicated(keys)]
    support <- vapply(
      unique_rows,
      function(r) sum(2^(seq_len(n) - 1L)[r[m + seq_len(n)] > 0]),
      numeric(1)
    )
    rows <- unique_rows[vapply(
      seq_along(unique_rows),
      function(i) {
        !any(support != support[i] & bitwAnd(support, support[i]) == support)
      },
      logical(1)
    )]
  }
  result <- lapply(rows, function(r) r[m + seq_len(n)])
  if (length(result) > 1L) {
    order <- do.call(
      order,
      c(
        lapply(seq_len(n), function(i) -vapply(result, `[`, numeric(1), i)),
        list(method = 'radix')
      )
    )
    result <- result[order]
  }
  result
}
new_net <- function(name) {
  n <- new.env(parent = emptyenv())
  n$name <- name
  n$p <- n$t <- character()
  n$initial <- n$cap <- n$priority <- numeric()
  n$pre <- n$post <- n$inh <- matrix(0, 16, 16)
  n$arcs <- n$inhibitors <- 0L
  n$current <- numeric()
  n$history <- list()
  n
}
define <- function(n, w) {
  cmd <- w[1]
  count <- length(w) - 1L
  if (!cmd %in% c('place', 'transition', 'arc', 'inhibit')) {
    bad(paste('unknown definition', cmd))
  }
  if (
    !(if (cmd == 'place') {
      count %in% 2:3
    } else if (cmd == 'transition') {
      count %in% 1:2
    } else {
      count == 3
    })
  ) {
    bad('wrong number of arguments')
  }
  a <- w[2]
  if (cmd %in% c('place', 'transition')) {
    if (a %in% c(n$p, n$t)) {
      bad(paste('duplicate name', a))
    }
    if (cmd == 'place') {
      if (count == 3 && as.numeric(w[3]) > as.numeric(w[4])) {
        bad(paste('tokens exceed capacity of', a))
      }
      n$p <- c(n$p, a)
      n$initial <- c(n$initial, as.numeric(w[3]))
      n$cap <- c(n$cap, if (count == 3) as.numeric(w[4]) else 0)
    } else {
      n$t <- c(n$t, a)
      n$priority <- c(n$priority, if (count == 2) as.numeric(w[3]) else 0)
    }
  } else if (cmd == 'arc') {
    b <- w[3]
    for (x in c(a, b)) {
      if (!x %in% c(n$p, n$t)) bad(paste('unknown node', x))
    }
    pa <- match(a, n$p)
    pb <- match(b, n$p)
    if (is.na(pa) == is.na(pb)) {
      bad('arc must connect a place and a transition')
    }
    p <- if (!is.na(pa)) pa else pb
    t <- match(if (!is.na(pa)) b else a, n$t)
    field <- if (!is.na(pa)) 'pre' else 'post'
    if (n[[field]][p, t] > 0) {
      bad(paste('duplicate arc', a, b))
    }
    n[[field]][p, t] <- as.numeric(w[4])
    n$arcs <- n$arcs + 1L
  } else {
    p <- match(a, n$p)
    t <- match(w[3], n$t)
    if (is.na(p)) {
      bad(paste('unknown place', a))
    }
    if (is.na(t)) {
      bad(paste('unknown transition', w[3]))
    }
    if (n$inh[p, t] > 0) {
      bad(paste('duplicate inhibitor', a, w[3]))
    }
    n$inh[p, t] <- as.numeric(w[4])
    n$inhibitors <- n$inhibitors + 1L
  }
}
reason <- function(n, m, t) {
  for (p in seq_along(n$p)) {
    if (m[p] >= 0 && m[p] < n$pre[p, t]) {
      return(paste('insufficient tokens in', n$p[p]))
    }
  }
  for (p in seq_along(n$p)) {
    if (n$inh[p, t] > 0 && (m[p] < 0 || m[p] >= n$inh[p, t])) {
      return(paste('inhibited by', n$p[p]))
    }
  }
  for (p in seq_along(n$p)) {
    if (
      n$cap[p] > 0 && (m[p] < 0 || m[p] - n$pre[p, t] + n$post[p, t] > n$cap[p])
    ) {
      return(paste('capacity of', n$p[p], 'exceeded'))
    }
  }
  ''
}
enabled <- function(n, m) {
  which(vapply(seq_along(n$t), function(t) reason(n, m, t) == '', logical(1)))
}
fire <- function(n, m, t) {
  ifelse(m < 0, -1, m - n$pre[seq_along(n$p), t] + n$post[seq_along(n$p), t])
}
commit <- function(n, t) {
  n$history[[length(n$history) + 1L]] <- n$current
  n$current <- fire(n, n$current, t)
}
key <- function(m) paste(m, collapse = ',')
graph <- function(n, start, limit, target = NULL) {
  states <- list(start)
  parent <- via <- 0L
  edges <- list(list())
  index <- new.env(hash = TRUE, parent = emptyenv())
  index[[key(start)]] <- 1L
  matches <- function(m) {
    !is.null(target) &&
      all(m >= target[, 1] & (target[, 2] < 0 | m == target[, 2]))
  }
  result <- function(found = 0L, aborted = FALSE) {
    list(
      states = states,
      parent = parent,
      via = via,
      edges = edges,
      found = found,
      aborted = aborted
    )
  }
  if (matches(start)) {
    return(result(1L))
  }
  q <- 1L
  while (q <= length(states)) {
    for (t in enabled(n, states[[q]])) {
      m <- fire(n, states[[q]], t)
      k <- index[[key(m)]]
      if (is.null(k)) {
        if (length(states) == limit) {
          return(result(aborted = TRUE))
        }
        k <- length(states) + 1L
        index[[key(m)]] <- k
        states[[k]] <- m
        parent[k] <- q
        via[k] <- t
        edges[[k]] <- list()
        if (matches(m)) return(result(k))
      }
      edges[[q]][[length(edges[[q]]) + 1L]] <- c(t, k)
    }
    q <- q + 1L
  }
  result()
}
path <- function(g, k) {
  a <- integer()
  while (g$parent[k] > 0) {
    a <- c(g$via[k], a)
    k <- g$parent[k]
  }
  a
}
reach <- function(n, limit, display) {
  g <- graph(n, n$current, limit)
  if (g$aborted) {
    say('reachability graph limit ', limit, ' exceeded')
    return()
  }
  N <- length(g$states)
  if (display) {
    for (i in seq_len(N)) {
      a <- vapply(
        g$edges[[i]],
        function(e) paste0(n$t[e[1]], '->M', e[2] - 1L),
        character(1)
      )
      say(
        'M',
        i - 1L,
        ' ',
        mark(g$states[[i]]),
        ': ',
        if (length(a)) paste(a, collapse = ' ') else 'dead'
      )
    }
    return()
  }
  adj <- lapply(g$edges, function(e) vapply(e, `[`, numeric(1), 2))
  closure <- lapply(seq_len(N), function(i) visit(adj, i))
  comp <- integer(N)
  components <- 0L
  for (i in seq_len(N)) {
    if (comp[i] == 0) {
      components <- components + 1L
      for (j in i:N) {
        if (closure[[i]][j] && closure[[j]][i]) comp[j] <- components
      }
    }
  }
  terminal <- rep(TRUE, components)
  home <- rep(TRUE, N)
  maximum <- numeric(length(n$p))
  dead <- integer()
  edges <- 0L
  persistent <- TRUE
  for (i in seq_len(N)) {
    if (!length(g$edges[[i]])) {
      dead <- c(dead, i)
    }
    edges <- edges + length(g$edges[[i]])
    maximum <- pmax(maximum, g$states[[i]])
    home <- home & closure[[i]]
    for (e in g$edges[[i]]) {
      if (comp[i] != comp[e[2]]) {
        terminal[comp[i]] <- FALSE
      }
      for (u in g$edges[[i]]) {
        if (e[1] != u[1] && reason(n, g$states[[e[2]]], u[1]) != '') {
          persistent <- FALSE
        }
      }
    }
  }
  say('reachable markings: ', N)
  say('edges: ', edges)
  say('components: ', components, ' (terminal ', sum(terminal), ')')
  say('dead markings: ', length(dead))
  for (i in dead) {
    a <- n$t[path(g, i)]
    say(
      '  M',
      i - 1L,
      ' ',
      mark(g$states[[i]]),
      ' path ',
      if (length(a)) paste(a, collapse = ' ') else 'empty'
    )
  }
  bound <- max(maximum)
  say('max tokens: ', mark(maximum))
  say('bound: ', num(bound))
  say('safe: ', yes(bound <= 1))
  say('home markings: ', sum(home))
  say('reversible: ', yes(home[1]))
  say('persistent: ', yes(persistent))
  levels <- character()
  for (t in seq_along(n$t)) {
    present <- rep(FALSE, components)
    used <- cycle <- FALSE
    for (i in seq_len(N)) {
      for (e in g$edges[[i]]) {
        if (e[1] == t) {
          used <- TRUE
          present[comp[i]] <- TRUE
          if (comp[i] == comp[e[2]]) cycle <- TRUE
        }
      }
    }
    level <- if (all(!terminal | present)) {
      'L4'
    } else if (cycle) {
      'L3'
    } else if (used) {
      'L1'
    } else {
      'L0'
    }
    levels <- c(levels, paste0(n$t[t], '=', level))
  }
  say('liveness: ', paste(levels, collapse = ' '))
}
cover <- function(n, limit) {
  states <- list(n$current)
  parent <- via <- 0L
  old <- dead <- FALSE
  rank <- function(v) ifelse(v < 0, Inf, v)
  q <- 1L
  while (q <= length(states)) {
    if (!old[q]) {
      es <- enabled(n, states[[q]])
      dead[q] <- !length(es)
      ancestors <- integer()
      a <- q
      while (a > 0) {
        ancestors <- c(a, ancestors)
        a <- parent[a]
      }
      for (t in es) {
        m <- fire(n, states[[q]], t)
        for (a in ancestors) {
          if (
            all(rank(m) >= rank(states[[a]])) &&
              any(rank(m) > rank(states[[a]]))
          ) {
            m[n$cap == 0 & rank(m) > rank(states[[a]])] <- -1
          }
        }
        if (length(states) == limit) {
          say('coverability tree limit ', limit, ' exceeded')
          return()
        }
        old <- c(old, any(vapply(states, identical, logical(1), m)))
        states[[length(states) + 1L]] <- m
        parent <- c(parent, q)
        via <- c(via, t)
        dead <- c(dead, FALSE)
      }
    }
    q <- q + 1L
  }
  say('coverability tree nodes: ', length(states))
  maximum <- numeric(length(n$p))
  for (i in seq_along(states)) {
    say(
      '  ',
      i - 1L,
      ' ',
      mark(states[[i]]),
      ' ',
      if (i == 1) 'root' else paste('<-', parent[i] - 1L, n$t[via[i]]),
      if (old[i]) ' old' else '',
      if (dead[i]) ' dead' else ''
    )
    mask <- rank(states[[i]]) > rank(maximum)
    maximum[mask] <- states[[i]][mask]
  }
  say('bounds: ', mark(maximum))
  say('unbounded: ', listed(n$p[maximum < 0]))
}
bits <- function(n, mask) {
  which(bitwAnd(mask, bitwShiftL(1L, seq_along(n$p) - 1L)) != 0)
}
sets <- function(n, trap) {
  found <- integer()
  for (mask in seq_len(2^length(n$p) - 1L)) {
    ps <- bits(n, mask)
    valid <- TRUE
    for (t in seq_along(n$t)) {
      input <- any(n$post[ps, t] > 0)
      output <- any(n$pre[ps, t] > 0)
      if (if (trap) output && !input else input && !output) {
        valid <- FALSE
        break
      }
    }
    if (valid) found <- c(found, mask)
  }
  result <- found[vapply(
    found,
    function(m) !any(found != m & bitwAnd(found, m) == found),
    logical(1)
  )]
  if (length(result) > 1L) {
    for (i in 2:length(result)) {
      j <- i
      while (j > 1L) {
        a <- bits(n, result[j])
        b <- bits(n, result[j - 1L])
        smaller <- if (length(a) != length(b)) {
          length(a) < length(b)
        } else {
          lexless(a, b)
        }
        if (!smaller) {
          break
        }
        result[c(j - 1L, j)] <- result[c(j, j - 1L)]
        j <- j - 1L
      }
    }
  }
  result
}
set_text <- function(n, mask) {
  paste0('{', paste(n$p[bits(n, mask)], collapse = ','), '}')
}
realize <- function(n, counts) {
  used <- numeric(length(counts))
  stack <- list(n$current)
  choices <- 1L
  result <- integer()
  seen <- new.env(hash = TRUE, parent = emptyenv())
  total <- sum(counts)
  while (length(stack)) {
    d <- length(result) + 1L
    if (length(result) == total) {
      return(result)
    }
    chosen <- 0L
    if (choices[d] <= length(counts)) {
      for (t in choices[d]:length(counts)) {
        choices[d] <- t + 1L
        if (used[t] >= counts[t] || reason(n, stack[[d]], t) != '') {
          next
        }
        used[t] <- used[t] + 1
        k <- key(used)
        used[t] <- used[t] - 1
        if (!is.null(seen[[k]])) {
          next
        }
        seen[[k]] <- TRUE
        chosen <- t
        break
      }
    }
    if (chosen > 0) {
      used[chosen] <- used[chosen] + 1
      result <- c(result, chosen)
      stack[[length(stack) + 1L]] <- fire(n, stack[[d]], chosen)
      choices <- c(choices, 1L)
    } else {
      stack <- head(stack, -1L)
      choices <- head(choices, -1L)
      if (length(result)) {
        t <- tail(result, 1L)
        used[t] <- used[t] - 1
        result <- head(result, -1L)
      }
    }
  }
  NULL
}
invariants <- function(n, transpose) {
  a <- n$post[seq_along(n$p), seq_along(n$t), drop = FALSE] -
    n$pre[seq_along(n$p), seq_along(n$t), drop = FALSE]
  if (transpose) {
    a <- t(a)
  }
  f <- flows(a)
  ns <- if (transpose) n$t else n$p
  covered <- rep(FALSE, length(ns))
  bounds <- rep(-1, length(ns))
  say(if (transpose) 'T' else 'P', '-semiflows: ', length(f))
  for (c in f) {
    terms <- paste(
      paste0(ifelse(c[c > 0] == 1, '', paste0(num(c[c > 0]), '*')), ns[c > 0]),
      collapse = ' + '
    )
    covered <- covered | c > 0
    if (transpose) {
      sequence <- realize(n, c)
      say(
        '  ',
        terms,
        ': ',
        if (is.null(sequence)) {
          'not realizable'
        } else {
          paste0('realizable ', paste(n$t[sequence], collapse = ' '))
        }
      )
    } else {
      value <- sum(c * n$current)
      say('  ', terms, ' = ', num(value))
      for (p in which(c > 0)) {
        bounds[p] <- if (bounds[p] < 0) {
          floor(value / c[p])
        } else {
          min(bounds[p], floor(value / c[p]))
        }
      }
    }
  }
  if (!transpose) {
    say(
      'bounds: (',
      paste(ifelse(bounds < 0, '-', num(bounds)), collapse = ','),
      ')'
    )
  }
  say(if (transpose) 'consistent: ' else 'conservative: ', yes(all(covered)))
}
classify <- function(n) {
  P <- length(n$p)
  T <- length(n$t)
  inputs <- lapply(seq_len(T), function(t) which(n$pre[seq_len(P), t] > 0))
  outputs <- lapply(seq_len(P), function(p) which(n$pre[p, seq_len(T)] > 0))
  ordinary <- all(n$pre <= 1 & n$post <= 1)
  pure <- !any(n$pre > 0 & n$post > 0)
  sm <- ordinary &&
    all(vapply(
      seq_len(T),
      function(t) {
        length(inputs[[t]]) == 1L && sum(n$post[seq_len(P), t] > 0) == 1
      },
      logical(1)
    ))
  mg <- ordinary &&
    all(vapply(
      seq_len(P),
      function(p) {
        length(outputs[[p]]) == 1L && sum(n$post[p, seq_len(T)] > 0) == 1
      },
      logical(1)
    ))
  fc <- ordinary
  efc <- ordinary
  for (p in seq_len(P)) {
    for (t in outputs[[p]]) {
      if (length(outputs[[p]]) != 1L && length(inputs[[t]]) != 1L) fc <- FALSE
    }
    for (q in seq_len(P)) {
      if (
        length(intersect(outputs[[p]], outputs[[q]])) &&
          !identical(outputs[[p]], outputs[[q]])
      ) {
        efc <- FALSE
      }
    }
  }
  labels <- c(
    'ordinary',
    'pure',
    'state machine',
    'marked graph',
    'free choice',
    'extended free choice'
  )
  values <- c(ordinary, pure, sm, mg, fc, efc)
  for (i in seq_along(labels)) {
    say(labels[i], ': ', yes(values[i]))
  }
  verdict <- if (!fc) {
    'not applicable'
  } else if (P > 12) {
    'too many places'
  } else {
    'holds'
  }
  if (fc && P <= 12) {
    traps <- sets(n, TRUE)
    for (s in sets(n, FALSE)) {
      if (
        !any(vapply(
          traps,
          function(q) bitwAnd(s, q) == q && any(n$current[bits(n, q)] > 0),
          logical(1)
        ))
      ) {
        verdict <- paste('fails at', set_text(n, s))
        break
      }
    }
  }
  say('commoner: ', verdict)
}
workflow <- function(n, limit) {
  P <- length(n$p)
  T <- length(n$t)
  sources <- which(rowSums(n$post[seq_len(P), seq_len(T), drop = FALSE]) == 0)
  sinks <- which(rowSums(n$pre[seq_len(P), seq_len(T), drop = FALSE]) == 0)
  if (length(sources) != 1) {
    say('workflow: no (', length(sources), ' source places)')
    return()
  }
  if (length(sinks) != 1) {
    say('workflow: no (', length(sinks), ' sink places)')
    return()
  }
  i <- sources[1]
  o <- sinks[1]
  ns <- c(n$p, n$t)
  adj <- rev <- rep(list(integer()), P + T)
  for (p in seq_len(P)) {
    for (t in seq_len(T)) {
      if (n$pre[p, t] > 0) {
        adj[[p]] <- c(adj[[p]], P + t)
        rev[[P + t]] <- c(rev[[P + t]], p)
      }
      if (n$post[p, t] > 0) {
        adj[[P + t]] <- c(adj[[P + t]], p)
        rev[[p]] <- c(rev[[p]], P + t)
      }
    }
  }
  f <- visit(adj, i)
  b <- visit(rev, o)
  for (v in seq_along(ns)) {
    if (!f[v] || !b[v]) {
      say(
        'workflow: no (',
        ns[v],
        ' is not on a path from ',
        n$p[i],
        ' to ',
        n$p[o],
        ')'
      )
      return()
    }
  }
  say('workflow: source ', n$p[i], ' sink ', n$p[o])
  start <- goal <- numeric(P)
  start[i] <- goal[o] <- 1
  g <- graph(n, start, limit)
  if (g$aborted) {
    say('reachability graph limit ', limit, ' exceeded')
    return()
  }
  finish <- which(vapply(g$states, identical, logical(1), goal))
  rev <- rep(list(integer()), length(g$states))
  used <- rep(FALSE, T)
  for (u in seq_along(g$states)) {
    for (e in g$edges[[u]]) {
      rev[[e[2]]] <- c(rev[[e[2]]], u)
      used[e[1]] <- TRUE
    }
  }
  option <- length(finish) > 0 && all(visit(rev, finish[1]))
  proper <- all(vapply(
    g$states,
    function(m) m[o] < 1 || identical(m, goal),
    logical(1)
  ))
  live <- all(used)
  say('option to complete: ', yes(option))
  say('proper completion: ', yes(proper))
  say('no dead transitions: ', yes(live))
  say('sound: ', yes(option && proper && live))
}
arity <- c(
  MARKING = 0,
  RESET = 0,
  SET = 2,
  ENABLED = 0,
  FIRE = -1,
  UNDO = 1,
  SIMULATE = 3,
  CONFLICTS = 0,
  REACH = 1,
  GRAPH = 1,
  COVER = 1,
  PATH = 2,
  INCIDENCE = 0,
  PINV = 0,
  TINV = 0,
  SIPHONS = 0,
  TRAPS = 0,
  CLASSIFY = 0,
  WORKFLOW = 1,
  SHOW = 0
)
execute <- function(n, w) {
  cmd <- w[1]
  if (!cmd %in% names(arity)) {
    bad(paste('unknown command', cmd))
  }
  if (if (arity[cmd] < 0) length(w) < 2 else length(w) != arity[cmd] + 1) {
    bad('wrong number of arguments')
  }
  limit <- 0
  if (cmd %in% c('REACH', 'GRAPH', 'COVER', 'PATH', 'WORKFLOW')) {
    limit <- number(w[2], 1, 2000)
    if (is.na(limit)) bad(paste('invalid limit', w[2]))
  }
  switch(
    cmd,
    MARKING = say('marking ', mark(n$current)),
    RESET = {
      n$current <- n$initial
      n$history <- list()
      say('marking ', mark(n$current))
    },
    SET = {
      p <- match(w[2], n$p)
      if (is.na(p)) {
        bad(paste('unknown place', w[2]))
      }
      v <- number(w[3], 0, 999)
      if (is.na(v)) {
        bad(paste('invalid tokens', w[3]))
      }
      if (n$cap[p] > 0 && v > n$cap[p]) {
        bad(paste('tokens exceed capacity of', w[2]))
      }
      n$current[p] <- v
      n$history <- list()
      say('marking ', mark(n$current))
    },
    ENABLED = say('enabled: ', listed(n$t[enabled(n, n$current)])),
    FIRE = {
      ts <- integer()
      for (s in w[-1]) {
        t <- match(s, n$t)
        if (is.na(t)) {
          bad(paste('unknown transition', s))
        }
        ts <- c(ts, t)
      }
      for (i in seq_along(ts)) {
        r <- reason(n, n$current, ts[i])
        if (r != '') {
          say(
            'step ',
            i,
            ': ',
            n$t[ts[i]],
            ' not enabled (',
            r,
            ') at ',
            mark(n$current)
          )
          return()
        }
        commit(n, ts[i])
      }
      say('fired ', length(ts), ' -> ', mark(n$current))
    },
    UNDO = {
      k <- number(w[2], 1, 1000)
      if (is.na(k)) {
        bad(paste('invalid count', w[2]))
      }
      h <- length(n$history)
      if (k > h) {
        bad(paste0('cannot undo ', num(k), ': history size ', h))
      }
      n$current <- n$history[[h - k + 1]]
      n$history <- head(n$history, h - k)
      say('marking ', mark(n$current))
    },
    SIMULATE = {
      steps <- number(w[2], 1, 1000)
      x <- number(w[3], 1, 2147483646)
      if (is.na(steps)) {
        bad(paste('invalid steps', w[2]))
      }
      if (is.na(x)) {
        bad(paste('invalid seed', w[3]))
      }
      if (!w[4] %in% c('PRIORITY', 'RANDOM')) {
        bad(paste('invalid mode', w[4]))
      }
      counts <- integer(length(n$t))
      done <- 0L
      while (done < steps) {
        es <- enabled(n, n$current)
        if (!length(es)) {
          say('dead (steps=', done, ')')
          break
        }
        if (w[4] == 'RANDOM') {
          x <- (x * 48271) %% 2147483647
          t <- es[x %% length(es) + 1]
        } else {
          t <- es[which.max(n$priority[es])]
        }
        commit(n, t)
        counts[t] <- counts[t] + 1L
        done <- done + 1L
        say('step ', done, ': ', n$t[t], ' -> ', mark(n$current))
      }
      if (done == steps) {
        say('completed (steps=', num(steps), ')')
      }
      say('counts: ', paste(paste0(n$t, '=', counts), collapse = ' '))
    },
    CONFLICTS = {
      s <- e <- character()
      for (u in seq_along(n$t)) {
        if (u < length(n$t)) {
          for (v in (u + 1L):length(n$t)) {
            pair <- paste0(n$t[u], '/', n$t[v])
            if (any(n$pre[, u] > 0 & n$pre[, v] > 0)) {
              s <- c(s, pair)
            }
            if (
              reason(n, n$current, u) == '' &&
                reason(n, n$current, v) == '' &&
                (reason(n, fire(n, n$current, u), v) != '' ||
                  reason(n, fire(n, n$current, v), u) != '')
            ) {
              e <- c(e, pair)
            }
          }
        }
      }
      say('structural: ', listed(s))
      say('effective: ', listed(e))
    },
    REACH = reach(n, limit, FALSE),
    GRAPH = reach(n, limit, TRUE),
    COVER = cover(n, limit),
    PATH = {
      entries <- strsplit(w[3], ',', fixed = TRUE)[[1]]
      if (length(entries) != length(n$p)) {
        bad(paste('target needs', length(n$p), 'entries'))
      }
      target <- matrix(0, length(entries), 2)
      for (p in seq_along(entries)) {
        s <- entries[p]
        if (s == '*') {
          target[p, ] <- c(0, -1)
          next
        }
        plus <- endsWith(s, '+')
        v <- number(if (plus) substr(s, 1, nchar(s) - 1) else s, 0, 9999999999)
        if (is.na(v)) {
          bad(paste('invalid target entry', s))
        }
        target[p, ] <- c(v, if (plus) -1 else v)
      }
      g <- graph(n, n$current, limit, target)
      if (g$found > 0) {
        a <- n$t[path(g, g$found)]
        say(
          'reached ',
          mark(g$states[[g$found]]),
          ' length=',
          length(a),
          if (length(a)) paste0(': ', paste(a, collapse = ' ')) else ''
        )
      } else if (g$aborted) {
        say('search limit ', num(limit), ' exceeded')
      } else {
        say('unreachable (markings explored: ', length(g$states), ')')
      }
    },
    INCIDENCE = {
      rows <- c(
        list(c('', n$t)),
        lapply(seq_along(n$p), function(p) {
          c(n$p[p], num(n$post[p, seq_along(n$t)] - n$pre[p, seq_along(n$t)]))
        })
      )
      width <- vapply(
        seq_along(rows[[1]]),
        function(i) max(vapply(rows, function(r) nchar(r[i]), integer(1))),
        integer(1)
      )
      for (r in rows) {
        say(sub(
          ' +$',
          '',
          paste(
            vapply(
              seq_along(r),
              function(i) {
                format(
                  r[i],
                  width = width[i],
                  justify = if (i == 1) 'left' else 'right'
                )
              },
              character(1)
            ),
            collapse = '  '
          )
        ))
      }
    },
    PINV = invariants(n, FALSE),
    TINV = invariants(n, TRUE),
    SIPHONS = ,
    TRAPS = {
      if (length(n$p) > 12) {
        bad('more than 12 places')
      }
      ss <- sets(n, cmd == 'TRAPS')
      say(
        'minimal ',
        if (cmd == 'TRAPS') 'traps' else 'siphons',
        ': ',
        length(ss)
      )
      for (s in ss) {
        say('  ', set_text(n, s), ' tokens=', num(sum(n$current[bits(n, s)])))
      }
    },
    CLASSIFY = classify(n),
    WORKFLOW = workflow(n, limit),
    SHOW = {
      for (p in seq_along(n$p)) {
        say(
          'place ',
          n$p[p],
          ' tokens=',
          num(n$initial[p]),
          ' capacity=',
          if (n$cap[p] == 0) 'none' else num(n$cap[p])
        )
      }
      for (t in seq_along(n$t)) {
        listing <- function(mat) {
          ps <- which(mat[seq_along(n$p), t] > 0)
          if (length(ps)) {
            paste(paste0(n$p[ps], ':', num(mat[ps, t])), collapse = ',')
          } else {
            '-'
          }
        }
        say(
          'transition ',
          n$t[t],
          ' priority=',
          num(n$priority[t]),
          ' pre=',
          listing(n$pre),
          ' post=',
          listing(n$post),
          ' inhibit=',
          listing(n$inh)
        )
      }
    }
  )
}
input <- file('stdin', open = 'r')
read_line <- function() readLines(input, n = 1, warn = FALSE)
blocks <- as.integer(read_line())
for (b in seq_len(blocks)) {
  n <- new_net(strsplit(read_line(), ' ', fixed = TRUE)[[1]][2])
  repeat {
    line <- read_line()
    if (line == 'END NET') {
      break
    }
    tryCatch(
      define(n, strsplit(line, ' ', fixed = TRUE)[[1]]),
      error = function(e) say('error: ', conditionMessage(e))
    )
  }
  n$current <- n$initial
  say(
    'net ',
    n$name,
    ': places=',
    length(n$p),
    ' transitions=',
    length(n$t),
    ' arcs=',
    n$arcs,
    ' inhibitors=',
    n$inhibitors
  )
  commands <- as.integer(read_line())
  for (i in seq_len(commands)) {
    tryCatch(
      execute(n, strsplit(read_line(), ' ', fixed = TRUE)[[1]]),
      error = function(e) say('error: ', conditionMessage(e))
    )
  }
}
