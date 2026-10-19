stations_order <- c("GRILL", "FRY", "COLD", "BAR")
courses <- c("DRINK", "STARTER", "MAIN", "DESSERT")

object <- function(...) list2env(list(...), parent = emptyenv())
number <- function(text) as.numeric(text)
cents <- function(text) as.numeric(gsub(".", "", text, fixed = TRUE))
integer_text <- function(value) format(value, scientific = FALSE, trim = TRUE)
money <- function(value) {
  whole <- floor(value / 100)
  paste0(integer_text(whole), ".", sprintf("%02d", as.integer(value %% 100)))
}
clock <- function(time) {
  minutes <- 660 + time
  sprintf("%02d:%02d", as.integer(floor(minutes / 60)), as.integer(minutes %% 60))
}
rounded <- function(amount, rate) floor((amount * rate + 50) / 100)
fail <- function(reason) stop(reason, call. = FALSE)

state <- object(
  now = 0, tables = list(), servers = list(), waiting = list(),
  menu = list(), lines = list(), stations = list(),
  happy_rate = 0, happy_end = 0, covers = 0, parties = 0,
  turns = 0, stay = 0,
  sales = setNames(rep(0, length(courses)), courses),
  totals = setNames(rep(0, 5), c("subtotal", "discount", "service", "tax", "total")),
  payments = c(CASH = 0, CARD = 0), tips = 0,
  comps = 0, comp_amount = 0, voids = 0,
  served = numeric(), output = character()
)
for (name in stations_order) {
  state$stations[[name]] <- object(
    name = name, capacity = if (name == "BAR") 2 else 1,
    up = TRUE, queue = list(), cooking = list(),
    tickets = numeric(), remakes = 0
  )
}

emit <- function(...) {
  arguments <- list(...)
  parts <- unlist(lapply(arguments, function(value) {
    if (is.numeric(value)) vapply(value, integer_text, character(1))
    else as.character(value)
  }), use.names = FALSE)
  state$output <- c(state$output, paste(parts, collapse = " "))
}

get_table <- function(text) {
  item <- state$tables[[as.character(number(text))]]
  if (is.null(item)) fail(paste("unknown table", text))
  item
}

get_check <- function(text) {
  item <- get_table(text)
  if (is.null(item$check)) fail(paste("table", text, "is free"))
  item$check
}

unlocked <- function(check) {
  if (check$paid > 0) fail(paste("check for table", check$table$number, "is locked"))
}

get_line <- function(text) {
  id <- number(text)
  if (id < 1 || id > length(state$lines)) fail(paste("unknown line", text))
  state$lines[[id]]
}

modifiable <- function(line) {
  if (line$status == "VOID") fail(paste0("#", line$id, " is void"))
  if (line$check$closed) fail(paste0("#", line$id, " is on a closed check"))
  unlocked(line$check)
}

active_lines <- function(check) {
  Filter(function(line) line$status != "VOID", check$lines)
}

unserved <- function(check) {
  count <- sum(vapply(active_lines(check), function(line) line$status != "SERVED", logical(1)))
  if (count > 0) fail(paste("table", check$table$number, "has", count, "unserved items"))
}

get_station <- function(name) {
  station <- state$stations[[name]]
  if (is.null(station)) fail(paste("unknown station", name))
  station
}

require_course <- function(name) {
  if (!(name %in% courses)) fail(paste("unknown course", name))
}

get_item <- function(name) {
  item <- state$menu[[name]]
  if (is.null(item)) fail(paste("unknown item", name))
  item
}

load_server <- function(server) {
  sum(vapply(state$tables, function(item)
    !is.null(item$check) && identical(item$check$server, server), logical(1)))
}

select_table <- function(size) {
  tables <- Filter(function(item) is.null(item$check) && item$seats >= size,
                   state$tables)
  if (!length(tables)) return(NULL)
  indexes <- order(
    vapply(tables, function(item) item$seats, numeric(1)),
    vapply(tables, function(item) item$number, numeric(1))
  )
  tables[[indexes[1]]]
}

seat_party <- function(party, size, table) {
  loads <- vapply(state$servers, load_server, numeric(1))
  server <- state$servers[[which.min(loads)]]
  check <- object(
    party = party, size = size, table = table,
    server = server, seated = state$now,
    lines = list(), paid = 0, discount = 0, closed = FALSE
  )
  table$check <- check
  server$parties <- server$parties + 1
  state$covers <- state$covers + size
  state$parties <- state$parties + 1
  check
}

