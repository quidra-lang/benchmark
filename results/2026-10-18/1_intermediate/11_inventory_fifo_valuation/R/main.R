categories <- c(
  "received", "returned", "adjusted-in", "adjusted-out",
  "shipped", "written-down", "expired", "recalled"
)

object <- function(...) list2env(list(...), parent = emptyenv())
has <- function(env, key) exists(key, envir = env, inherits = FALSE)
names_sorted <- function(env) sort(ls(envir = env, all.names = TRUE))

number <- function(text) as.numeric(text)
cents <- function(text) as.numeric(gsub(".", "", text, fixed = TRUE))
digits <- function(value) sprintf("%.0f", value)

money <- function(value) {
  amount <- abs(value)
  paste0(
    if (value < 0) "-" else "",
    digits(floor(amount / 100)), ".",
    sprintf("%02d", as.integer(amount %% 100))
  )
}

signed_quantity <- function(value) {
  paste0(if (value > 0) "+" else "", digits(value))
}

signed_money <- function(value) {
  paste0(if (value > 0) "+" else "", money(value))
}

margin <- function(profit, revenue) {
  if (revenue == 0) return("n/a")
  tenths <- floor(abs(profit) * 1000 / revenue)
  paste0(
    if (profit < 0 && tenths > 0) "-" else "",
    digits(floor(tenths / 10)), ".", digits(tenths %% 10), "%"
  )
}

fail <- function(reason) {
  stop(structure(
    list(message = reason, call = NULL),
    class = c("command_error", "error", "condition")
  ))
}

stock_quantity <- function(stocks) {
  if (length(stocks) == 0) return(0)
  sum(vapply(stocks, function(stock) stock$quantity, numeric(1)))
}

stock_value <- function(stocks) {
  if (length(stocks) == 0) return(0)
  sum(vapply(stocks, function(stock) stock$quantity * stock$cost, numeric(1)))
}

inventory <- function() {
  totals <- new.env(parent = emptyenv())
  for (category in categories) {
    totals[[category]] <- object(quantity = 0, value = 0)
  }
  object(
    day = 1, stock = new.env(parent = emptyenv()),
    items = new.env(parent = emptyenv()),
    lots = list(), orders = list(), totals = totals, output = character()
  )
}

emit <- function(inv, indent, ...) {
  parts <- unlist(list(...), use.names = FALSE)
  inv$output <- c(
    inv$output,
    paste0(strrep(" ", indent), paste(as.character(parts), collapse = " "))
  )
}

warehouse <- function(inv, code) {
  if (!has(inv$stock, code)) fail(paste("unknown warehouse", code))
  code
}

item <- function(inv, code) {
  if (!has(inv$items, code)) fail(paste("unknown item", code))
  inv$items[[code]]
}

pair <- function(inv, w, code) {
  warehouse(inv, w)
  item(inv, code)
}

lookup_order <- function(inv, text) {
  id <- number(text)
  if (id < 1 || id > length(inv$orders)) fail(paste("unknown order", text))
  inv$orders[[id]]
}

lookup_lot <- function(inv, text) {
  id <- number(text)
  if (id < 1 || id > length(inv$lots)) fail(paste("unknown lot", text))
  inv$lots[[id]]
}

require_quantity <- function(q) {
  if (q == 0) fail("invalid quantity")
}

holdings <- function(inv, w, code) {
  bucket <- inv$stock[[w]][[code]]
  if (is.null(bucket)) return(list())
  as.list(bucket, all.names = TRUE)
}

fifo <- function(inv, w, code) {
  stocks <- holdings(inv, w, code)
  if (length(stocks) == 0) return(stocks)
  stocks[order(
    vapply(stocks, function(s) s$lot$day, numeric(1)),
    vapply(stocks, function(s) s$lot$number, numeric(1))
  )]
}

quantity <- function(inv, w, code) stock_quantity(holdings(inv, w, code))

total_quantity <- function(inv, code) {
  sum(vapply(
    names_sorted(inv$stock), function(w) quantity(inv, w, code), numeric(1)
  ))
}

backorder <- function(inv, code) {
  if (length(inv$orders) == 0) return(0)
  sum(vapply(
    inv$orders, function(o) if (o$item == code) o$backorder else 0, numeric(1)
  ))
}

