ROOM_TYPES <- c("SINGLE", "DOUBLE", "SUITE")
WEEKDAYS <- c("SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI")

fail <- function(message) {
  error <- simpleError(message)
  class(error) <- c("CommandError", class(error))
  stop(error)
}

leap <- function(year) year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0)

month_lengths <- function(year) {
  c(31, if (leap(year)) 29 else 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31)
}

day_number <- function(text) {
  year <- as.numeric(substr(text, 1, 4))
  month <- as.numeric(substr(text, 6, 7))
  day <- as.numeric(substr(text, 9, 10))
  if (year < 2000 || year > 2099 || month < 1 || month > 12)
    fail(paste("invalid date", text))
  lengths <- month_lengths(year)
  if (day < 1 || day > lengths[month])
    fail(paste("invalid date", text))
  count <- 0
  if (year > 2000) {
    for (previous in 2000:(year - 1))
      count <- count + if (leap(previous)) 366 else 365
  }
  count + sum(head(lengths, month - 1)) + day - 1
}

date_text <- function(number) {
  year <- 2000
  repeat {
    length <- if (leap(year)) 366 else 365
    if (number < length) break
    number <- number - length
    year <- year + 1
  }
  month <- 1
  for (length in month_lengths(year)) {
    if (number < length) break
    number <- number - length
    month <- month + 1
  }
  sprintf("%04d-%02d-%02d", year, month, number + 1)
}

date_weekday <- function(day) paste(date_text(day), WEEKDAYS[day %% 7 + 1])

cents <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1]]
  100 * as.numeric(parts[1]) + as.numeric(parts[2])
}

money <- function(value) {
  sprintf("%.0f.%02d", floor(value / 100), as.integer(value %% 100))
}

new_object <- function(...) list2env(list(...), parent = emptyenv())
stored <- function(env, key) exists(key, envir = env, inherits = FALSE)
lookup <- function(env, key) get(key, envir = env, inherits = FALSE)
insert <- function(env, key, value) assign(key, value, envir = env)

state <- new_object(
  today = day_number("2026-01-01"),
  rooms = new.env(hash = TRUE, parent = emptyenv()),
  seasons = list(),
  blocks = new.env(hash = TRUE, parent = emptyenv()),
  reservations = new.env(hash = TRUE, parent = emptyenv()),
  reservation_order = character(),
  waitlist = list(),
  used_ids = new.env(hash = TRUE, parent = emptyenv()),
  occupied = new.env(hash = TRUE, parent = emptyenv()),
  output = character()
)

emit <- function(..., indent = 0) {
  values <- unlist(list(...), use.names = FALSE)
  state$output <- c(state$output,
                    paste0(strrep(" ", indent), paste(values, collapse = " ")))
}

room_numbers <- function() sort(as.numeric(ls(state$rooms)))

require_room <- function(text) {
  key <- as.character(as.numeric(text))
  if (!stored(state$rooms, key)) fail(paste("unknown room", text))
  lookup(state$rooms, key)
}

require_type <- function(kind) {
  if (!(kind %in% ROOM_TYPES)) fail(paste("invalid type", kind))
}

require_unused <- function(id) {
  if (stored(state$used_ids, id)) fail(paste("duplicate reservation", id))
}

reservation <- function(id, status = NULL) {
  if (!stored(state$reservations, id)) fail(paste("unknown reservation", id))
  entry <- lookup(state$reservations, id)
  if (!is.null(status) && entry$status != status)
    fail(paste("invalid status", id, entry$status))
  entry
}

stay <- function(first, last) {
  arrival <- day_number(first)
  departure <- day_number(last)
  if (arrival < state$today) fail(paste("past date", first))
  if (departure <= arrival) fail(paste("invalid range", first, last))
  if (departure - arrival > 30) fail(paste("too long", departure - arrival))
  c(arrival, departure)
}

period <- function(first, last, past_restricted = FALSE, limited = TRUE) {
  start <- day_number(first)
  end <- day_number(last)
  if (past_restricted && start < state$today) fail(paste("past date", first))
  if (end < start) fail(paste("invalid range", first, last))
  if (limited && end - start + 1 > 31) fail(paste("too long", end - start + 1))
  c(start, end)
}

night_key <- function(day, number) paste0(day, ":", number)

