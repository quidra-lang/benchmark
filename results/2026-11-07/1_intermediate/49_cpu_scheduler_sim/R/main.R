options(scipen = 999)
algorithms <- c("FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ")
keys <- c("cs", "q", "k", "s", "seed")
registry <- list()

emit <- function(...) cat(paste(..., collapse = " "), "\n", sep = "")

fail <- function(s) stop(structure(list(message = s, call = NULL), class = c("command_error", "error", "condition")))

ratio <- function(u, v) {
  n <- floor(100 * u / v)
  sprintf("%.0f.%02.0f", n %/% 100, n %% 100)
}

allowed <- function(a, k) k == "cs" || (k == "q" && a %in% c("RR", "LOTTERY")) || (k == "seed" && a == "LOTTERY") || (k == "k" && a == "PRIORITY") || (k == "s" && a == "MLFQ")

valid <- function(k, v) switch(k, cs = v <= 5, q = v >= 1 && v <= 20, k = v >= 1 && v <= 50, s = v <= 500, seed = v >= 1 && v <= 2147483646, FALSE)

notation <- function(a, p, full = FALSE) paste(vapply(keys[full|vapply(keys, function(k) allowed(a, k), logical(1))], function(k) paste0(k, "=", p[[k]]), character(1)), collapse = " ")

mutable <- function(...) list2env(list(...), parent = emptyenv())

listline <- function(p) {
  b <- paste0(rep(c("C", "I"), length.out = length(p$bursts)), p$bursts)
  paste(p$id, paste0("arrival=", p$arrival), paste0("priority=", p$priority), paste0("deadline=", if (p$deadline == 0) "none" else p$deadline), paste0("bursts=", paste(b, collapse = ",")))
}