all_stocks <- function(inv) {
  stocks <- list()
  for (w in names_sorted(inv$stock)) {
    for (code in names_sorted(inv$stock[[w]])) {
      stocks <- c(stocks, holdings(inv, w, code))
    }
  }
  stocks
}

require_stock <- function(inv, w, code, q) {
  available <- quantity(inv, w, code)
  if (available < q) {
    fail(paste("insufficient stock", w, code, digits(available)))
  }
}

card_entry <- function(inv, code, kind, w, q, value) {
  entry <- item(inv, code)
  entry$card[[length(entry$card) + 1]] <- list(
    day = inv$day, kind = kind, warehouse = w, quantity = q, value = value
  )
}

accumulate <- function(inv, category, q, value) {
  total <- inv$totals[[category]]
  total$quantity <- total$quantity + q
  total$value <- total$value + value
}

add_stock <- function(inv, w, lot, q, cost) {
  location <- inv$stock[[w]]
  bucket <- location[[lot$item]]
  if (is.null(bucket)) {
    bucket <- new.env(parent = emptyenv())
    location[[lot$item]] <- bucket
  }
  key <- as.character(lot$number)
  if (has(bucket, key)) {
    stock <- bucket[[key]]
    stock$quantity <- stock$quantity + q
  } else {
    bucket[[key]] <- object(lot = lot, quantity = q, cost = cost)
  }
}

create_lot <- function(inv, w, code, day, q, cost, kind) {
  lot <- object(
    number = length(inv$lots) + 1, item = code, warehouse = w,
    kind = kind, day = day, initial_quantity = q,
    initial_cost = cost, removed = 0
  )
  inv$lots[[length(inv$lots) + 1]] <- lot
  add_stock(inv, w, lot, q, cost)
  lot
}

issue <- function(inv, w, code, q) {
  parts <- list()
  cost <- 0
  for (stock in fifo(inv, w, code)) {
    if (q == 0) break
    taken <- min(q, stock$quantity)
    parts[[length(parts) + 1]] <- list(
      lot = stock$lot, quantity = taken, cost = stock$cost
    )
    cost <- cost + taken * stock$cost
    stock$quantity <- stock$quantity - taken
    q <- q - taken
    if (stock$quantity == 0) {
      rm(list = as.character(stock$lot$number), envir = inv$stock[[w]][[code]])
    }
  }
  list(parts = parts, cost = cost)
}

fulfil <- function(inv, order, q, kind) {
  if (q == 0) return(0)
  issued <- issue(inv, order$warehouse, order$item, q)
  order$shipped <- order$shipped + q
  order$backorder <- order$backorder - q
  order$revenue <- order$revenue + q * order$price
  order$cogs <- order$cogs + issued$cost
  order$issues <- c(order$issues, issued$parts)
  accumulate(inv, "shipped", q, issued$cost)
  card_entry(inv, order$item, kind, order$warehouse, -q, -issued$cost)
  issued$cost
}

allocate <- function(inv, w, code) {
  available <- quantity(inv, w, code)
  for (order in inv$orders) {
    if (available == 0) break
    if (order$warehouse != w || order$item != code || order$backorder == 0) next
    q <- min(available, order$backorder)
    cost <- fulfil(inv, order, q, "fill")
    revenue <- q * order$price
    available <- available - q
    emit(inv, 2, "FILL", "order", digits(order$number), "qty", digits(q),
         "revenue", money(revenue), "cogs", money(cost),
         "profit", money(revenue - cost), "backorder", digits(order$backorder))
  }
}

remove_parts <- function(parts) {
  for (part in parts) {
    part$lot$removed <- part$lot$removed + part$quantity
  }
}

sales <- function(inv) {
  rows <- new.env(parent = emptyenv())
  for (order in inv$orders) {
    if (!has(rows, order$item)) {
      rows[[order$item]] <- object(quantity = 0, revenue = 0, cogs = 0)
    }
    row <- rows[[order$item]]
    row$quantity <- row$quantity + order$shipped - order$returned
    row$revenue <- row$revenue + order$revenue
    row$cogs <- row$cogs + order$cogs
  }
  rows
}