night_rate <- function(room, day) {
  percentage <- 100
  if (length(state$seasons)) {
    for (i in rev(seq_along(state$seasons))) {
      entry <- state$seasons[[i]]
      if (entry[1] <= day && day <= entry[2]) {
        percentage <- entry[3]
        break
      }
    }
  }
  floor(room$rate * percentage / 100)
}

price <- function(room, arrival, departure) {
  nights <- list()
  if (arrival < departure) {
    for (day in arrival:(departure - 1))
      nights[[length(nights) + 1]] <- c(day, room$number, night_rate(room, day))
  }
  nights
}

first_unavailable <- function(room, arrival, departure, except_for = NULL) {
  if (arrival >= departure) return(NULL)
  for (day in arrival:(departure - 1)) {
    key <- night_key(day, room$number)
    if (stored(state$blocks, key)) return(day)
    if (stored(state$occupied, key)) {
      entry <- lookup(state$occupied, key)
      if (is.null(except_for) || entry$reservation != except_for$id) return(day)
    }
  }
  NULL
}

free_room <- function(kind, arrival, departure, except_for = NULL) {
  for (number in room_numbers()) {
    room <- require_room(as.character(number))
    if (room$kind == kind &&
        is.null(first_unavailable(room, arrival, departure, except_for))) return(room)
  }
  NULL
}

inhouse <- function(room) {
  for (id in state$reservation_order) {
    entry <- reservation(id)
    if (entry$status == "inhouse" && identical(entry$room, room)) return(entry)
  }
  NULL
}

occupy <- function(entry, nights) {
  for (night in nights) {
    key <- night_key(night[1], night[2])
    insert(state$occupied, key, list(reservation = entry$id, rate = night[3]))
  }
}

release <- function(entry, first = NULL) {
  for (night in entry$nights) {
    if (is.null(first) || night[1] >= first) {
      key <- night_key(night[1], night[2])
      if (stored(state$occupied, key)) rm(list = key, envir = state$occupied)
    }
  }
}

lodging <- function(entry) {
  sum(vapply(entry$nights, function(night) night[3], numeric(1)))
}

first_rate <- function(entry) entry$nights[[1]][3]

create_reservation <- function(id, guest, room, arrival, departure, indent = 0) {
  nights <- price(room, arrival, departure)
  entry <- new_object(
    id = id, guest = guest, room = room, arrival = arrival, departure = departure,
    nights = nights, status = "booked", extras = list(), deposit = 0, paid = 0,
    posting = NULL, fee = 0, penalty = NULL, bill = NULL
  )
  insert(state$reservations, id, entry)
  state$reservation_order <- c(state$reservation_order, id)
  insert(state$used_ids, id, TRUE)
  occupy(entry, nights)
  emit("BOOK", id, guest, "room", room$number, room$kind,
       date_text(arrival), "->", date_text(departure),
       "nights", departure - arrival, "total", money(lodging(entry)),
       indent = indent)
}

guest_total <- function(guest) {
  sum(vapply(state$reservation_order, function(id) {
    entry <- reservation(id)
    if (entry$guest == guest) entry$paid else 0
  }, numeric(1)))
}

tier <- function(guest) {
  points <- floor(guest_total(guest) / 100)
  if (points >= 2000) return("GOLD")
  if (points >= 500) return("SILVER")
  "BRONZE"
}

calculate_bill <- function(entry) {
  charge <- lodging(entry)
  percentage <- switch(tier(entry$guest), GOLD = 10, SILVER = 5, BRONZE = 0)
  discount <- floor(charge * percentage / 100)
  penalty <- if (is.null(entry$penalty)) 0 else entry$penalty[2]
  extras <- sum(vapply(entry$extras, function(value) value[[2]], numeric(1)))
  subtotal <- charge - discount + penalty + extras
  tax <- floor(subtotal / 10)
  c(charge, discount, penalty, extras, tax, subtotal + tax)
}

deposit_parts <- function(entry, amount) {
  if (amount >= entry$deposit)
    return(c("deposit", money(entry$deposit), "due", money(amount - entry$deposit)))
  c("deposit", money(entry$deposit), "refund", money(entry$deposit - amount))
}