process_waiting <- function() {
  remaining <- list()
  for (entry in state$waiting) {
    table <- select_table(entry$size)
    if (is.null(table)) {
      remaining[[length(remaining) + 1]] <- entry
    } else {
      check <- seat_party(entry$party, entry$size, table)
      emit("SEATED", entry$party, entry$size, "table", table$number,
           "server", check$server$name, "waited", state$now - entry$joined)
    }
  }
  state$waiting <- remaining
}

line_amount <- function(line) {
  if (is.null(line$reason)) line$price * line$quantity else 0
}

check_amounts <- function(check) {
  subtotal <- sum(vapply(active_lines(check), line_amount, numeric(1)))
  discount <- rounded(subtotal, check$discount)
  after <- subtotal - discount
  service <- if (check$size >= 6) rounded(after, 18) else 0
  tax <- rounded(after, 8)
  total <- after + service + tax
  c(subtotal = subtotal, discount = discount, service = service,
    tax = tax, total = total, due = total - check$paid)
}

close_check <- function(check) {
  amounts <- check_amounts(check)
  state$turns <- state$turns + 1
  state$stay <- state$stay + state$now - check$seated
  for (line in active_lines(check)) {
    state$sales[line$course] <- state$sales[line$course] + line_amount(line)
  }
  for (field in names(state$totals)) {
    state$totals[field] <- state$totals[field] + amounts[field]
  }
  check$server$sales <- check$server$sales + amounts["total"]
  check$closed <- TRUE
  check$table$check <- NULL
  emit("FREE", "table", check$table$number, check$party,
       "stayed", state$now - check$seated)
  process_waiting()
}

start_station <- function(station, time) {
  while (station$up && length(station$queue) &&
         length(station$cooking) < station$capacity) {
    line <- station$queue[[1]]
    station$queue <- station$queue[-1]
    line$status <- "COOKING"
    line$ready <- time + line$prep
    line$started <- TRUE
    station$cooking[[length(station$cooking) + 1]] <- line
  }
}

tick <- function(minutes) {
  finish <- state$now + minutes
  emit("TICK", clock(finish))
  repeat {
    cooking <- unlist(lapply(state$stations, function(station) station$cooking),
                      recursive = FALSE)
    if (!length(cooking)) break
    time <- min(vapply(cooking, function(line) line$ready, numeric(1)))
    if (time > finish) break
    for (name in stations_order) {
      station <- state$stations[[name]]
      finished <- Filter(function(line) line$ready == time, station$cooking)
      station$cooking <- Filter(function(line) line$ready != time, station$cooking)
      if (length(finished)) {
        finished <- finished[order(vapply(finished, function(line) line$id, numeric(1)))]
      }
      for (line in finished) {
        line$status <- "READY"
        station$tickets <- c(station$tickets, time - line$fire)
        emit("READY", clock(time), name, paste0("#", line$id),
             line$item, paste0("x", line$quantity),
             "table", line$check$table$number, "seat", line$seat)
      }
    }
    for (name in stations_order) start_station(state$stations[[name]], time)
  }
  state$now <- finish
}

seat_totals <- function(check) {
  lines <- active_lines(check)
  if (!length(lines)) return(setNames(numeric(), character()))
  seats <- sort(unique(vapply(lines, function(line) line$seat, numeric(1))))
  setNames(vapply(seats, function(seat)
    sum(vapply(Filter(function(line) line$seat == seat, lines),
               line_amount, numeric(1))), numeric(1)), as.character(seats))
}

allocate <- function(values, rate) {
  result <- floor(values * rate / 100)
  left <- rounded(sum(values), rate) - sum(result)
  if (left > 0 && length(values)) {
    seats <- as.numeric(names(values))
    sorted <- order(-(values * rate %% 100), seats)
    for (index in head(sorted, left)) result[index] <- result[index] + 1
  }
  result
}

show_bill <- function(check) {
  emit("BILL", "table", check$table$number, check$party, "guests", check$size)
  seat_values <- seat_totals(check)
  for (seat in names(seat_values)) {
    emit("SEAT", seat, money(seat_values[[seat]]))
    for (line in active_lines(check)) {
      if (as.character(line$seat) != seat) next
      if (is.null(line$reason)) {
        emit(paste0("#", line$id), line$item, paste0("x", line$quantity),
             money(line_amount(line)))
      } else {
        emit(paste0("#", line$id), line$item, paste0("x", line$quantity),
             money(line_amount(line)), "COMP", line$reason)
      }
    }
  }
  a <- check_amounts(check)
  emit("SUBTOTAL", money(a["subtotal"]))
  if (check$discount != 0)
    emit("DISCOUNT", paste0(check$discount, "%"), money(a["discount"]))
  if (check$size >= 6) emit("SERVICE", money(a["service"]))
  emit("TAX", money(a["tax"]))
  emit("TOTAL", money(a["total"]))
  if (check$paid > 0) {
    emit("PAID", money(check$paid))
    emit("DUE", money(a["due"]))
  }
}