simulate <- function(p, a, param) {
  n <- length(p)
  states <- lapply(p, function(x) mutable(state = "FUTURE", burst = 1L, left = x$bursts[1], effective = x$priority, wait = 0, level = 0L, used = 0, enqueued = 0, start = -1, finish = -1, slices = 0))
  bursts <- lapply(p, function(x) lapply(seq_len((length(x$bursts) + 1L) %/% 2L), function(j) mutable(ready = 0, start = -1, finish = 0, slices = 0)))
  queues <- list(integer(), integer(), integer())
  cpu <- previous <- 0L
  mode <- sw <- run <- switches <- busy <- switching <- idle <- qmax <- qsum <- 0
  x <- param$seed
  labels <- events <- character()
  shots <- list()
  t <- 0
  deadline <- function(i) if (p[[i]]$deadline == 0) 2^52 else p[[i]]$arrival + p[[i]]$deadline
  log <- function(s) events <<- c(events, paste(t, s))
  enqueue <- function(i) {
    z <- states[[i]]
    z$state <- "READY"
    z$enqueued <- t
    l <- if (a == "MLFQ") z$level + 1L else 1L
    queues[[l]] <<- c(queues[[l]], i)
  }
  start <- function(i) {
    cpu <<- i
    mode <<- 2
    run <<- 0
    z <- states[[i]]
    z$state <- "RUN"
    if (z$start<0) z$start <- t
    b <- bursts[[i]][[(z$burst + 1L) %/% 2L]]
    if (b$start<0) b$start <- t
  }
  snapshot <- function() list(states = lapply(states, as.list), queues = lapply(queues, identity), cpu = cpu, mode = mode)
  repeat {
    if (a == "PRIORITY") for (i in queues[[1]]) {
      z <- states[[i]]
      z$wait <- z$wait + 1
      if (z$wait == param$k) {
        z$wait <- 0
        if (z$effective>0) {
          z$effective <- z$effective - 1
          log(paste("AGE", p[[i]]$id, z$effective))
        }
      }
    }
    for (i in seq_len(n)) {
      z <- states[[i]]
      if (z$state == "IO" && z$left == 0) {
        z$burst <- z$burst + 1L
        z$left <- p[[i]]$bursts[z$burst]
        bursts[[i]][[(z$burst + 1L) %/% 2L]]$ready <- t
        enqueue(i)
        log(paste("IODONE", p[[i]]$id))
      }
    }
    for (i in seq_len(n)) if (states[[i]]$state == "FUTURE" && p[[i]]$arrival == t) {
      bursts[[i]][[1]]$ready <- t
      enqueue(i)
      log(paste("ARRIVE", p[[i]]$id))
    }
    if (mode == 1 && sw == 0) {
      start(cpu)
      log(paste("START", p[[cpu]]$id))
    } else if (mode == 2) {
      i <- cpu
      z <- states[[i]]
      if (z$left == 0 && z$burst == length(p[[i]]$bursts)) {
        z$state <- "DONE"
        z$finish <- t
        log(paste("DONE", p[[i]]$id))
        mode <- 0
        cpu <- 0L
      } else {
        demoted <- FALSE
        if (a == "MLFQ" && z$level<2 && z$used == c(4, 8)[z$level + 1L]) {
          z$level <- z$level + 1L
          z$used <- 0
          demoted <- TRUE
          log(paste("DEMOTE", p[[i]]$id, z$level))
        }
        preempt <- FALSE
        for (l in seq_len(3L)) for (j in queues[[l]]) {
          u <- states[[j]]
          if ((a == "SRTF" && u$left<z$left) || (a == "PRIORITY" && u$effective<z$effective) || (a == "EDF" && deadline(j)<deadline(i)) || (a == "MLFQ" && l - 1L<z$level)) preempt <- TRUE
        }
        if (z$left == 0) {
          z$burst <- z$burst + 1L
          z$left <- p[[i]]$bursts[z$burst]
          z$state <- "IO"
          log(paste("IO", p[[i]]$id, z$left))
          mode <- 0
          cpu <- 0L
        } else if (demoted) {
          enqueue(i)
          mode <- 0
          cpu <- 0L
        } else if (a %in% c("RR", "LOTTERY") && run == param$q) {
          enqueue(i)
          log(paste("EXPIRE", p[[i]]$id))
          mode <- 0
          cpu <- 0L
        } else if (preempt) {
          enqueue(i)
          log(paste("PREEMPT", p[[i]]$id))
          mode <- 0
          cpu <- 0L
        }
      }
    }
    if (all(vapply(states, function(z) z$state == "DONE", logical(1)))) {
      shots[[length(shots) + 1L]] <- snapshot()
      break
    }
    if (a == "MLFQ" && param$s>0 && t>0 && t %% param$s == 0) {
      queues[[1]] <- unlist(queues, use.names = FALSE)
      queues[[2]] <- queues[[3]] <- integer()
      for (z in states) {
        z$level <- 0L
        z$used <- 0
      }
      log("BOOST")
    }
    if (mode == 0) {
      nonempty <- which(lengths(queues)>0)
      if (length(nonempty)) {
        l <- nonempty[1]
        q <- queues[[l]]
        selected <- 1L
        if (a == "LOTTERY") {
          total <- sum(vapply(q, function(i) 10 - p[[i]]$priority, numeric(1)))
          x <- (48271 * x) %% 2147483647
          draw <- x %% total
          count <- 0
          for (j in seq_along(q)) {
            count <- count + 10 - p[[q[j]]]$priority
            if (count>draw) {
              selected <- j
              break
            }
          }
        } else if (length(q)>1L) for (j in 2:length(q)) {
          i <- q[j]
          b <- q[selected]
          u <- states[[i]]
          v <- states[[b]]
          better <- switch(a, SJF = u$left<v$left, SRTF = u$left<v$left, PRIORITY = u$effective<v$effective, EDF = deadline(i)<deadline(b), HRRN = (t - u$enqueued + u$left) * v$left>(t - v$enqueued + v$left) * u$left, FALSE)
          if (better) selected <- j
        }
        i <- q[selected]
        queues[[l]] <- q[-selected]
        z <- states[[i]]
        z$effective <- p[[i]]$priority
        z$wait <- 0
        z$slices <- z$slices + 1
        b <- bursts[[i]][[(z$burst + 1L) %/% 2L]]
        b$slices <- b$slices + 1
        change <- i != previous
        if (change) switches <- switches + 1
        if (change && param$cs>0) {
          cpu <- i
          mode <- 1
          sw <- param$cs
          z$state <- "SWITCH"
          log(paste("SWITCH", p[[i]]$id))
        } else {
          start(i)
          log(paste("DISPATCH", p[[i]]$id))
        }
      }
    }
    shots[[length(shots) + 1L]] <- snapshot()
    qlen <- sum(lengths(queues))
    qmax <- max(qmax, qlen)
    qsum <- qsum + qlen
    label <- "IDLE"
    if (mode == 2) {
      z <- states[[cpu]]
      z$left <- z$left - 1
      z$used <- z$used + 1
      run <- run + 1
      previous <- cpu
      label <- p[[cpu]]$id
      busy <- busy + 1
      if (z$left == 0) bursts[[cpu]][[(z$burst + 1L) %/% 2L]]$finish <- t + 1
    } else if (mode == 1) {
      sw <- sw - 1
      label <- "CS"
      switching <- switching + 1
    } else idle <- idle + 1
    labels <- c(labels, label)
    for (z in states) if (z$state == "IO") z$left <- z$left - 1
    t <- t + 1
  }
  totals <- numeric(3)
  met <- missed <- 0
  for (i in seq_len(n)) {
    z <- states[[i]]
    u <- p[[i]]
    turn <- z$finish - u$arrival
    totals <- totals + c(turn, turn - sum(u$bursts), z$start - u$arrival)
    if (u$deadline>0) {
      if (z$finish <= u$arrival + u$deadline) met <- met + 1 else missed <- missed + 1
    }
  }
  list(p = p, states = states, bursts = bursts, labels = labels, events = events, shots = shots, finish = t, switches = switches, busy = busy, switching = switching, idle = idle, qmax = qmax, qsum = qsum, met = met, missed = missed, totals = totals)
}