check_out <- function(entry, day, indent = 0) {
  if (day < entry$departure) {
    penalty <- NULL
    for (night in entry$nights) {
      if (night[1] == day) {
        penalty <- c(day, night[3])
        break
      }
    }
    entry$penalty <- penalty
    release(entry, day)
    entry$nights <- Filter(function(night) night[1] < day, entry$nights)
    entry$departure <- day
  }
  bill <- calculate_bill(entry)
  entry$bill <- bill
  entry$paid <- bill[6]
  entry$status <- "checkedout"
  entry$posting <- day
  entry$room$clean <- FALSE
  emit("CHECKOUT", entry$id, "nights", length(entry$nights),
       "lodging", money(bill[1]), "discount", money(bill[2]),
       "penalty", money(bill[3]), "extras", money(bill[4]),
       "tax", money(bill[5]), "total", money(bill[6]),
       deposit_parts(entry, bill[6]), indent = indent)
}

process_waitlist <- function() {
  remaining <- list()
  for (entry in state$waitlist) {
    if (entry$arrival < state$today) {
      emit("WAITLIST", entry$id, "expired", indent = 2)
    } else {
      room <- free_room(entry$kind, entry$arrival, entry$departure)
      if (is.null(room)) {
        remaining[[length(remaining) + 1]] <- entry
      } else {
        create_reservation(entry$id, entry$guest, room, entry$arrival,
                           entry$departure, indent = 2)
      }
    }
  }
  state$waitlist <- remaining
}

cmd_room <- function(a) {
  number <- as.numeric(a[1])
  if (stored(state$rooms, as.character(number))) fail(paste("duplicate room", a[1]))
  require_type(a[2])
  room <- new_object(number = number, kind = a[2], rate = cents(a[3]), clean = TRUE)
  insert(state$rooms, as.character(number), room)
  emit("ROOM", a[1], a[2], a[3])
}

cmd_rate <- function(a) {
  room <- require_room(a[1])
  previous <- room$rate
  room$rate <- cents(a[2])
  emit("RATE", a[1], money(previous), "->", a[2])
}

cmd_season <- function(a) {
  dates <- period(a[1], a[2], limited = FALSE)
  state$seasons[[length(state$seasons) + 1]] <- c(dates, as.numeric(a[3]))
  emit("SEASON", length(state$seasons), a[1], "->", a[2], paste0(a[3], "%"))
}

cmd_block <- function(a) {
  room <- require_room(a[1])
  dates <- period(a[2], a[3], past_restricted = TRUE)
  for (day in dates[1]:dates[2]) {
    if (stored(state$occupied, night_key(day, room$number)))
      fail(paste("room unavailable", a[1], date_text(day)))
  }
  added <- 0
  for (day in dates[1]:dates[2]) {
    key <- night_key(day, room$number)
    if (!stored(state$blocks, key)) {
      insert(state$blocks, key, TRUE)
      added <- added + 1
    }
  }
  emit("BLOCK", a[1], a[2], "->", a[3], "added", added)
}

cmd_unblock <- function(a) {
  room <- require_room(a[1])
  dates <- period(a[2], a[3], past_restricted = TRUE)
  removed <- 0
  for (day in dates[1]:dates[2]) {
    key <- night_key(day, room$number)
    if (stored(state$blocks, key)) {
      rm(list = key, envir = state$blocks)
      removed <- removed + 1
    }
  }
  emit("UNBLOCK", a[1], a[2], "->", a[3], "removed", removed)
}

cmd_clean <- function(a) {
  room <- require_room(a[1])
  if (room$clean) fail(paste("already clean", a[1]))
  room$clean <- TRUE
  emit("CLEAN", a[1])
}

cmd_today <- function(a) {
  day <- day_number(a[1])
  if (day < state$today) fail(paste("past date", a[1]))
  emit("TODAY", date_weekday(day))
  departing <- state$reservation_order[vapply(state$reservation_order, function(id) {
    entry <- reservation(id)
    entry$status == "inhouse" && entry$departure < day
  }, logical(1))]
  if (length(departing)) {
    departures <- vapply(departing, function(id) reservation(id)$departure, numeric(1))
    departing <- departing[order(departures, departing)]
  }
  for (id in departing) {
    entry <- reservation(id)
    check_out(entry, entry$departure, indent = 2)
  }
  absent <- state$reservation_order[vapply(state$reservation_order, function(id) {
    entry <- reservation(id)
    entry$status == "booked" && entry$arrival < day
  }, logical(1))]
  if (length(absent)) {
    arrivals <- vapply(absent, function(id) reservation(id)$arrival, numeric(1))
    absent <- absent[order(arrivals, absent)]
  }
  for (id in absent) {
    entry <- reservation(id)
    release(entry)
    entry$fee <- first_rate(entry)
    entry$paid <- entry$fee
    entry$status <- "noshow"
    entry$posting <- entry$arrival
    emit("NOSHOW", entry$id, entry$guest, "fee", money(entry$fee),
         deposit_parts(entry, entry$fee), indent = 2)
  }
  state$today <- day
}