show_report <- function() {
  emit("REPORT", clock(state$now))
  emit("COVERS", state$covers, "parties", state$parties)
  emit("TURNS", state$turns, "avg_stay",
       if (state$turns > 0) floor(state$stay / state$turns) else "-")
  sales <- c("SALES")
  for (course in courses) sales <- c(sales, course, money(state$sales[course]))
  emit(sales)
  totals <- c("TOTALS")
  for (field in names(state$totals)) totals <- c(totals, field, money(state$totals[field]))
  emit(totals)
  emit("PAYMENTS", "cash", money(state$payments["CASH"]),
       "card", money(state$payments["CARD"]), "tips", money(state$tips))
  emit("COMPS", state$comps, money(state$comp_amount), "VOIDS", state$voids)
  if (length(state$served)) {
    names <- names(state$served)
    ranked <- order(-as.numeric(state$served), names)
    for (index in seq_len(min(3, length(ranked)))) {
      item <- ranked[index]
      emit("TOP", index, names[item], state$served[item])
    }
  }
  for (name in stations_order) {
    station <- state$stations[[name]]
    tickets <- station$tickets
    emit(name, "tickets", length(tickets), "avg",
         if (length(tickets)) floor(sum(tickets) / length(tickets)) else "-",
         "max", if (length(tickets)) max(tickets) else "-",
         "remakes", station$remakes)
  }
  for (server in state$servers) {
    emit("SERVER", server$name, "tables", load_server(server),
         "parties", server$parties, "sales", money(server$sales),
         "tips", money(server$tips))
  }
}

