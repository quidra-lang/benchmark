options(scipen = 999L)
orders <- list()
traders <- new.env(hash = TRUE, parent = emptyenv())
trades <- list()
priority <- maker <- taker <- band <- 0L
tick <- lot <- 1L
halted <- FALSE

emit <- function(...) cat(paste(..., collapse = " "), "\n", sep = "")

fail <- function(s) stop(structure(list(message = s, call = NULL), class = c("command_error", "error", "condition")))

dec <- function(n) sprintf("%d.%02d", n %/% 100L, n %% 100L)

resting <- function(o) o$status %in% c("OPEN", "PARTIAL")

active <- function(o) resting(o) || o$status == "PENDING"

last_price <- function() if (length(trades)) trades[[length(trades)]]$price else 0L

register <- function(t) {
  if (!exists(t, traders, inherits = FALSE)) {
    x <- new.env(parent = emptyenv())
    x$bought <- x$sold <- x$cash <- x$fees <- 0L
    x$limit <- NULL
    traders[[t]] <- x
  }
  traders[[t]]
}

exposure <- function(t, s, excluded = NULL) {
  x <- if (exists(t, traders, inherits = FALSE)) traders[[t]] else NULL
  n <- if (is.null(x)) 0L else x$bought - x$sold
  v <- if (s == "BUY") n else - n
  for (o in orders) if (!identical(o, excluded) && o$trader == t && o$side == s && active(o)) v <- v + o$remaining
  v
}

risk <- function(t, s, q, excluded = NULL) {
  if (!exists(t, traders, inherits = FALSE)) return(FALSE)
  x <- traders[[t]]
  !is.null(x$limit) && exposure(t, s, excluded) + q>x$limit
}

outside <- function(p) band>0L && length(trades)>0L && abs(p - last_price())>band

matchable <- function(o, p) o$price == 0L || if (o$side == "BUY") p <= o$price else p >= o$price

triggered <- function(o, p) if (o$side == "BUY") p >= o$trigger else p <= o$trigger

book <- function(s) {
  a <- Filter(function(o) resting(o) && o$side == s, orders)
  if (!length(a)) return(a)
  p <- vapply(a, function(o) o$price, integer(1L))
  r <- vapply(a, function(o) o$priority, integer(1L))
  a[order(if (s == "BUY") - p else p, r)]
}

best <- function(s) {
  a <- book(s)
  if (length(a)) a[[1L]] else NULL
}

order_line <- function(o) emit("ORDER", o$id, o$status, paste0(o$filled, "/", o$quantity))

details <- function(o) {
  p <- if (o$price == 0L) "-" else o$price
  a <- if (o$filled == 0L) "-" else dec((o$value * 100L) %/% o$filled)
  s <- paste(o$id, o$trader, o$kind, o$side, p, o$status, paste0(o$filled, "/", o$quantity), "avg", a)
  if (o$trigger>0L) s <- paste(s, "trigger", o$trigger)
  s
}

position <- function(t) {
  x <- traders[[t]]
  n <- x$bought - x$sold
  emit("POSITION", t, "bought", x$bought, "sold", x$sold, "net", n, "cash", x$cash, "fees", x$fees, "pnl", x$cash + n * last_price())
}

trade_line <- function(i) {
  x <- trades[[i]]
  emit("TRADE", i, x$price, x$quantity, x$buy$id, x$buy$trader, x$sell$id, x$sell$trader)
}

execute <- function(o) {
  op <- if (o$side == "BUY") "SELL" else "BUY"
  while (o$remaining>0L) {
    y <- best(op)
    if (is.null(y) || !matchable(o, y$price)) break
    if (y$trader == o$trader) {
      emit("STP", y$id, y$remaining)
      y$history <- c(y$history, paste("STP", y$remaining))
      y$remaining <- 0L
      y$status <- "CANCELLED"
      next
    }
    q <- min(o$remaining, y$visible)
    p <- y$price
    tf <- q * taker
    mf <- q * maker
    if (o$side == "BUY") {
      b <- o
      s <- y
      bf <- tf
      sf <- mf
    } else {
      b <- y
      s <- o
      bf <- mf
      sf <- tf
    }
    trades[[length(trades) + 1L]] <<- list(price = p, quantity = q, buy = b, sell = s, taker = o, bf = bf, sf = sf)
    i <- length(trades)
    for (x in list(o, y)) {
      x$remaining <- x$remaining - q
      x$filled <- x$filled + q
      x$value <- x$value + q * p
      x$history <- c(x$history, paste("FILL", i, p, q))
    }
    y$visible <- y$visible - q
    bt <- traders[[b$trader]]
    st <- traders[[s$trader]]
    bt$bought <- bt$bought + q
    bt$cash <- bt$cash - q * p - bf
    bt$fees <- bt$fees + bf
    st$sold <- st$sold + q
    st$cash <- st$cash + q * p - sf
    st$fees <- st$fees + sf
    trade_line(i)
    if (y$remaining == 0L) y$status <- "FILLED" else {
      y$status <- "PARTIAL"
      if (y$visible == 0L) {
        priority <<- priority + 1L
        y$priority <- priority
        y$visible <- min(y$peak, y$remaining)
        h <- y$remaining - y$visible
        y$history <- c(y$history, paste("REFRESH", y$visible, h))
        emit("REFRESH", y$id, y$visible, h)
      }
    }
  }
}