cmd_book <- function(a) {
  require_unused(a[1])
  require_type(a[3])
  dates <- stay(a[4], a[5])
  room <- free_room(a[3], dates[1], dates[2])
  if (is.null(room)) fail(paste("no availability", a[3], a[4], a[5]))
  create_reservation(a[1], a[2], room, dates[1], dates[2])
}

cmd_bookroom <- function(a) {
  require_unused(a[1])
  room <- require_room(a[3])
  dates <- stay(a[4], a[5])
  unavailable <- first_unavailable(room, dates[1], dates[2])
  if (!is.null(unavailable))
    fail(paste("room unavailable", a[3], date_text(unavailable)))
  create_reservation(a[1], a[2], room, dates[1], dates[2])
}

cmd_waitlist <- function(a) {
  require_unused(a[1])
  require_type(a[3])
  dates <- stay(a[4], a[5])
  room <- free_room(a[3], dates[1], dates[2])
  if (!is.null(room)) {
    create_reservation(a[1], a[2], room, dates[1], dates[2])
  } else {
    entry <- list(id = a[1], guest = a[2], kind = a[3],
                  arrival = dates[1], departure = dates[2])
    state$waitlist[[length(state$waitlist) + 1]] <- entry
    insert(state$used_ids, a[1], TRUE)
    emit("WAITLIST", a[1], "queued position", length(state$waitlist))
  }
}

cmd_modify <- function(a) {
  entry <- reservation(a[1], "booked")
  dates <- stay(a[2], a[3])
  room <- entry$room
  choice <- "kept"
  if (!is.null(first_unavailable(room, dates[1], dates[2], entry))) {
    room <- free_room(room$kind, dates[1], dates[2], entry)
    if (is.null(room))
      fail(paste("no availability", entry$room$kind, a[2], a[3]))
    choice <- "reassigned"
  }
  nights <- price(room, dates[1], dates[2])
  release(entry)
  entry$room <- room
  entry$arrival <- dates[1]
  entry$departure <- dates[2]
  entry$nights <- nights
  occupy(entry, nights)
  emit("MODIFY", a[1], "room", room$number, choice, a[2], "->", a[3],
       "nights", dates[2] - dates[1], "total", money(lodging(entry)))
}

cmd_cancel <- function(a) {
  for (i in seq_along(state$waitlist)) {
    if (state$waitlist[[i]]$id == a[1]) {
      state$waitlist <- state$waitlist[-i]
      emit("CANCEL", a[1], "waitlist removed")
      return(invisible(NULL))
    }
  }
  entry <- reservation(a[1], "booked")
  days <- entry$arrival - state$today
  first <- first_rate(entry)
  fee <- if (days >= 7) 0 else if (days >= 1) floor(first / 2) else first
  release(entry)
  entry$fee <- fee
  entry$paid <- fee
  entry$status <- "cancelled"
  entry$posting <- state$today
  emit("CANCEL", a[1], "days", days, "fee", money(fee), deposit_parts(entry, fee))
}

cmd_checkin <- function(a) {
  entry <- reservation(a[1], "booked")
  if (entry$arrival != state$today)
    fail(paste("not arrival date", a[1], date_text(entry$arrival)))
  occupant <- inhouse(entry$room)
  if (!is.null(occupant))
    fail(paste("room occupied", entry$room$number, occupant$id))
  if (!entry$room$clean) fail(paste("room dirty", entry$room$number))
  entry$status <- "inhouse"
  emit("CHECKIN", a[1], entry$guest, "room", entry$room$number,
       "until", date_text(entry$departure))
}