run_command <- function(command, a) {
  if (command == "TABLE") {
    id <- number(a[1])
    if (!is.null(state$tables[[as.character(id)]]))
      fail(paste("table", a[1], "already exists"))
    table <- object(number = id, seats = number(a[2]), check = NULL)
    state$tables[[as.character(id)]] <- table
    emit("TABLE", id, "seats", table$seats)
    process_waiting()
  } else if (command == "STAFF") {
    if (any(vapply(state$servers, function(server) server$name == a[1], logical(1))))
      fail(paste(a[1], "is already on duty"))
    state$servers[[length(state$servers) + 1]] <-
      object(name = a[1], parties = 0, sales = 0, tips = 0)
    emit("STAFF", a[1])
  } else if (command == "SEAT") {
    for (table in state$tables) {
      if (!is.null(table$check) && table$check$party == a[1])
        fail(paste(a[1], "is already seated at table", table$number))
    }
    for (entry in state$waiting) {
      if (entry$party == a[1]) fail(paste(a[1], "is already waiting"))
    }
    size <- number(a[2])
    if (!any(vapply(state$tables, function(table) table$seats >= size, logical(1))))
      fail(paste("no table for party of", size))
    if (!length(state$servers)) fail("no server on duty")
    table <- select_table(size)
    if (is.null(table)) {
      state$waiting[[length(state$waiting) + 1]] <-
        list(party = a[1], size = size, joined = state$now)
      emit("WAIT", a[1], size, "position", length(state$waiting))
    } else {
      check <- seat_party(a[1], size, table)
      emit("SEAT", a[1], size, "table", table$number, "server", check$server$name)
    }
  } else if (command == "CANCEL") {
    index <- which(vapply(state$waiting, function(entry) entry$party == a[1], logical(1)))
    if (!length(index)) fail(paste(a[1], "is not waiting"))
    entry <- state$waiting[[index[1]]]
    state$waiting <- state$waiting[-index[1]]
    emit("CANCEL", entry$party, entry$size, "waited", state$now - entry$joined)
  } else if (command == "MOVE") {
    source <- get_table(a[1])
    destination <- get_table(a[2])
    if (is.null(source$check)) fail(paste("table", a[1], "is free"))
    if (!is.null(destination$check)) fail(paste("table", a[2], "is occupied"))
    check <- source$check
    if (destination$seats < check$size)
      fail(paste("table", a[2], "is too small for", check$party))
    source$check <- NULL
    destination$check <- check
    check$table <- destination
    emit("MOVE", check$party, "table", source$number, "->", destination$number)
    process_waiting()
  } else if (command == "MENU") {
    get_station(a[2])
    require_course(a[5])
    old <- state$menu[[a[1]]]
    item <- object(
      name = a[1], station = a[2], prep = number(a[3]),
      price = cents(a[4]), course = a[5],
      stock = if (is.null(old)) NULL else old$stock
    )
    state$menu[[a[1]]] <- item
    emit("MENU", if (is.null(old)) "ADD" else "UPDATE",
         a[1], a[2], item$prep, money(item$price), a[5])
  } else if (command == "STOCK") {
    item <- get_item(a[1])
    item$stock <- number(a[2])
    emit("STOCK", item$name, item$stock)
  } else if (command == "HAPPY") {
    state$happy_rate <- number(a[1])
    state$happy_end <- state$now + number(a[2])
    emit("HAPPY", paste0(state$happy_rate, "%"), "until", clock(state$happy_end))
  } else if (command == "ITEMS") {
    items <- unname(state$menu)
    if (length(items)) {
      ord <- order(
        vapply(items, function(item) match(item$course, courses), integer(1)),
        vapply(items, function(item) item$name, character(1))
      )
      items <- items[ord]
    }
    emit("ITEMS", length(items))
    for (item in items)
      emit(item$course, item$name, item$station, item$prep, money(item$price),
           if (is.null(item$stock)) "-" else item$stock)
  } else if (command == "ORDER") {
    check <- get_check(a[1])
    unlocked(check)
    seat <- number(a[2])
    if (seat > check$size)
      fail(paste("seat", seat, "out of range for table", a[1]))
    item <- get_item(a[3])
    quantity <- number(a[4])
    if (!is.null(item$stock) && item$stock < quantity)
      fail(paste("only", item$stock, item$name, "left"))
    happy <- item$course == "DRINK" && state$now < state$happy_end
    price <- item$price - if (happy) rounded(item$price, state$happy_rate) else 0
    line <- object(
      id = length(state$lines) + 1, check = check, seat = seat,
      item = item$name, quantity = quantity, station = item$station,
      prep = item$prep, price = price, course = item$course,
      status = "ORDERED", reason = NULL, fire = 0, ready = 0, started = FALSE
    )
    state$lines[[length(state$lines) + 1]] <- line
    check$lines[[length(check$lines) + 1]] <- line
    if (happy) {
      emit("ORDER", paste0("#", line$id), "table", check$table$number, "seat", seat,
           item$name, paste0("x", quantity), money(line_amount(line)), "HAPPY")
    } else {
      emit("ORDER", paste0("#", line$id), "table", check$table$number, "seat", seat,
           item$name, paste0("x", quantity), money(line_amount(line)))
    }
    if (!is.null(item$stock)) {
      item$stock <- item$stock - quantity
      if (item$stock == 0) emit("SOLDOUT", item$name)
    }
  } else if (command == "FIRE") {
    check <- get_check(a[1])
    require_course(a[2])
    lines <- Filter(function(line) line$course == a[2] && line$status == "ORDERED",
                    check$lines)
    if (!length(lines)) fail(paste("nothing to fire for", a[2], "at table", a[1]))
    if (a[2] %in% c("MAIN", "DESSERT")) {
      earlier <- if (a[2] == "MAIN") "STARTER" else c("STARTER", "MAIN")
      for (previous in earlier) {
        if (any(vapply(check$lines, function(line)
            line$course == previous && line$status == "ORDERED", logical(1))))
          fail(paste("fire", previous, "first"))
      }
    }
    for (line in lines) {
      line$status <- "QUEUED"
      line$fire <- state$now
      station <- state$stations[[line$station]]
      station$queue[[length(station$queue) + 1]] <- line
    }
    emit("FIRE", "table", check$table$number, a[2],
         vapply(lines, function(line) paste0("#", line$id), character(1)))
    for (name in stations_order) start_station(state$stations[[name]], state$now)
  } else if (command == "TICK") {
    tick(number(a[1]))
  } else if (command == "SERVE") {
    check <- get_check(a[1])
    lines <- Filter(function(line) line$status == "READY", check$lines)
    if (!length(lines)) fail(paste("nothing ready for table", a[1]))
    for (line in lines) {
      line$status <- "SERVED"
      if (is.na(match(line$item, names(state$served))))
        state$served[line$item] <- 0
      state$served[line$item] <- state$served[line$item] + line$quantity
    }
    emit("SERVE", "table", check$table$number,
         vapply(lines, function(line) paste0("#", line$id), character(1)))
  } else if (command == "RUSH") {
    line <- get_line(a[1])
    if (line$status != "QUEUED") fail(paste0("#", line$id, " is not queued"))
    station <- state$stations[[line$station]]
    station$queue <- c(list(line),
                       Filter(function(other) !identical(other, line), station$queue))
    emit("RUSH", paste0("#", line$id), line$station)
  } else if (command == "REMAKE") {
    line <- get_line(a[1])
    if (line$check$closed) fail(paste0("#", line$id, " is on a closed check"))
    if (!(line$status %in% c("READY", "SERVED")))
      fail(paste0("#", line$id, " is not ready or served"))
    line$status <- "QUEUED"
    line$fire <- state$now
    station <- state$stations[[line$station]]
    station$queue <- c(list(line), station$queue)
    station$remakes <- station$remakes + 1
    emit("REMAKE", paste0("#", line$id), line$item, line$station)
    start_station(station, state$now)
  } else if (command == "VOID") {
    line <- get_line(a[1])
    if (line$status == "VOID") fail(paste0("#", line$id, " is already void"))
    if (line$started) fail(paste0("#", line$id, " has already started"))
    if (line$status == "QUEUED") {
      station <- state$stations[[line$station]]
      station$queue <- Filter(function(other) !identical(other, line), station$queue)
    }
    line$status <- "VOID"
    item <- state$menu[[line$item]]
    if (!is.null(item$stock)) item$stock <- item$stock + line$quantity
    state$voids <- state$voids + 1
    emit("VOID", paste0("#", line$id), line$item, paste0("x", line$quantity))
  } else if (command == "STATION") {
    station <- get_station(a[1])
    if (a[2] == "DOWN" && !station$up)
      fail(paste("station", a[1], "is already down"))
    if (a[2] == "UP" && station$up)
      fail(paste("station", a[1], "is not down"))
    station$up <- a[2] == "UP"
    if (station$up) start_station(station, state$now)
    emit("STATION", a[1], a[2])
  } else if (command %in% c("COMP", "TRANSFER")) {
    line <- get_line(a[1])
    modifiable(line)
    if (command == "COMP") {
      if (!is.null(line$reason)) fail(paste0("#", line$id, " is already comped"))
      value <- line_amount(line)
      emit("COMP", paste0("#", line$id), line$item, money(value), a[2])
      state$comps <- state$comps + 1
      state$comp_amount <- state$comp_amount + value
      line$reason <- a[2]
    } else {
      seat <- number(a[2])
      if (seat > line$check$size)
        fail(paste("seat", seat, "out of range for table", line$check$table$number))
      if (seat == line$seat)
        fail(paste0("#", line$id, " is already on seat ", seat))
      emit("TRANSFER", paste0("#", line$id), "seat", line$seat, "->", seat)
      line$seat <- seat
    }
  } else if (command == "DISCOUNT") {
    check <- get_check(a[1])
    unlocked(check)
    check$discount <- number(a[2])
    emit("DISCOUNT", "table", check$table$number, paste0(check$discount, "%"))
  } else if (command == "BILL") {
    show_bill(get_check(a[1]))
  } else if (command == "SPLIT") {
    check <- get_check(a[1])
    amounts <- check_amounts(check)
    if (amounts["due"] == 0) fail(paste("nothing to split for table", a[1]))
    if (a[2] == "EVEN") {
      count <- number(a[3])
      if (count > check$size)
        fail(paste("cannot split table", a[1], count, "ways"))
      emit("SPLIT", "table", check$table$number, "EVEN", count,
           "due", money(amounts["due"]))
      quotient <- floor(amounts["due"] / count)
      remainder <- amounts["due"] %% count
      for (i in seq_len(count))
        emit("PAYER", i, money(quotient + if (i <= remainder) 1 else 0))
    } else {
      if (check$paid > 0) fail(paste("table", a[1], "has payments"))
      values <- seat_totals(check)
      discounts <- allocate(values, check$discount)
      after <- values - discounts
      services <- allocate(after, if (check$size >= 6) 18 else 0)
      taxes <- allocate(after, 8)
      emit("SPLIT", "table", check$table$number, "BYSEAT",
           "total", money(amounts["total"]))
      for (seat in names(values)) {
        emit("SEAT", seat, "subtotal", money(values[[seat]]),
             "discount", money(discounts[[seat]]),
             "service", money(services[[seat]]), "tax", money(taxes[[seat]]),
             "total", money(after[[seat]] + services[[seat]] + taxes[[seat]]))
      }
    }
  } else if (command == "PAY") {
    check <- get_check(a[1])
    if (!(a[2] %in% c("CASH", "CARD")))
      fail(paste("unknown method", a[2]))
    unserved(check)
    due <- check_amounts(check)["due"]
    if (due == 0) fail(paste("nothing to pay for table", a[1]))
    value <- cents(a[3])
    applied <- min(value, due)
    check$paid <- check$paid + applied
    state$payments[a[2]] <- state$payments[a[2]] + applied
    if (value < due) {
      emit("PAY", "table", check$table$number, a[2], money(value),
           "remaining", money(due - value))
    } else {
      emit("PAY", "table", check$table$number, a[2], money(value),
           if (a[2] == "CASH") "change" else "tip", money(value - due))
      if (a[2] == "CARD") {
        state$tips <- state$tips + value - due
        check$server$tips <- check$server$tips + value - due
      }
      close_check(check)
    }
  } else if (command == "CLOSE") {
    check <- get_check(a[1])
    unserved(check)
    due <- check_amounts(check)["due"]
    if (due != 0) fail(paste("table", a[1], "still owes", money(due)))
    close_check(check)
  } else if (command == "STATUS") {
    check <- get_check(a[1])
    emit("STATUS", "table", check$table$number, check$party,
         "guests", check$size, "since", clock(check$seated))
    for (line in check$lines) {
      fields <- c(paste0("#", line$id), "seat", line$seat, line$item,
                  paste0("x", line$quantity), line$course, line$status)
      if (line$status == "COOKING") fields <- c(fields, "until", clock(line$ready))
      if (!is.null(line$reason)) fields <- c(fields, "COMP", line$reason)
      emit(fields)
    }
  } else if (command == "KITCHEN") {
    emit("KITCHEN", clock(state$now))
    for (name in stations_order) {
      station <- state$stations[[name]]
      cooking <- station$cooking
      if (length(cooking)) {
        ord <- order(
          vapply(cooking, function(line) line$ready, numeric(1)),
          vapply(cooking, function(line) line$id, numeric(1))
        )
        cooking <- cooking[ord]
      }
      cooking_text <- if (length(cooking))
        paste(vapply(cooking, function(line)
          paste0("#", line$id, "@", clock(line$ready)), character(1)), collapse = " ")
        else "-"
      queue_text <- if (length(station$queue))
        paste(vapply(station$queue, function(line)
          paste0("#", line$id), character(1)), collapse = " ")
        else "-"
      emit(name, if (station$up) "up" else "down",
           "cooking", cooking_text, "queue", queue_text)
    }
  } else if (command == "FLOOR") {
    tables <- unname(state$tables)
    if (length(tables))
      tables <- tables[order(vapply(tables, function(table) table$number, numeric(1)))]
    free <- sum(vapply(tables, function(table) is.null(table$check), logical(1)))
    emit("FLOOR", clock(state$now), "free", free,
         "seated", length(tables) - free, "waiting", length(state$waiting))
    for (table in tables) {
      check <- table$check
      if (is.null(check)) {
        emit("table", table$number, "seats", table$seats, "free")
      } else {
        fields <- c("table", table$number, "seats", table$seats,
                    check$party, "guests", check$size, "server", check$server$name,
                    "since", clock(check$seated), "items", length(active_lines(check)),
                    "total", money(check_amounts(check)["total"]))
        if (check$paid > 0) fields <- c(fields, "paid", money(check$paid))
        emit(fields)
      }
    }
    for (i in seq_along(state$waiting)) {
      entry <- state$waiting[[i]]
      emit("WAITING", i, entry$party, entry$size, "since", clock(entry$joined))
    }
  } else if (command == "REPORT") {
    show_report()
  }
}

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(lines[1])
for (i in seq_len(count)) {
  words <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  tryCatch(
    run_command(command, arguments),
    error = function(e) {
      reason <- conditionMessage(e)
      if (grepl("^(unknown table|table |check for table |unknown line |#|unknown station |unknown course |unknown item |seat |only |no table for party |no server on duty|nothing |fire |station |cannot split|is already |[A-Za-z0-9_]+ is already|[A-Za-z0-9_]+ is not waiting)", reason)) {
        emit("ERROR", reason)
      } else {
        stop(e)
      }
    }
  )
}
if (length(state$output)) cat(paste(state$output, collapse = "\n"), "\n", sep = "")