metrics <- function(r, i) {
  p <- r$p[[i]]
  z <- r$states[[i]]
  t <- z$finish - p$arrival
  c(t, t - sum(p$bursts), z$start - p$arrival)
}

summary_line <- function(r) {
  n <- length(r$p)
  paste0("turnaround=", ratio(r$totals[1], n), " waiting=", ratio(r$totals[2], n), " response=", ratio(r$totals[3], n), " util=", ratio(r$busy * 100, r$finish), " end=", r$finish, " switches=", r$switches)
}

command <- function(w) {
  c <- w[1]
  n <- function(i) as.numeric(w[i])
  p <- if (length(w)>1) registry[[w[2]]] else NULL
  if (c == "PROC") {
    if (!is.null(p)) fail(paste("duplicate process", w[2]))
    if (length(registry) == 10) fail("too many processes")
    if (n(3)>200) fail(paste("invalid arrival", w[2]))
    if (n(4)>9) fail(paste("invalid priority", w[2]))
    b <- as.numeric(substring(w[-seq_len(4L)], 2))
    letters <- substring(w[-seq_len(4L)], 1, 1)
    if (length(b) %% 2 == 0 || any(b<1|b>30) || any(letters != rep(c("C", "I"), length.out = length(b)))) fail(paste("invalid bursts", w[2]))
    p <- list(id = w[2], arrival = n(3), priority = n(4), deadline = 0, bursts = b)
    registry[[p$id]] <<- p
    emit(c, p$id, paste0("cpu=", sum(b[seq(1, length(b), by = 2)])), paste0("io=", sum(b[which(seq_along(b) %% 2 == 0)])))
    return(invisible(NULL))
  }
  if (c == "GEN") {
    count <- n(3)
    ids <- paste0(w[2], seq_len(count))
    for (id in ids) if (id %in% names(registry)) fail(paste("duplicate process", id))
    if (length(registry) + count>10) fail("too many processes")
    emit(c, paste0("count=", count))
    x <- n(4)
    next_random <- function() {
      x <<- (48271 * x) %% 2147483647
      x
    }
    for (id in ids) {
      arrival <- next_random() %% 21
      priority <- next_random() %% 10
      m <- 1 + next_random() %% 3
      b <- numeric()
      for (j in seq_len(m)) {
        if (j>1) b <- c(b, 1 + next_random() %% 8)
        b <- c(b, 1 + next_random() %% 9)
      }
      p <- list(id = id, arrival = arrival, priority = priority, deadline = 0, bursts = b)
      registry[[id]] <<- p
      emit(listline(p))
    }
    return(invisible(NULL))
  }
  if (c %in% c("SETPRIO", "DEADLINE", "DROP")) {
    if (is.null(p)) fail(paste("unknown process", w[2]))
    if (c == "DROP") {
      registry[[w[2]]] <<- NULL
      emit(c, w[2])
    } else if (c == "SETPRIO") {
      if (n(3)>9) fail(paste("invalid priority", p$id))
      p$priority <- n(3)
      registry[[p$id]] <<- p
      emit(c, p$id, paste0("priority=", p$priority))
    } else {
      if (n(3)>1000) fail(paste("invalid deadline", p$id))
      p$deadline <- n(3)
      registry[[p$id]] <<- p
      emit(c, p$id, if (p$deadline == 0) "none" else p$deadline)
    }
    return(invisible(NULL))
  }
  if (c == "CLEAR") {
    emit(c, paste0("count=", length(registry)))
    registry <<- list()
    return(invisible(NULL))
  }
  if (c == "LIST") {
    emit(c, paste0("count=", length(registry)))
    for (id in sort(names(registry), method = "radix")) emit(listline(registry[[id]]))
    return(invisible(NULL))
  }
  a <- metric <- ""
  start <- 3L
  multi <- c %in% c("COMPARE", "RANK", "DIFF")
  if (c == "COMPARE") start <- 2L else if (c == "RANK") {
    metric <- w[2]
    if (!(metric %in% c("turnaround", "waiting", "response", "end", "switches", "missed"))) fail(paste("unknown metric", metric))
  } else {
    a <- w[2]
    if (!(a %in% algorithms)) fail(paste("unknown algorithm", a))
    if (c == "DIFF") {
      if (!(w[3] %in% algorithms)) fail(paste("unknown algorithm", w[3]))
      start <- 4L
    }
  }
  if (c %in% c("SNAPSHOT", "WINDOW")) start <- 4L
  if (c == "WINDOW" && (n(3)<1 || n(3)>1000)) fail("invalid window")
  seen <- character()
  if (c == "SWEEP") {
    start <- 6L
    k <- w[3]
    if (!(k %in% keys)) fail(paste("unknown key", k))
    if (!allowed(a, k)) fail(paste("key", k, "not allowed for", a))
    if (n(4)>n(5) || !valid(k, n(4)) || !valid(k, n(5)) || n(5) - n(4)>20) fail("invalid range")
    seen <- k
  }
  param <- list(cs = 0, q = 4, k = 5, s = 0, seed = 1)
  if (start <= length(w)) for (word in w[start:length(w)]) {
    kv <- strsplit(word, "=", fixed = TRUE)[[1]]
    k <- kv[1]
    v <- as.numeric(kv[2])
    if (!(k %in% keys)) fail(paste("unknown key", k))
    if (!multi && !allowed(a, k)) fail(paste("key", k, "not allowed for", a))
    if (k %in% seen) fail(paste("duplicate key", k))
    if (!valid(k, v)) fail(paste("invalid", k))
    seen <- c(seen, k)
    param[[k]] <- v
  }
  if (!length(registry)) fail("no processes")
  ps <- registry[sort(names(registry), method = "radix")]
  N <- length(ps)
  if (c == "SWEEP") {
    emit(c, a, w[3], n(4), n(5))
    best <- Inf
    bestv <- 0
    for (v in seq(n(4), n(5))) {
      param[[w[3]]] <- v
      r <- simulate(ps, a, param)
      emit(notation(a, param), summary_line(r))
      if (r$totals[2]<best) {
        best <- r$totals[2]
        bestv <- v
      }
    }
    emit("BEST", paste0(w[3], "=", bestv))
    return(invisible(NULL))
  }
  if (multi) {
    if (c == "DIFF") {
      r <- simulate(ps, a, param)
      s <- simulate(ps, w[3], param)
      emit(c, a, w[3], notation("", param, TRUE))
      wins <- loss <- ties <- 0
      for (i in seq_len(N)) {
        u <- metrics(r, i)
        v <- metrics(s, i)
        emit(ps[[i]]$id, paste0("turnaround=", u[1], "/", v[1]), paste0("waiting=", u[2], "/", v[2]), paste0("response=", u[3], "/", v[3]))
        if (u[1]<v[1]) wins <- wins + 1 else if (u[1]>v[1]) loss <- loss + 1 else ties <- ties + 1
      }
      emit("WINS", paste0(a, "=", wins), paste0(w[3], "=", loss), paste0("ties=", ties))
      return(invisible(NULL))
    }
    results <- lapply(algorithms, function(a) simulate(ps, a, param))
    if (c == "COMPARE") {
      emit(c, notation("", param, TRUE))
      row <- function(v) cat(paste0(sprintf("%-8s", v[1]), " ", paste(sprintf("%8s", v[-1L]), collapse = " ")), "\n", sep = "")
      row(c("ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"))
      for (i in seq_along(results)) {
        r <- results[[i]]
        row(c(algorithms[i], vapply(r$totals, function(u) ratio(u, N), character(1)), ratio(r$busy * 100, r$finish), r$finish, r$switches, r$missed))
      }
      best <- vapply(seq_len(3L), function(j) algorithms[which.min(vapply(results, function(r) r$totals[j], numeric(1)))], character(1))
      emit("BEST", paste(paste0(c("turnaround", "waiting", "response"), "=", best), collapse = " "))
    } else {
      emit(c, metric, notation("", param, TRUE))
      j <- match(metric, c("turnaround", "waiting", "response"))
      values <- vapply(results, function(r) if (!is.na(j)) r$totals[j] else switch(metric, end = r$finish, switches = r$switches, missed = r$missed), numeric(1))
      for (i in order(values)) emit(sum(values<values[i]) + 1, algorithms[i], if (is.na(j)) values[i] else ratio(values[i], N))
    }
    return(invisible(NULL))
  }
  r <- simulate(ps, a, param)
  note <- notation(a, param)
  T <- r$finish
  if (c == "TRACE") {
    emit(c, a, note)
    for (s in r$events) emit(s)
    emit("END", T)
  } else if (c == "TIMELINE") {
    if (T>100) fail(paste("too long", T))
    emit(c, a, note, paste0("end=", T))
    chars <- c(FUTURE = "-", DONE = "-", READY = ".", SWITCH = "s", RUN = "#", IO = "i")
    for (i in seq_len(N)) emit(sprintf("%-8s", ps[[i]]$id), paste(vapply(r$shots[seq_len(T)], function(s) chars[[s$states[[i]]$state]], character(1)), collapse = ""))
  } else if (c == "SNAPSHOT") {
    t <- n(3)
    s <- r$shots[[min(t, T) + 1L]]
    emit(c, a, note, paste0("t=", t))
    if (s$mode == 0) emit("CPU IDLE") else emit("CPU", if (s$mode == 1) "SWITCH" else "RUN", ps[[s$cpu]]$id)
    for (l in seq_len(if (a == "MLFQ") 3L else 1L)) {
      ids <- vapply(s$queues[[l]], function(i) ps[[i]]$id, character(1))
      emit(if (a == "MLFQ") paste0("QUEUE", l - 1L) else "QUEUE", if (length(ids)) paste(ids, collapse = " ") else "none")
    }
    for (i in seq_len(N)) {
      p <- ps[[i]]
      z <- s$states[[i]]
      if (z$state == "FUTURE") emit(p$id, "FUTURE", paste0("at=", p$arrival)) else if (z$state == "DONE") emit(p$id, "DONE", paste0("at=", z$finish)) else {
        line <- paste(p$id, z$state, paste0("burst=", z$burst), paste0("left=", z$left))
        if (a == "PRIORITY") line <- paste(line, paste0("prio=", z$effective))
        if (a == "MLFQ") line <- paste(line, paste0("level=", z$level), paste0("used=", z$used))
        emit(line)
      }
    }
  } else if (c == "BURSTS") {
    emit(c, a, note)
    for (i in seq_len(N)) for (j in seq_along(r$bursts[[i]])) {
      b <- r$bursts[[i]][[j]]
      len <- ps[[i]]$bursts[2 * j - 1]
      emit(ps[[i]]$id, paste0("#", j), paste0("len=", len), paste0("ready=", b$ready), paste0("start=", b$start), paste0("end=", b$finish), paste0("wait=", b$finish - b$ready - len), paste0("slices=", b$slices))
    }
  } else if (c == "WINDOW") {
    width <- n(3)
    emit(c, a, note, paste0("width=", width))
    for (lo in seq(0, T - 1, by = width)) {
      hi <- min(lo + width, T)
      shots <- r$shots[(lo + 1):hi]
      modes <- vapply(shots, function(s) s$mode, numeric(1))
      labels <- vapply(shots[modes == 2], function(s) ps[[s$cpu]]$id, character(1))
      cs <- sum(modes == 1)
      idle <- sum(modes == 0)
      busy <- hi - lo - cs - idle
      counts <- vapply(ps, function(p) sum(labels == p$id), numeric(1))
      top <- if (max(counts) == 0) "none" else ps[[which.max(counts)]]$id
      emit(paste0(lo, "-", hi), paste0("busy=", busy), paste0("switch=", cs), paste0("idle=", idle), paste0("util=", ratio(busy * 100, hi - lo)), paste0("top=", top))
    }
  } else if (c == "STATS") {
    emit(c, a, note)
    for (j in seq_len(3L)) {
      k <- c("turnaround", "waiting", "response")[j]
      values <- vapply(seq_len(N), function(i) metrics(r, i)[j], numeric(1))
      lo <- which.min(values)
      hi <- which.max(values)
      v <- sort(values)
      med <- if (N %% 2) 2 * v[(N + 1L) %/% 2L] else v[N %/% 2L] + v[N %/% 2L + 1L]
      emit(k, paste0("min=", values[lo]), paste0("(", ps[[lo]]$id, ")"), paste0("max=", values[hi]), paste0("(", ps[[hi]]$id, ")"), paste0("median=", med %/% 2, ".", med %% 2 * 5), paste0("total=", r$totals[j]))
    }
  } else if (c == "RUN") {
    emit(c, a, note)
    segments <- character()
    lo <- 0
    while (lo<T) {
      hi <- lo + 1
      while (hi<T && r$labels[hi + 1] == r$labels[lo + 1]) hi <- hi + 1
      segments <- c(segments, paste0("[", lo, "-", hi, " ", r$labels[lo + 1], "]"))
      lo <- hi
    }
    for (i in seq(1, length(segments), by = 8)) emit("GANTT", paste(segments[i:min(i + 7, length(segments))], collapse = ""))
    for (i in seq_len(N)) {
      p <- ps[[i]]
      z <- r$states[[i]]
      m <- metrics(r, i)
      line <- paste(p$id, paste0("arrival=", p$arrival), paste0("done=", z$finish), paste0("turnaround=", m[1]), paste0("waiting=", m[2]), paste0("response=", m[3]), paste0("slices=", z$slices))
      if (p$deadline>0) {
        d <- p$arrival + p$deadline
        line <- paste(line, paste0("deadline=", d), paste0("late=", max(0, z$finish - d)))
      }
      emit(line)
    }
    emit("AVERAGE", paste0("turnaround=", ratio(r$totals[1], N)), paste0("waiting=", ratio(r$totals[2], N)), paste0("response=", ratio(r$totals[3], N)))
    emit("CPU", paste0("end=", T), paste0("busy=", r$busy), paste0("switch=", r$switching), paste0("idle=", r$idle), paste0("switches=", r$switches), paste0("util=", ratio(r$busy * 100, T)))
    emit("QUEUE", paste0("max=", r$qmax), paste0("avg=", ratio(r$qsum, T)))
    event_names <- vapply(strsplit(r$events, " ", fixed = TRUE), function(w) w[2], character(1))
    counts <- vapply(c("PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE"), function(k) sum(event_names == k), numeric(1))
    emit("EVENTS", paste0("preempt=", counts[1]), paste0("expire=", counts[2]), paste0("demote=", counts[3]), paste0("boost=", counts[4]), paste0("age=", counts[5]))
    emit("DEADLINE", paste0("met=", r$met), paste0("missed=", r$missed))
  }
  invisible(NULL)
}
input <- readLines(file("stdin"), warn = FALSE)
for (i in seq_len(as.integer(input[1]))) tryCatch(command(strsplit(input[i + 1L], " ", fixed = TRUE)[[1]]), command_error = function(e) emit("ERROR", e$message))