post <- function(o, force = FALSE) {
  if (o$remaining == 0L) o$status <- "FILLED" else if (force || (o$kind == "LIMIT" && o$condition != "IOC") || o$kind %in% c("ICEBERG", "STOPLIMIT")) {
    priority <<- priority + 1L
    o$priority <- priority
    o$visible <- if (o$peak>0L) min(o$peak, o$remaining) else o$remaining
    o$status <- if (o$filled>0L) "PARTIAL" else "OPEN"
    o$history <- c(o$history, paste("REST", o$price, o$visible))
  } else {
    o$history <- c(o$history, paste("EXPIRE", o$remaining))
    o$remaining <- 0L
    o$status <- "CANCELLED"
  }
  order_line(o)
}

trigger_stops <- function() {
  while (length(trades)) {
    p <- last_price()
    selected <- Filter(function(o) o$status == "PENDING" && triggered(o, p), orders)
    if (!length(selected)) return(invisible(NULL))
    for (o in selected) o$status <- "TRIGGERING"
    for (o in selected) {
      emit("TRIGGER", o$id)
      o$history <- c(o$history, "TRIGGER")
      execute(o)
      post(o)
    }
  }
}

cancel <- function(o) {
  o$history <- c(o$history, paste("CANCEL", o$remaining))
  o$remaining <- 0L
  o$status <- "CANCELLED"
  order_line(o)
}

levels <- function(s) {
  a <- book(s)
  p <- unique(vapply(a, function(o) o$price, integer(1L)))
  lapply(p, function(x) {
    b <- Filter(function(o) o$price == x, a)
    c(x, sum(vapply(b, function(o) o$visible, integer(1L))), length(b))
  })
}