margin_line <- function(inv, label, row) {
  profit <- row$revenue - row$cogs
  emit(inv, 2, label, "sold", digits(row$quantity),
       "revenue", money(row$revenue), "cogs", money(row$cogs),
       "profit", money(profit), "margin", margin(profit, row$revenue))
}

aging_line <- function(inv, label, buckets, monetary = FALSE) {
  parts <- label
  labels <- c("0-30", "31-60", "61-90", "91+")
  for (i in seq_len(4)) {
    parts <- c(parts, labels[i], if (monetary) money(buckets[i]) else digits(buckets[i]))
  }
  emit(inv, 2, parts)
}

command <- function(inv, cmd, a) {
  if (cmd == "DAY") {
    day <- number(a[1])
    if (day <= inv$day) fail(paste("invalid day", a[1]))
    inv$day <- day
    emit(inv, 0, "DAY", digits(day))

  } else if (cmd == "WAREHOUSE") {
    w <- a[1]
    if (has(inv$stock, w)) fail(paste("duplicate warehouse", w))
    inv$stock[[w]] <- new.env(parent = emptyenv())
    emit(inv, 0, "WAREHOUSE", w)

  } else if (cmd == "ITEM") {
    code <- a[1]
    level <- number(a[2])
    name <- a[3]
    action <- "added"
    if (has(inv$items, code)) {
      entry <- inv$items[[code]]
      entry$level <- level
      entry$name <- name
      action <- "updated"
    } else {
      inv$items[[code]] <- object(
        code = code, name = name, level = level, last_cost = NULL, card = list()
      )
    }
    emit(inv, 0, "ITEM", code, action, name, "level", digits(level))

  } else if (cmd == "RECEIVE") {
    w <- a[1]
    code <- a[2]
    entry <- pair(inv, w, code)
    q <- number(a[3])
    cost <- cents(a[4])
    day <- number(a[5])
    require_quantity(q)
    if (day > inv$day) fail(paste("future day", a[5]))
    lot <- create_lot(inv, w, code, day, q, cost, "receive")
    entry$last_cost <- cost
    accumulate(inv, "received", q, q * cost)
    card_entry(inv, code, "receive", w, q, q * cost)
    emit(inv, 0, "RECEIVE", w, code, "lot", digits(lot$number),
         "qty", digits(q), "cost", money(cost), "day", digits(day),
         "value", money(q * cost))
    allocate(inv, w, code)

  } else if (cmd == "SHIP") {
    w <- a[1]
    code <- a[2]
    pair(inv, w, code)
    q <- number(a[3])
    require_quantity(q)
    order <- object(
      number = length(inv$orders) + 1, warehouse = w, item = code,
      day = inv$day, price = cents(a[4]), ordered = q, shipped = 0,
      backorder = q, cancelled = 0, returned = 0, revenue = 0, cogs = 0,
      issues = list()
    )
    inv$orders[[length(inv$orders) + 1]] <- order
    shipped <- min(q, quantity(inv, w, code))
    cost <- fulfil(inv, order, shipped, "ship")
    emit(inv, 0, "SHIP", "order", digits(order$number), w, code,
         "shipped", digits(shipped), "revenue", money(order$revenue),
         "cogs", money(cost), "profit", money(order$revenue - cost),
         "backorder", digits(order$backorder))

  } else if (cmd == "CANCEL") {
    order <- lookup_order(inv, a[1])
    if (order$backorder == 0) fail(paste("no backorder", a[1]))
    order$cancelled <- order$cancelled + order$backorder
    order$backorder <- 0
    emit(inv, 0, "CANCEL", "order", digits(order$number),
         "qty", digits(order$cancelled))

  } else if (cmd == "TRANSFER") {
    source <- a[1]
    destination <- a[2]
    code <- a[3]
    warehouse(inv, source)
    warehouse(inv, destination)
    if (source == destination) fail(paste("same warehouse", source))
    item(inv, code)
    q <- number(a[4])
    require_quantity(q)
    require_stock(inv, source, code, q)
    issued <- issue(inv, source, code, q)
    for (part in issued$parts) {
      add_stock(inv, destination, part$lot, part$quantity, part$cost)
    }
    card_entry(inv, code, "transfer-out", source, -q, -issued$cost)
    card_entry(inv, code, "transfer-in", destination, q, issued$cost)
    emit(inv, 0, "TRANSFER", source, "->", destination, code,
         "qty", digits(q), "value", money(issued$cost),
         "lots", length(issued$parts))
    allocate(inv, destination, code)

  } else if (cmd == "ADJUST") {
    w <- a[1]
    code <- a[2]
    change <- a[3]
    pair(inv, w, code)
    q <- number(substr(change, 2, nchar(change)))
    require_quantity(q)
    if (substr(change, 1, 1) == "+") {
      cost <- cents(a[4])
      lot <- create_lot(inv, w, code, inv$day, q, cost, "adjust")
      accumulate(inv, "adjusted-in", q, q * cost)
      card_entry(inv, code, "adjust", w, q, q * cost)
      emit(inv, 0, "ADJUST", w, code, paste0("+", digits(q)),
           "lot", digits(lot$number), "value", money(q * cost))
      allocate(inv, w, code)
    } else {
      require_stock(inv, w, code, q)
      issued <- issue(inv, w, code, q)
      remove_parts(issued$parts)
      accumulate(inv, "adjusted-out", q, issued$cost)
      card_entry(inv, code, "adjust", w, -q, -issued$cost)
      emit(inv, 0, "ADJUST", w, code, paste0("-", digits(q)),
           "value", money(issued$cost))
    }

  } else if (cmd == "RETURN") {
    order <- lookup_order(inv, a[1])
    q <- number(a[2])
    cost <- cents(a[3])
    require_quantity(q)
    available <- order$shipped - order$returned
    if (q > available) {
      fail(paste("return exceeds shipped", a[1], digits(available)))
    }
    lot <- create_lot(inv, order$warehouse, order$item, inv$day, q, cost, "return")
    refund <- q * order$price
    order$returned <- order$returned + q
    order$revenue <- order$revenue - refund
    order$cogs <- order$cogs - q * cost
    accumulate(inv, "returned", q, q * cost)
    card_entry(inv, order$item, "return", order$warehouse, q, q * cost)
    emit(inv, 0, "RETURN", "order", digits(order$number),
         order$warehouse, order$item, "qty", digits(q),
         "lot", digits(lot$number), "refund", money(refund),
         "value", money(q * cost))
    allocate(inv, order$warehouse, order$item)

  } else if (cmd == "COUNT") {
    w <- a[1]
    code <- a[2]
    entry <- pair(inv, w, code)
    actual <- number(a[3])
    held <- quantity(inv, w, code)
    if (actual == held) {
      emit(inv, 0, "COUNT", w, code, "qty", digits(actual), "ok")
    } else if (actual < held) {
      q <- held - actual
      issued <- issue(inv, w, code, q)
      remove_parts(issued$parts)
      accumulate(inv, "adjusted-out", q, issued$cost)
      card_entry(inv, code, "count", w, -q, -issued$cost)
      emit(inv, 0, "COUNT", w, code, "qty", digits(held), "->",
           digits(actual), "shortage", digits(q), "value", money(issued$cost))
    } else {
      q <- actual - held
      cost <- if (is.null(entry$last_cost)) 0 else entry$last_cost
      lot <- create_lot(inv, w, code, inv$day, q, cost, "count")
      accumulate(inv, "adjusted-in", q, q * cost)
      card_entry(inv, code, "count", w, q, q * cost)
      emit(inv, 0, "COUNT", w, code, "qty", digits(held), "->",
           digits(actual), "surplus", digits(q), "lot", digits(lot$number),
           "value", money(q * cost))
      allocate(inv, w, code)
    }

  } else if (cmd == "MARKET") {
    code <- a[1]
    item(inv, code)
    price <- cents(a[2])
    changed <- 0
    q <- 0
    loss <- 0
    for (w in names_sorted(inv$stock)) {
      warehouse_loss <- 0
      for (stock in holdings(inv, w, code)) {
        if (stock$cost <= price) next
        warehouse_loss <- warehouse_loss + stock$quantity * (stock$cost - price)
        changed <- changed + 1
        q <- q + stock$quantity
        stock$cost <- price
      }
      if (warehouse_loss > 0) {
        card_entry(inv, code, "writedown", w, 0, -warehouse_loss)
      }
      loss <- loss + warehouse_loss
    }
    accumulate(inv, "written-down", q, loss)
    emit(inv, 0, "MARKET", code, "price", money(price), "lots",
         digits(changed), "qty", digits(q), "loss", money(loss))

  } else if (cmd == "RECALL") {
    lot <- lookup_lot(inv, a[1])
    held <- list()
    for (w in names_sorted(inv$stock)) {
      stock <- holdings(inv, w, lot$item)[[as.character(lot$number)]]
      if (!is.null(stock)) {
        held[[length(held) + 1]] <- list(warehouse = w, stock = stock)
      }
    }
    if (length(held) == 0) fail(paste("nothing to recall", a[1]))
    q <- 0
    value <- 0
    for (entry in held) {
      stock <- entry$stock
      q <- q + stock$quantity
      value <- value + stock$quantity * stock$cost
      rm(list = as.character(lot$number), envir = inv$stock[[entry$warehouse]][[lot$item]])
      card_entry(inv, lot$item, "recall", entry$warehouse,
                 -stock$quantity, -stock$quantity * stock$cost)
    }
    lot$removed <- lot$removed + q
    accumulate(inv, "recalled", q, value)
    emit(inv, 0, "RECALL", "lot", digits(lot$number), lot$item,
         "qty", digits(q), "value", money(value))
    for (entry in held) {
      emit(inv, 2, entry$warehouse, "qty", digits(entry$stock$quantity),
           "value", money(entry$stock$quantity * entry$stock$cost))
    }

  } else if (cmd == "EXPIRE") {
    days <- number(a[1])
    emit(inv, 0, "EXPIRE", digits(days))
    total_q <- 0
    total_value <- 0
    for (code in names_sorted(inv$items)) {
      for (w in names_sorted(inv$stock)) {
        expired <- Filter(
          function(stock) inv$day - stock$lot$day > days,
          holdings(inv, w, code)
        )
        if (length(expired) == 0) next
        q <- stock_quantity(expired)
        value <- stock_value(expired)
        for (stock in expired) {
          stock$lot$removed <- stock$lot$removed + stock$quantity
          rm(list = as.character(stock$lot$number), envir = inv$stock[[w]][[code]])
        }
        accumulate(inv, "expired", q, value)
        card_entry(inv, code, "expire", w, -q, -value)
        total_q <- total_q + q
        total_value <- total_value + value
        emit(inv, 2, code, w, "lots", length(expired), "qty", digits(q),
             "value", money(value))
      }
    }
    emit(inv, 2, "total", "qty", digits(total_q), "value", money(total_value))

  } else if (cmd == "VALUE" || cmd == "AGING") {
    warehouses <- if (length(a) > 0) warehouse(inv, a[1]) else names_sorted(inv$stock)
    if (cmd == "VALUE") {
      emit(inv, 0, c("VALUE", a))
    } else {
      emit(inv, 0, c("AGING", a, "day", digits(inv$day)))
    }
    total_q <- 0
    total_value <- 0
    bucket_q <- numeric(4)
    bucket_v <- numeric(4)
    for (code in names_sorted(inv$items)) {
      rows <- lapply(warehouses, function(w) holdings(inv, w, code))
      selected <- unlist(rows, recursive = FALSE, use.names = FALSE)
      q <- stock_quantity(selected)
      if (q == 0) next
      value <- stock_value(selected)
      if (cmd == "VALUE") {
        emit(inv, 2, code, "qty", digits(q), "value", money(value),
             "avg", money(floor(value / q)))
        if (length(a) == 0) {
          for (i in seq_along(warehouses)) {
            held <- stock_quantity(rows[[i]])
            if (held > 0) {
              emit(inv, 4, warehouses[i], "qty", digits(held),
                   "value", money(stock_value(rows[[i]])))
            }
          }
        }
      } else {
        item_buckets <- numeric(4)
        for (stock in selected) {
          age <- inv$day - stock$lot$day
          bucket <- if (age <= 30) 1 else if (age <= 60) 2 else if (age <= 90) 3 else 4
          item_buckets[bucket] <- item_buckets[bucket] + stock$quantity
          bucket_q[bucket] <- bucket_q[bucket] + stock$quantity
          bucket_v[bucket] <- bucket_v[bucket] + stock$quantity * stock$cost
        }
        aging_line(inv, code, item_buckets)
      }
      total_q <- total_q + q
      total_value <- total_value + value
    }
    if (cmd == "VALUE") {
      emit(inv, 2, "total", "qty", digits(total_q), "value", money(total_value))
    } else {
      aging_line(inv, "total", bucket_q)
      aging_line(inv, "value", bucket_v, TRUE)
    }

  } else if (cmd == "LOTS") {
    w <- a[1]
    code <- a[2]
    pair(inv, w, code)
    emit(inv, 0, "LOTS", w, code)
    stocks <- fifo(inv, w, code)
    pending <- Filter(
      function(o) o$warehouse == w && o$item == code && o$backorder > 0,
      inv$orders
    )
    for (stock in stocks) {
      emit(inv, 2, "lot", digits(stock$lot$number), "day", digits(stock$lot$day),
           "qty", digits(stock$quantity), "cost", money(stock$cost),
           "value", money(stock$quantity * stock$cost),
           "age", digits(inv$day - stock$lot$day))
    }
    for (order in pending) {
      emit(inv, 2, "backorder", "order", digits(order$number),
           "qty", digits(order$backorder))
    }
    if (length(stocks) == 0 && length(pending) == 0) emit(inv, 2, "(none)")

  } else if (cmd == "REORDER" || cmd == "ITEMS") {
    emit(inv, 0, cmd)
    found <- FALSE
    for (code in names_sorted(inv$items)) {
      entry <- inv$items[[code]]
      q <- total_quantity(inv, code)
      pending <- backorder(inv, code)
      if (cmd == "REORDER") {
        if (q - pending > entry$level) next
        emit(inv, 2, code, entry$name, "onhand", digits(q),
             "backorder", digits(pending), "level", digits(entry$level))
      } else {
        emit(inv, 2, code, entry$name, "level", digits(entry$level),
             "onhand", digits(q), "backorder", digits(pending), "cost",
             if (is.null(entry$last_cost)) "none" else money(entry$last_cost))
      }
      found <- TRUE
    }
    if (!found) emit(inv, 2, "(none)")

  } else if (cmd == "MARGIN" || cmd == "TOP") {
    rows <- sales(inv)
    codes <- names_sorted(rows)
    if (cmd == "MARGIN") {
      emit(inv, 0, "MARGIN")
      total_q <- 0
      revenue <- 0
      cogs <- 0
      for (code in codes) {
        entry <- rows[[code]]
        margin_line(inv, code, entry)
        total_q <- total_q + entry$quantity
        revenue <- revenue + entry$revenue
        cogs <- cogs + entry$cogs
      }
      margin_line(inv, "total", object(quantity = total_q, revenue = revenue, cogs = cogs))
    } else {
      k <- number(a[1])
      emit(inv, 0, "TOP", digits(k))
      if (length(codes) > 0) {
        revenue <- vapply(codes, function(c) rows[[c]]$revenue, numeric(1))
        profit <- vapply(codes, function(c) rows[[c]]$revenue - rows[[c]]$cogs, numeric(1))
        codes <- codes[order(-profit, -revenue, codes)]
        if (k > 0) {
          for (i in seq_len(min(k, length(codes)))) {
            entry <- rows[[codes[i]]]
            gain <- entry$revenue - entry$cogs
            emit(inv, 2, digits(i), codes[i], "profit", money(gain),
                 "revenue", money(entry$revenue), "margin", margin(gain, entry$revenue))
          }
        }
      } else {
        emit(inv, 2, "(none)")
      }
    }

  } else if (cmd == "BACKORDERS") {
    emit(inv, 0, "BACKORDERS")
    pending <- Filter(function(o) o$backorder > 0, inv$orders)
    for (order in pending) {
      emit(inv, 2, "order", digits(order$number), order$warehouse, order$item,
           "qty", digits(order$backorder), "day", digits(order$day),
           "price", money(order$price))
    }
    if (length(pending) == 0) emit(inv, 2, "(none)")

  } else if (cmd == "ORDER") {
    order <- lookup_order(inv, a[1])
    emit(inv, 0, "ORDER", digits(order$number), order$warehouse, order$item,
         "day", digits(order$day), "price", money(order$price))
    emit(inv, 2, "ordered", digits(order$ordered), "shipped", digits(order$shipped),
         "backorder", digits(order$backorder), "cancelled", digits(order$cancelled),
         "returned", digits(order$returned))
    for (part in order$issues) {
      emit(inv, 2, "lot", digits(part$lot$number), "qty", digits(part$quantity),
           "cost", money(part$cost))
    }
    emit(inv, 2, "revenue", money(order$revenue), "cogs", money(order$cogs),
         "profit", money(order$revenue - order$cogs))

  } else if (cmd == "TRACE") {
    lot <- lookup_lot(inv, a[1])
    emit(inv, 0, "TRACE", "lot", digits(lot$number), lot$item, lot$kind,
         lot$warehouse, "day", digits(lot$day), "qty", digits(lot$initial_quantity),
         "cost", money(lot$initial_cost))
    for (w in names_sorted(inv$stock)) {
      stock <- holdings(inv, w, lot$item)[[as.character(lot$number)]]
      if (!is.null(stock)) {
        emit(inv, 2, "held", w, "qty", digits(stock$quantity), "cost", money(stock$cost))
      }
    }
    for (order in inv$orders) {
      q <- 0
      for (part in order$issues) {
        if (part$lot$number == lot$number) q <- q + part$quantity
      }
      if (q > 0) emit(inv, 2, "order", digits(order$number), "qty", digits(q))
    }
    if (lot$removed > 0) emit(inv, 2, "removed", "qty", digits(lot$removed))

  } else if (cmd == "CARD") {
    entry <- item(inv, a[1])
    emit(inv, 0, "CARD", entry$code, entry$name)
    q <- 0
    value <- 0
    for (card in entry$card) {
      q <- q + card$quantity
      value <- value + card$value
      emit(inv, 2, "day", digits(card$day), card$kind, card$warehouse,
           signed_quantity(card$quantity), signed_money(card$value),
           "balance", digits(q), money(value))
    }
    if (length(entry$card) == 0) emit(inv, 2, "(none)")

  } else if (cmd == "STATUS") {
    emit(inv, 0, "STATUS")
    for (w in names_sorted(inv$stock)) {
      skus <- 0
      stocks <- list()
      for (code in names_sorted(inv$stock[[w]])) {
        current <- holdings(inv, w, code)
        if (length(current) > 0) skus <- skus + 1
        stocks <- c(stocks, current)
      }
      pending <- 0
      for (order in inv$orders) {
        if (order$warehouse == w) pending <- pending + order$backorder
      }
      emit(inv, 2, w, "skus", digits(skus), "qty", digits(stock_quantity(stocks)),
           "value", money(stock_value(stocks)), "backorder", digits(pending))
    }
    if (length(names_sorted(inv$stock)) == 0) emit(inv, 2, "(none)")

  } else if (cmd == "SUMMARY") {
    emit(inv, 0, "SUMMARY")
    for (category in categories) {
      total <- inv$totals[[category]]
      emit(inv, 2, category, "qty", digits(total$quantity),
           "value", money(total$value))
    }
    stocks <- all_stocks(inv)
    emit(inv, 2, "on-hand", "qty", digits(stock_quantity(stocks)),
         "value", money(stock_value(stocks)))
    open <- 0
    pending <- 0
    for (order in inv$orders) {
      if (order$backorder > 0) open <- open + 1
      pending <- pending + order$backorder
    }
    emit(inv, 2, "orders", digits(length(inv$orders)),
         "open", digits(open), "backorder", digits(pending))
  }
}

execute <- function(inv, line) {
  tokens <- strsplit(line, " ", fixed = TRUE)[[1]]
  cmd <- tokens[1]
  args <- tokens[-1]
  tryCatch(
    command(inv, cmd, args),
    command_error = function(err) emit(inv, 0, "ERROR", err$message)
  )
}

input <- readLines(stdin(), warn = FALSE)
n <- as.integer(input[1])
inv <- inventory()
for (i in seq_len(n)) {
  execute(inv, input[i + 1])
}
cat(paste(inv$output, collapse = "\n"), "\n", sep = "")