cmd_move <- function(a) {
  entry <- reservation(a[1], "inhouse")
  room <- require_room(a[2])
  previous <- entry$room
  if (identical(room, previous)) fail(paste("same room", a[2]))
  remaining <- Filter(function(night) night[1] >= state$today, entry$nights)
  if (!length(remaining)) fail(paste("no remaining nights", a[1]))
  unavailable <- first_unavailable(room, remaining[[1]][1], entry$departure, entry)
  if (!is.null(unavailable))
    fail(paste("room unavailable", a[2], date_text(unavailable)))
  occupant <- inhouse(room)
  if (!is.null(occupant))
    fail(paste("room occupied", a[2], occupant$id))
  if (!room$clean) fail(paste("room dirty", a[2]))
  release(entry, state$today)
  entry$nights <- lapply(entry$nights, function(night) {
    if (night[1] >= state$today) night[2] <- room$number
    night
  })
  future <- Filter(function(night) night[1] >= state$today, entry$nights)
  occupy(entry, future)
  previous$clean <- FALSE
  entry$room <- room
  emit("MOVE", a[1], previous$number, "->", a[2], "nights", length(remaining))
}

cmd_extend <- function(a) {
  entry <- reservation(a[1], "inhouse")
  departure <- day_number(a[2])
  if (departure <= entry$departure)
    fail(paste("invalid range", date_text(entry$departure), a[2]))
  if (departure - entry$arrival > 30)
    fail(paste("too long", departure - entry$arrival))
  unavailable <- first_unavailable(entry$room, entry$departure, departure, entry)
  if (!is.null(unavailable))
    fail(paste("room unavailable", entry$room$number, date_text(unavailable)))
  nights <- price(entry$room, entry$departure, departure)
  entry$nights <- c(entry$nights, nights)
  occupy(entry, nights)
  entry$departure <- departure
  emit("EXTEND", a[1], "until", a[2], "nights", length(entry$nights),
       "total", money(lodging(entry)))
}

cmd_charge <- function(a) {
  entry <- reservation(a[1], "inhouse")
  value <- cents(a[2])
  if (value == 0) fail("invalid amount")
  entry$extras[[length(entry$extras) + 1]] <- list(a[3], value)
  extras <- sum(vapply(entry$extras, function(row) row[[2]], numeric(1)))
  emit("CHARGE", a[1], a[3], a[2], "extras", money(extras))
}

cmd_pay <- function(a) {
  entry <- reservation(a[1])
  if (!(entry$status %in% c("booked", "inhouse")))
    fail(paste("invalid status", a[1], entry$status))
  amount <- cents(a[2])
  if (amount == 0) fail("invalid amount")
  entry$deposit <- entry$deposit + amount
  emit("PAY", a[1], a[2], "deposit", money(entry$deposit))
}

cmd_checkout <- function(a) check_out(reservation(a[1], "inhouse"), state$today)

cmd_invoice <- function(a) {
  entry <- reservation(a[1])
  room <- entry$room
  emit("INVOICE", a[1], entry$guest, "room", room$number, room$kind, entry$status)
  if (entry$status %in% c("cancelled", "noshow")) {
    label <- if (entry$status == "cancelled") "cancellation" else "noshow"
    emit(label, "fee", money(entry$fee), indent = 2)
    emit("total", money(entry$fee), indent = 2)
    emit(deposit_parts(entry, entry$fee), indent = 2)
    return(invisible(NULL))
  }
  for (night in entry$nights)
    emit(date_weekday(night[1]), "room", night[2], money(night[3]), indent = 2)
  bill <- if (is.null(entry$bill)) calculate_bill(entry) else entry$bill
  emit("lodging", money(bill[1]), indent = 2)
  emit("discount", money(bill[2]), indent = 2)
  if (!is.null(entry$penalty))
    emit("penalty", date_weekday(entry$penalty[1]), money(bill[3]), indent = 2)
  for (extra in entry$extras)
    emit("extra", extra[[1]], money(extra[[2]]), indent = 2)
  emit("tax", money(bill[5]), indent = 2)
  emit("total", money(bill[6]), indent = 2)
  emit(deposit_parts(entry, bill[6]), indent = 2)
}

cmd_avail <- function(a) {
  require_type(a[1])
  dates <- period(a[2], a[3])
  numbers <- Filter(function(number) require_room(as.character(number))$kind == a[1],
                    room_numbers())
  emit("AVAIL", a[1], a[2], "->", a[3])
  for (day in dates[1]:dates[2]) {
    free <- Filter(function(number) {
      key <- night_key(day, number)
      !stored(state$blocks, key) && !stored(state$occupied, key)
    }, numbers)
    emit(date_weekday(day), "free", length(free), free, indent = 2)
  }
}