command <- function(w) {
  c <- w[1L]
  n <- function(i) as.integer(w[i])
  if (c %in% c("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG")) {
    p <- r <- k <- 0L
    condition <- ""
    if (c == "MARKET") q <- n(5L) else if (c == "STOP") {
      r <- n(5L)
      q <- n(6L)
    } else if (c == "STOPLIMIT") {
      r <- n(5L)
      p <- n(6L)
      q <- n(7L)
    } else {
      p <- n(5L)
      q <- n(6L)
      if (c == "ICEBERG") k <- n(7L) else if (length(w) == 7L) condition <- w[7L]
    }
    prices <- switch(c, MARKET = integer(), STOP = r, STOPLIMIT = c(r, p), p)
    if (halted) fail("halted")
    if (w[2L] %in% names(orders)) fail("duplicate id")
    if (any(prices == 0L)) fail("invalid price")
    if (q == 0L) fail("invalid quantity")
    if (any(prices %% tick != 0L)) fail("invalid tick")
    if (q %% lot != 0L) fail("invalid lot")
    o <- new.env(parent = emptyenv())
    o$id <- w[2L]
    o$trader <- w[3L]
    o$kind <- c
    o$side <- w[4L]
    o$condition <- condition
    o$status <- "ARRIVING"
    o$price <- p
    o$trigger <- r
    o$peak <- k
    o$quantity <- o$remaining <- q
    o$visible <- o$filled <- o$value <- o$priority <- 0L
    o$history <- "ACCEPT"
    if (r>0L && length(trades)>0L && triggered(o, last_price())) fail("invalid trigger")
    if (c == "ICEBERG" && (k == 0L || k>q || k %% lot != 0L)) fail("invalid peak")
    if (p>0L && outside(p)) fail("outside band")
    if (risk(o$trader, o$side, q)) fail("risk limit")
    b <- book(if (o$side == "BUY") "SELL" else "BUY")
    if (condition == "POSTONLY" && length(b) && matchable(o, b[[1L]]$price)) fail("would cross")
    if (condition == "FOK" && sum(vapply(Filter(function(x) x$trader != o$trader && matchable(o, x$price), b), function(x) x$remaining, integer(1L)))<q) fail("unfillable")
    register(o$trader)
    orders[[o$id]] <<- o
    if (r>0L) {
      o$status <- "PENDING"
      order_line(o)
    } else {
      if (condition != "POSTONLY") execute(o)
      post(o)
      trigger_stops()
    }
    return(invisible(NULL))
  }
  if (c %in% c("CANCEL", "REPLACE", "STATUS", "HISTORY")) {
    if (c == "REPLACE" && halted) fail("halted")
    if (!(w[2L] %in% names(orders))) fail("unknown order")
    o <- orders[[w[2L]]]
    if (c == "STATUS") emit(c, details(o)) else if (c == "HISTORY") {
      emit(c, o$id, length(o$history))
      for (h in o$history) emit(h)
    } else if (c == "CANCEL") {
      if (!active(o)) fail("not open")
      cancel(o)
    } else {
      p <- n(3L)
      q <- n(4L)
      moved <- p != o$price
      if (!resting(o)) fail("not open")
      if (p == 0L) fail("invalid price")
      if (q == 0L) fail("invalid quantity")
      if (moved && p %% tick != 0L) fail("invalid tick")
      if (q %% lot != 0L) fail("invalid lot")
      if (!moved && q == o$remaining) fail("no change")
      if (moved && outside(p)) fail("outside band")
      if (q>o$remaining && risk(o$trader, o$side, q, o)) fail("risk limit")
      kept <- !moved && q<o$remaining
      mode <- if (kept) "kept" else "lost"
      o$quantity <- o$filled + q
      o$price <- p
      o$remaining <- q
      o$history <- c(o$history, paste("REPLACE", p, q, mode))
      emit(c, o$id, mode)
      if (kept) {
        o$visible <- min(o$visible, q)
        order_line(o)
      } else {
        o$status <- "ARRIVING"
        execute(o)
        post(o, TRUE)
        trigger_stops()
      }
    }
    return(invisible(NULL))
  }
  if (c %in% c("CANCELALL", "ORDERS", "POSITION", "FILLS")) {
    t <- w[2L]
    if (!exists(t, traders, inherits = FALSE)) fail("unknown trader")
    if (c %in% c("CANCELALL", "ORDERS")) {
      a <- Filter(function(o) active(o) && o$trader == t, orders)
      emit(c, t, length(a))
      for (o in a) if (c == "CANCELALL") cancel(o) else emit(details(o))
    } else if (c == "POSITION") position(t) else {
      ids <- which(vapply(trades, function(x) x$buy$trader == t || x$sell$trader == t, logical(1L)))
      emit(c, t, length(ids))
      net <- 0L
      for (i in ids) {
        x <- trades[[i]]
        buy <- x$buy$trader == t
        o <- if (buy) x$buy else x$sell
        net <- net + if (buy) x$quantity else - x$quantity
        emit(i, if (buy) "BUY" else "SELL", x$price, x$quantity, o$id, if (identical(x$taker, o)) "TAKER" else "MAKER", "fee", if (buy) x$bf else x$sf, "net", net)
      }
    }
    return(invisible(NULL))
  }
  if (c == "HALT") {
    if (halted) fail("already halted")
    halted <<- TRUE
    emit(c)
  } else if (c == "RESUME") {
    if (!halted) fail("not halted")
    halted <<- FALSE
    emit(c)
  } else if (c == "RISK") {
    t <- w[2L]
    m <- n(3L)
    x <- register(t)
    x$limit <- m
    emit(c, t, m, "exposure buy", exposure(t, "BUY"), "sell", exposure(t, "SELL"))
  } else if (c == "FEE") {
    a <- n(2L)
    b <- n(3L)
    if (a + b<0L) fail("invalid fee")
    maker <<- a
    taker <<- b
    emit(c, "maker", a, "taker", b)
  } else if (c == "BAND") {
    band <<- n(2L)
    emit(c, band)
  } else if (c %in% c("TICK", "LOT")) {
    u <- n(2L)
    if (u == 0L) fail("invalid size")
    if (c == "TICK") tick <<- u else lot <<- u
    emit(c, u)
  } else if (c == "BOOK") {
    k <- n(2L)
    if (k == 0L) fail("invalid depth")
    b <- levels("BUY")
    a <- levels("SELL")
    emit(c, "bids", length(b), "asks", length(a))
    for (x in rev(head(a, k))) emit("ASK", x[1L], x[2L], x[3L])
    for (x in head(b, k)) emit("BID", x[1L], x[2L], x[3L])
  } else if (c == "LAST") {
    if (!length(trades)) emit(c, "none") else {
      x <- trades[[length(trades)]]
      emit(c, x$price, x$quantity)
    }
  } else if (c == "VWAP") {
    if (!length(trades)) emit(c, "none") else {
      v <- sum(vapply(trades, function(x) x$quantity, integer(1L)))
      a <- sum(vapply(trades, function(x) x$price * x$quantity, integer(1L)))
      emit(c, dec((a * 100L) %/% v), "volume", v, "trades", length(trades))
    }
  } else if (c == "SPREAD") {
    b <- best("BUY")
    a <- best("SELL")
    if (is.null(b) || is.null(a)) emit(c, "bid", if (is.null(b)) "none" else b$price, "ask", if (is.null(a)) "none" else a$price) else {
      s <- a$price + b$price
      emit(c, "bid", b$price, "ask", a$price, "spread", a$price - b$price, "mid", paste0(s %/% 2L, ".", s %% 2L * 5L))
    }
  } else if (c == "IMPACT") {
    s <- w[2L]
    q <- n(3L)
    if (q == 0L) fail("invalid quantity")
    r <- q
    cost <- worst <- used <- total <- 0L
    for (x in levels(if (s == "BUY") "SELL" else "BUY")) {
      total <- total + x[2L]
      if (r>0L) {
        u <- min(r, x[2L])
        r <- r - u
        cost <- cost + u * x[1L]
        worst <- x[1L]
        used <- used + 1L
      }
    }
    if (r>0L) emit(c, s, q, "insufficient", total) else emit(c, s, q, "avg", dec((cost * 100L) %/% q), "worst", worst, "levels", used)
  } else if (c %in% c("TRADES", "BARS")) {
    k <- n(2L)
    if (k == 0L) fail("invalid count")
    T <- length(trades)
    if (c == "TRADES") {
      m <- min(k, T)
      emit(c, m, "of", T)
      for (i in tail(seq_len(T), m)) trade_line(i)
    } else {
      emit(c, T %/% k + as.integer(T %% k != 0L))
      if (T) for (i in seq(1L, T, by = k)) {
        g <- trades[i:min(i + k - 1L, T)]
        p <- vapply(g, function(x) x$price, integer(1L))
        emit((i - 1L) %/% k + 1L, "open", p[1L], "high", max(p), "low", min(p), "close", tail(p, 1L), "volume", sum(vapply(g, function(x) x$quantity, integer(1L))))
      }
    }
  } else if (c == "RANK") {
    names <- ls(traders, sorted = FALSE)
    pnl <- vapply(names, function(t) {
      x <- traders[[t]]
      x$cash + (x$bought - x$sold) * last_price()
    }, integer(1L))
    v <- vapply(names, function(t) {
      x <- traders[[t]]
      x$bought + x$sold
    }, integer(1L))
    idx <- order(-pnl, -v, names, method = "radix")
    emit(c, length(idx))
    for (i in seq_along(idx)) {
      j <- idx[i]
      emit(i, names[j], "pnl", pnl[j], "volume", v[j])
    }
  } else if (c == "FLOW") {
    b <- s <- 0L
    for (x in trades) if (x$taker$side == "BUY") b <- b + x$quantity else s <- s + x$quantity
    emit(c, "buy", b, "sell", s, "net", b - s)
  } else if (c == "SUMMARY") {
    if (!length(trades)) emit(c, "trades", 0L) else {
      p <- vapply(trades, function(x) x$price, integer(1L))
      emit(c, "trades", length(trades), "volume", sum(vapply(trades, function(x) x$quantity, integer(1L))), "open", p[1L], "high", max(p), "low", min(p), "close", tail(p, 1L), "fees", sum(vapply(trades, function(x) x$bf + x$sf, integer(1L))))
    }
    for (t in sort(ls(traders), method = "radix")) position(t)
  }
  invisible(NULL)
}
input <- readLines(file("stdin"), warn = FALSE)
for (i in seq_len(as.integer(input[1L]))) {
  w <- strsplit(input[i + 1L], " ", fixed = TRUE)[[1L]]
  tryCatch(command(w), command_error = function(e) if (w[1L] %in% c("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG", "CANCEL", "REPLACE")) emit("REJECT", w[2L], e$message) else emit("ERROR", e$message))
}