occupancy_parts <- function(numbers, day) {
  blocked <- sum(vapply(numbers, function(number)
    stored(state$blocks, night_key(day, number)), logical(1)))
  occupied <- sum(vapply(numbers, function(number)
    stored(state$occupied, night_key(day, number)), logical(1)))
  available <- length(numbers) - blocked
  rate <- if (available > 0) paste0(floor(occupied * 100 / available), "%") else "n/a"
  c("rooms", length(numbers), "blocked", blocked, "occupied", occupied, "rate", rate)
}

cmd_occupancy <- function(a) {
  day <- day_number(a[1])
  emit("OCCUPANCY", date_weekday(day), occupancy_parts(room_numbers(), day))
  for (kind in ROOM_TYPES) {
    numbers <- Filter(function(number) require_room(as.character(number))$kind == kind,
                      room_numbers())
    if (length(numbers))
      emit(kind, occupancy_parts(numbers, day), indent = 2)
  }
}

daily_values <- function(day) {
  numbers <- room_numbers()
  available <- length(numbers) - sum(vapply(numbers, function(number)
    stored(state$blocks, night_key(day, number)), logical(1)))
  occupied <- 0
  revenue <- 0
  for (number in numbers) {
    key <- night_key(day, number)
    if (stored(state$occupied, key)) {
      occupied <- occupied + 1
      revenue <- revenue + lookup(state$occupied, key)$rate
    }
  }
  c(available, occupied, revenue)
}

metrics_parts <- function(available, occupied, revenue) {
  rate <- if (available > 0) paste0(floor(occupied * 100 / available), "%") else "n/a"
  average <- if (occupied > 0) money(floor(revenue / occupied)) else "n/a"
  revpar <- if (available > 0) money(floor(revenue / available)) else "n/a"
  c("sold", paste0(occupied, "/", available), "rate", rate,
    "revenue", money(revenue), "adr", average, "revpar", revpar)
}

cmd_stats <- function(a) {
  dates <- period(a[1], a[2])
  totals <- c(0, 0, 0)
  emit("STATS", a[1], "->", a[2])
  for (day in dates[1]:dates[2]) {
    values <- daily_values(day)
    totals <- totals + values
    emit(date_weekday(day), do.call(metrics_parts, as.list(values)), indent = 2)
  }
  emit("total", do.call(metrics_parts, as.list(totals)), indent = 2)
}

cmd_rooms <- function(a) {
  emit("ROOMS", date_weekday(state$today), "rooms", length(room_numbers()))
  for (number in room_numbers()) {
    room <- require_room(as.character(number))
    parts <- c(
      number, room$kind, "base", money(room$rate),
      "tonight", money(night_rate(room, state$today)),
      if (room$clean) "clean" else "dirty"
    )
    occupant <- inhouse(room)
    if (!is.null(occupant)) {
      parts <- c(parts, "occupied", occupant$id)
    } else if (stored(state$blocks, night_key(state$today, number))) {
      parts <- c(parts, "blocked")
    } else {
      parts <- c(parts, "vacant")
    }
    upcoming <- NULL
    for (id in state$reservation_order) {
      entry <- reservation(id)
      if (entry$status == "booked" && identical(entry$room, room) &&
          (is.null(upcoming) || entry$arrival < upcoming$arrival))
        upcoming <- entry
    }
    if (!is.null(upcoming))
      parts <- c(parts, "next", upcoming$id, date_text(upcoming$arrival))
    emit(parts, indent = 2)
  }
}

cmd_list <- function(a) {
  ids <- state$reservation_order[vapply(state$reservation_order, function(id)
    reservation(id)$status == a[1], logical(1))]
  if (length(ids)) {
    arrival <- vapply(ids, function(id) reservation(id)$arrival, numeric(1))
    ids <- ids[order(arrival, ids)]
  }
  emit("LIST", a[1], length(ids))
  for (id in ids) {
    entry <- reservation(id)
    emit(id, entry$guest, "room", entry$room$number,
         date_text(entry$arrival), "->", date_text(entry$departure), indent = 2)
  }
}

cmd_queue <- function(a) {
  emit("QUEUE", length(state$waitlist))
  for (i in seq_along(state$waitlist)) {
    entry <- state$waitlist[[i]]
    emit(i, entry$id, entry$guest, entry$kind,
         date_text(entry$arrival), "->", date_text(entry$departure), indent = 2)
  }
}

cmd_schedule <- function(a) {
  day <- day_number(a[1])
  arrivals <- state$reservation_order[vapply(state$reservation_order, function(id) {
    entry <- reservation(id)
    entry$arrival == day && entry$status != "cancelled"
  }, logical(1))]
  departures <- state$reservation_order[vapply(state$reservation_order, function(id) {
    entry <- reservation(id)
    entry$departure == day && entry$status %in% c("booked", "inhouse", "checkedout")
  }, logical(1))]
  emit("SCHEDULE", date_weekday(day), "arrivals", length(arrivals),
       "departures", length(departures))
  for (id in sort(arrivals)) {
    entry <- reservation(id)
    emit("arrival", id, entry$guest, "room", entry$room$number, entry$status, indent = 2)
  }
  for (id in sort(departures)) {
    entry <- reservation(id)
    emit("departure", id, entry$guest, "room", entry$room$number, entry$status, indent = 2)
  }
}

cmd_guest <- function(a) {
  ids <- state$reservation_order[vapply(state$reservation_order, function(id)
    reservation(id)$guest == a[1], logical(1))]
  if (!length(ids)) fail(paste("unknown guest", a[1]))
  emit("GUEST", a[1])
  for (id in ids) {
    entry <- reservation(id)
    deposit <- entry$status %in% c("booked", "inhouse")
    emit(id, "room", entry$room$number, entry$room$kind,
         date_text(entry$arrival), "->", date_text(entry$departure), entry$status,
         if (deposit) "deposit" else "paid",
         money(if (deposit) entry$deposit else entry$paid), indent = 2)
  }
  total <- guest_total(a[1])
  emit("total paid", money(total), "points", floor(total / 100),
       "tier", tier(a[1]), indent = 2)
}

cmd_revenue <- function(a) {
  dates <- period(a[1], a[2], limited = FALSE)
  totals <- c(0, 0, 0, 0, 0)
  cancellations <- 0
  noshows <- 0
  checkouts <- 0
  cancelled <- 0
  absent <- 0
  for (id in state$reservation_order) {
    entry <- reservation(id)
    if (is.null(entry$posting) ||
        entry$posting < dates[1] || entry$posting > dates[2]) next
    if (entry$status == "checkedout") {
      totals <- totals + entry$bill[1:5]
      checkouts <- checkouts + 1
    } else if (entry$status == "cancelled") {
      cancellations <- cancellations + entry$fee
      cancelled <- cancelled + 1
    } else if (entry$status == "noshow") {
      noshows <- noshows + entry$fee
      absent <- absent + 1
    }
  }
  emit("REVENUE", a[1], "->", a[2])
  for (i in seq_along(c("lodging", "discount", "penalty", "extras", "tax")))
    emit(c("lodging", "discount", "penalty", "extras", "tax")[i],
         money(totals[i]), indent = 2)
  emit("cancellation", money(cancellations), indent = 2)
  emit("noshow", money(noshows), indent = 2)
  total <- totals[1] - totals[2] + sum(totals[3:5]) + cancellations + noshows
  emit("total", money(total), indent = 2)
  emit("checkouts", checkouts, "cancellations", cancelled, "noshows", absent, indent = 2)
}

handlers <- list(
  ROOM = cmd_room, RATE = cmd_rate, SEASON = cmd_season,
  BLOCK = cmd_block, UNBLOCK = cmd_unblock, CLEAN = cmd_clean,
  TODAY = cmd_today, BOOK = cmd_book, BOOKROOM = cmd_bookroom,
  WAITLIST = cmd_waitlist, MODIFY = cmd_modify, CANCEL = cmd_cancel,
  CHECKIN = cmd_checkin, MOVE = cmd_move, EXTEND = cmd_extend,
  CHARGE = cmd_charge, PAY = cmd_pay, CHECKOUT = cmd_checkout,
  INVOICE = cmd_invoice, AVAIL = cmd_avail, OCCUPANCY = cmd_occupancy,
  STATS = cmd_stats, ROOMS = cmd_rooms, LIST = cmd_list,
  QUEUE = cmd_queue, SCHEDULE = cmd_schedule, GUEST = cmd_guest,
  REVENUE = cmd_revenue
)

execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  tryCatch(
    handlers[[command]](arguments),
    error = function(e) {
      if (!inherits(e, "CommandError")) stop(e)
      emit("ERROR", conditionMessage(e))
    }
  )
  process_waitlist()
}

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(lines[1])
for (i in seq_len(count)) execute(lines[i + 1])
if (length(state$output)) cat(paste0(paste(state$output, collapse = "\n"), "\n"))
