classes_all <- c("F", "J", "Y")
tier_order <- c(PLATINUM = 0L, GOLD = 1L, SILVER = 2L, NONE = 3L)
object <- function(...) list2env(list(...), parent = emptyenv())
registry <- function() new.env(hash = TRUE, parent = emptyenv())
aircraft <- registry()
flights <- registry()
bookings <- registry()
used_pnr <- registry()
people <- registry()
statuses <- registry()
flight_order <- character()
person_count <- 0L
definition <- NULL
fail <- function(message) stop(message, call. = FALSE)
ints <- function(a, b) if (a <= b) seq.int(a, b) else integer()
person <- function(id) people[[as.character(id)]]
tier <- function(p) if (is.null(statuses[[p$name]])) "NONE" else statuses[[p$name]]
members <- function(b) b$people[vapply(b$people, function(id) person(id)$active, logical(1L))]
passengers <- function(f) f$people[vapply(f$people, function(id) person(id)$active, logical(1L))]
passenger_result <- function(p) {
  if (p$type == "INFANT") return("LAP")
  if (p$seat == "") return("UNASSIGNED")
  p$seat
}
get_flight <- function(id, open = FALSE) {
  f <- flights[[id]]
  if (is.null(f)) fail(paste("unknown flight", id))
  if (open && f$closed) fail(paste("flight", id, "is closed"))
  f
}
get_booking <- function(pnr, open = FALSE) {
  b <- bookings[[pnr]]
  if (is.null(b) || !length(members(b))) fail(paste("unknown PNR", pnr))
  get_flight(b$flight, open)
  b
}
get_person <- function(b, name) {
  for (id in members(b)) {
    if (person(id)$name == name) return(person(id))
  }
  fail(paste("no passenger", name, "in", b$pnr))
}
cabin <- function(f, class) {
  c <- f$model$cabins[[class]]
  if (is.null(c)) fail(paste("no cabin", class, "on", f$id))
  c
}
booked <- function(f, class) {
  sum(vapply(passengers(f), function(id) person(id)$type != "INFANT" && person(id)$class == class, logical(1L)))
}
allowed <- function(f, p, seat, class, vacated = integer(), assignments = character()) {
  s <- f$model$seats[[seat]]
  if (is.null(s) || s$class != class || seat %in% f$blocked) return(FALSE)
  occupied <- f$occupied[[seat]]
  if (!is.null(occupied) && !(occupied %in% vacated)) return(FALSE)
  if ((p$type == "CHILD" || p$infant != 0L) && s$row %in% f$model$exits) return(FALSE)
  if (p$infant != 0L) {
    for (other_seat in ls(f$occupied, all.names = TRUE)) {
      id <- f$occupied[[other_seat]]
      if (id == p$id || id %in% vacated || person(id)$infant == 0L) next
      t <- f$model$seats[[other_seat]]
      if (t$row == s$row && t$block == s$block) return(FALSE)
    }
    for (key in names(assignments)) {
      id <- as.integer(key)
      if (id != p$id && person(id)$infant != 0L) {
        t <- f$model$seats[[assignments[[key]]]]
        if (t$row == s$row && t$block == s$block) return(FALSE)
      }
    }
  }
  TRUE
}
select_seat <- function(f, p, class = p$class) {
  first <- ""
  for (seat in f$model$cabins[[class]]$seats) {
    if (allowed(f, p, seat, class)) {
      if (first == "") first <- seat
      if (p$pref != "" && f$model$seats[[seat]]$kind == p$pref) return(seat)
    }
  }
  first
}
move_to <- function(f, p, seat) {
  if (p$seat != "") rm(list = p$seat, envir = f$occupied)
  p$seat <- seat
  if (seat != "") f$occupied[[seat]] <- p$id
}
reassign <- function(f) {
  output <- character()
  for (id in passengers(f)) {
    p <- person(id)
    if (p$type != "INFANT" && p$seat == "") {
      seat <- select_seat(f, p)
      if (seat != "") {
        move_to(f, p, seat)
        output <- c(output, paste("REASSIGNED", p$pnr, p$name, seat))
      }
    }
  }
  output
}
fits <- function(f, ids, seats, class) {
  assignments <- setNames(seats, as.character(ids))
  all(vapply(seq_along(ids), function(i) allowed(f, person(ids[i]), seats[i], class, assignments = assignments), logical(1L)))
}
group_seats <- function(f, ids, class) {
  c <- f$model$cabins[[class]]
  total <- length(ids)
  for (method in c("BLOCK", "ROW")) {
    for (row in ints(c$from, c$to)) {
      blocks <- if (method == "BLOCK") c$blocks else paste(c$blocks, collapse = "")
      for (block in blocks) {
        letters <- strsplit(block, "", fixed = TRUE)[[1L]]
        for (x in ints(1L, length(letters) - total + 1L)) {
          seats <- paste0(row, letters[x + seq_len(total) - 1L])
          if (fits(f, ids, seats, class)) return(list(method = method, seats = seats))
        }
      }
    }
  }
  for (height in ints(2L, total)) {
    width <- (total + height - 1L) %/% height
    rows <- (total + width - 1L) %/% width
    for (row in ints(c$from, c$to - rows + 1L)) {
      for (block in c$blocks) {
        letters <- strsplit(block, "", fixed = TRUE)[[1L]]
        for (x in ints(1L, length(letters) - width + 1L)) {
          j <- seq_len(total) - 1L
          seats <- paste0(row + j %/% width, letters[x + j %% width])
          if (fits(f, ids, seats, class)) return(list(method = "STACK", seats = seats))
        }
      }
    }
  }
  list(method = "SPLIT", seats = character())
}
removal_targets <- function(p) if (p$infant == 0L) p$id else c(p$id, p$infant)
remove_people <- function(f, ids) {
  for (id in ids) {
    p <- person(id)
    if (!p$active) next
    move_to(f, p, "")
    p$active <- FALSE
    p$volunteer <- FALSE
    if (p$type == "INFANT") {
      adult <- person(p$adult)
      adult$infant <- 0L
    }
  }
}
load_text <- function(seated, seats) {
  q <- (seated * 1000L) %/% seats
  paste0(q %/% 10L, ".", q %% 10L, "%")
}
seat_order <- function(f, ids) {
  rows <- vapply(ids, function(id) f$model$seats[[person(id)$seat]]$row, integer(1L))
  letters <- vapply(ids, function(id) f$model$seats[[person(id)$seat]]$letter, character(1L))
  ids[order(rows, letters, method = "radix")]
}
execute <- function(line) {
  t <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- t[1L]
  output <- character()
  emit <- function(lines) output <<- c(output, lines)
  if (command == "AIRCRAFT") {
    definition <<- object(id = t[2L], base = as.integer(t[3L]), limit = as.integer(t[4L]), cabins = registry(), seats = registry(), exits = integer(), blocked = character())
  } else if (command == "CABIN") {
    class <- t[2L]
    blocks <- t[5:length(t)]
    c <- object(from = as.integer(t[3L]), to = as.integer(t[4L]), blocks = blocks, seats = character(), capacity = 0L)
    for (row in ints(c$from, c$to)) {
      for (b in seq_along(blocks)) {
        letters <- strsplit(blocks[b], "", fixed = TRUE)[[1L]]
        for (x in seq_along(letters)) {
          if ((b == 1L && x == 1L) || (b == length(blocks) && x == length(letters))) {
            kind <- "W"
          } else if (x == 1L || x == length(letters)) {
            kind <- "A"
          } else {
            kind <- "M"
          }
          seat <- paste0(row, letters[x])
          definition$seats[[seat]] <- list(row = row, letter = letters[x], class = class, block = b, kind = kind)
          c$seats <- c(c$seats, seat)
        }
      }
    }
    definition$cabins[[class]] <- c
  } else if (command == "EXIT") {
    definition$exits <- as.integer(t[-1L])
  } else if (command == "BLOCKED") {
    definition$blocked <- t[-1L]
  } else if (command == "END") {
    parts <- c("AIRCRAFT", definition$id)
    for (class in classes_all) {
      c <- definition$cabins[[class]]
      if (!is.null(c)) {
        c$capacity <- sum(!(c$seats %in% definition$blocked))
        parts <- c(parts, class, c$capacity)
      }
    }
    aircraft[[definition$id]] <- definition
    emit(paste(parts, collapse = " "))
    definition <<- NULL
  } else if (command == "FLIGHT") {
    if (!is.null(flights[[t[2L]]])) fail(paste("duplicate flight", t[2L]))
    model <- aircraft[[t[3L]]]
    if (is.null(model)) fail(paste("unknown aircraft", t[3L]))
    f <- object(id = t[2L], model = model, blocked = model$blocked, occupied = registry(), limits = list(), closed = FALSE,
                bookings = character(), people = integer(), volunteers = integer())
    parts <- c("FLIGHT", f$id, model$id)
    for (class in classes_all) {
      c <- model$cabins[[class]]
      if (!is.null(c)) {
        f$limits[[class]] <- (c$capacity * (100L + as.integer(t[4L]))) %/% 100L
        parts <- c(parts, class, paste0(c$capacity, "/", f$limits[[class]]))
      }
    }
    flights[[f$id]] <- f
    flight_order <<- c(flight_order, f$id)
    emit(paste(parts, collapse = " "))
  } else if (command == "STATUS") {
    statuses[[t[2L]]] <- t[3L]
    emit(paste("STATUS", t[2L], t[3L]))
  } else if (command == "BOOK") {
    pnr <- t[2L]
    flight <- t[3L]
    class <- t[4L]
    if (!is.null(used_pnr[[pnr]])) fail(paste("duplicate PNR", pnr))
    f <- get_flight(flight, TRUE)
    cabin(f, class)
    parsed <- lapply(t[5:length(t)], function(token) strsplit(token, ":", fixed = TRUE)[[1L]])
    names <- character()
    for (parts in parsed) {
      if (parts[1L] %in% names) fail(paste("duplicate name", parts[1L], "in", pnr))
      names <- c(names, parts[1L])
    }
    aboard <- vapply(passengers(f), function(id) person(id)$name, character(1L))
    for (parts in parsed) {
      if (parts[1L] %in% aboard) fail(paste(parts[1L], "already on", flight))
    }
    types <- vapply(parsed, function(parts) parts[2L], character(1L))
    adults <- sum(types == "ADULT")
    infants <- sum(types == "INFANT")
    if (!adults) fail(paste("no adult in", pnr))
    if (infants > adults) fail(paste("too many infants in", pnr))
    if (booked(f, class) + length(parsed) - infants > f$limits[[class]]) fail(paste("limit exceeded for", flight, class))
    b <- object(pnr = pnr, flight = flight, people = integer(), checked = FALSE)
    adult_ids <- infant_ids <- seat_ids <- integer()
    for (parts in parsed) {
      person_count <<- person_count + 1L
      id <- person_count
      pref <- if (length(parts) == 3L) parts[3L] else ""
      p <- object(id = id, pnr = pnr, name = parts[1L], type = parts[2L], pref = pref, class = class,
                  seat = "", active = TRUE, infant = 0L, adult = 0L, volunteer = FALSE)
      people[[as.character(id)]] <- p
      b$people <- c(b$people, id)
      f$people <- c(f$people, id)
      if (p$type == "ADULT") adult_ids <- c(adult_ids, id)
      if (p$type == "INFANT") infant_ids <- c(infant_ids, id) else seat_ids <- c(seat_ids, id)
    }
    for (index in seq_along(infant_ids)) {
      infant <- person(infant_ids[index])
      adult <- person(adult_ids[index])
      infant$adult <- adult_ids[index]
      adult$infant <- infant_ids[index]
    }
    bookings[[pnr]] <- b
    used_pnr[[pnr]] <- TRUE
    f$bookings <- c(f$bookings, pnr)
    if (length(seat_ids) == 1L) {
      method <- "SINGLE"
      p <- person(seat_ids[1L])
      move_to(f, p, select_seat(f, p))
    } else {
      chosen <- group_seats(f, seat_ids, class)
      method <- chosen$method
      for (index in seq_along(seat_ids)) {
        p <- person(seat_ids[index])
        seat <- if (method == "SPLIT") select_seat(f, p) else chosen$seats[index]
        move_to(f, p, seat)
      }
    }
    results <- vapply(b$people, function(id) paste0(person(id)$name, ":", passenger_result(person(id))), character(1L))
    emit(paste(c("BOOKED", pnr, flight, class, method, results), collapse = " "))
  } else if (command == "FIND") {
    lines <- character()
    for (flight in flight_order) {
      f <- flights[[flight]]
      for (id in passengers(f)) {
        p <- person(id)
        if (p$name == t[2L]) lines <- c(lines, paste(flight, p$pnr, p$class, passenger_result(p), if (f$closed) "CLOSED" else "OPEN"))
      }
    }
    value <- statuses[[t[2L]]]
    if (is.null(value)) value <- "NONE"
    emit(paste("FIND", t[2L], value, length(lines)))
    emit(lines)
  } else if (command %in% c("SEAT", "SWAP", "CANCEL", "CHECKIN", "VOLUNTEER", "INFO")) {
    b <- get_booking(t[2L], command != "INFO")
    f <- flights[[b$flight]]
    if (command == "INFO") {
      emit(paste("INFO", b$pnr, b$flight, length(members(b)), if (b$checked) "CHECKED" else "NOT-CHECKED"))
      for (id in members(b)) {
        p <- person(id)
        emit(paste(p$name, p$type, p$class, passenger_result(p)))
      }
    } else if (command == "CHECKIN") {
      if (b$checked) fail(paste(b$pnr, "already checked in"))
      b$checked <- TRUE
      emit(paste("CHECKIN", b$pnr, length(members(b))))
    } else if (command == "CANCEL") {
      targets <- members(b)
      if (length(t) == 3L) {
        p <- get_person(b, t[3L])
        target_set <- removal_targets(p)
        remaining <- setdiff(members(b), target_set)
        if (length(remaining) && !any(vapply(remaining, function(id) person(id)$type == "ADULT", logical(1L)))) fail(paste(b$pnr, "would have no adult"))
        targets <- members(b)[members(b) %in% target_set]
      }
      names <- vapply(targets, function(id) person(id)$name, character(1L))
      remove_people(f, targets)
      emit(paste(c("CANCELLED", b$pnr, names), collapse = " "))
      emit(reassign(f))
    } else {
      p <- get_person(b, t[3L])
      if (command == "SWAP") {
        b2 <- get_booking(t[4L], TRUE)
        q <- get_person(b2, t[5L])
        if (p$id == q$id) fail(paste("cannot swap", p$name, "with itself"))
        for (passenger in list(p, q)) {
          if (passenger$type == "INFANT") fail(paste("infant", passenger$name, "has no seat"))
        }
        if (b$flight != b2$flight) fail(paste(b$pnr, "and", b2$pnr, "are on different flights"))
        if (p$class != q$class) fail(paste(p$name, "and", q$name, "are in different cabins"))
        for (passenger in list(p, q)) {
          if (passenger$seat == "") fail(paste(passenger$name, "has no seat"))
        }
        vacated <- c(p$id, q$id)
        assignments <- setNames(c(q$seat, p$seat), as.character(vacated))
        if (!allowed(f, p, q$seat, p$class, vacated, assignments) || !allowed(f, q, p$seat, q$class, vacated, assignments)) fail(paste("swap of", p$name, "and", q$name, "breaks seating rules"))
        old_p <- p$seat
        old_q <- q$seat
        move_to(f, p, "")
        move_to(f, q, "")
        move_to(f, p, old_q)
        move_to(f, q, old_p)
        emit(paste("SWAPPED", b$pnr, p$name, p$seat, b2$pnr, q$name, q$seat))
        emit(reassign(f))
      } else if (command == "VOLUNTEER") {
        if (p$type != "ADULT" || p$infant != 0L) fail(paste(p$name, "cannot volunteer"))
        if (p$seat == "") fail(paste(p$name, "has no seat"))
        if (p$volunteer) fail(paste(p$name, "already volunteered"))
        p$volunteer <- TRUE
        f$volunteers <- c(f$volunteers, p$id)
        emit(paste("VOLUNTEER", p$pnr, p$name, p$seat))
      } else {
        seat <- t[4L]
        if (p$type == "INFANT") fail(paste("infant", p$name, "has no seat"))
        s <- f$model$seats[[seat]]
        if (is.null(s) || s$class != p$class) fail(paste("no seat", seat, "in cabin", p$class))
        if (seat %in% f$blocked) fail(paste("seat", seat, "is blocked"))
        if (!is.null(f$occupied[[seat]])) fail(paste("seat", seat, "is occupied"))
        if ((p$type == "CHILD" || p$infant != 0L) && s$row %in% f$model$exits) fail(paste("exit row", s$row, "not allowed for", p$name))
        if (!allowed(f, p, seat, p$class)) fail(paste("infant limit reached at", seat))
        old <- p$seat
        move_to(f, p, seat)
        emit(paste("MOVED", p$pnr, p$name, old, "->", seat))
        emit(reassign(f))
      }
    }
  } else {
    f <- get_flight(t[2L], command %in% c("UPGRADE", "CLOSE", "BLOCK", "UNBLOCK"))
    classes <- classes_all[vapply(classes_all, function(class) !is.null(f$model$cabins[[class]]), logical(1L))]
    if (command == "UPGRADE") {
      total <- 0L
      for (index in ints(1L, length(classes) - 1L)) {
        higher <- classes[index]
        lower <- classes[index + 1L]
        targets <- passengers(f)[vapply(passengers(f), function(id) {
          p <- person(id)
          p$class == lower && p$type == "ADULT" && p$infant == 0L && tier(p) != "NONE"
        }, logical(1L))]
        ranks <- vapply(targets, function(id) tier_order[[tier(person(id))]], integer(1L))
        targets <- targets[order(ranks, targets, method = "radix")]
        for (id in targets) {
          if (booked(f, higher) >= f$limits[[higher]]) break
          p <- person(id)
          seat <- select_seat(f, p, higher)
          if (seat == "") break
          old <- passenger_result(p)
          move_to(f, p, seat)
          p$class <- higher
          total <- total + 1L
          emit(paste("UPGRADED", p$pnr, p$name, lower, old, "->", higher, seat))
        }
      }
      emit(reassign(f))
      emit(paste("UPGRADE", f$id, total))
    } else if (command == "CLOSE") {
      for (pnr in f$bookings) {
        b <- bookings[[pnr]]
        ids <- members(b)
        if (length(ids) && !b$checked) {
          emit(paste("NOSHOW", pnr, length(ids)))
          remove_people(f, ids)
        }
      }
      emit(reassign(f))
      denied <- 0L
      total <- 0L
      rates <- c(F = 500L, J = 300L, Y = 150L)
      for (class in classes) {
        targets <- f$volunteers[vapply(f$volunteers, function(id) {
          p <- person(id)
          p$active && p$volunteer && p$seat != "" && p$class == class
        }, logical(1L))]
        for (id in targets) {
          p <- person(id)
          useful <- FALSE
          for (waiting_id in passengers(f)) {
            waiting <- person(waiting_id)
            if (waiting$type != "INFANT" && waiting$class == class && waiting$seat == "" && allowed(f, waiting, p$seat, class, id)) {
              useful <- TRUE
              break
            }
          }
          if (useful) {
            amount <- rates[[class]]
            emit(paste("DENIED VOLUNTARY", p$pnr, p$name, class, amount))
            remove_people(f, id)
            denied <- denied + 1L
            total <- total + amount
            emit(reassign(f))
          }
        }
      }
      for (id in passengers(f)) {
        p <- person(id)
        if (p$active && p$type != "INFANT" && p$seat == "") {
          amount <- rates[[p$class]] * 2L
          if (p$type == "CHILD") amount <- amount %/% 2L
          emit(paste("DENIED INVOLUNTARY", p$pnr, p$name, p$class, amount))
          remove_people(f, removal_targets(p))
          denied <- denied + 1L
          total <- total + amount
        }
      }
      f$closed <- TRUE
      emit(paste("CLOSED", f$id, "denied", denied, "compensation", total))
    } else if (command %in% c("BLOCK", "UNBLOCK")) {
      seat <- t[3L]
      if (is.null(f$model$seats[[seat]])) fail(paste("no seat", seat, "on", f$id))
      blocked <- seat %in% f$blocked
      if (command == "BLOCK" && blocked) fail(paste("seat", seat, "is blocked"))
      if (command == "UNBLOCK" && !blocked) fail(paste("seat", seat, "is not blocked"))
      emit(paste(command, f$id, seat))
      if (command == "BLOCK") {
        f$blocked <- c(f$blocked, seat)
        if (!is.null(f$occupied[[seat]])) {
          p <- person(f$occupied[[seat]])
          move_to(f, p, "")
          move_to(f, p, select_seat(f, p))
          emit(paste("DISPLACED", p$pnr, p$name, seat, "->", passenger_result(p)))
        }
      } else {
        f$blocked <- setdiff(f$blocked, seat)
      }
      emit(reassign(f))
    } else if (command == "MAP") {
      emit(paste("MAP", f$id))
      for (class in classes) {
        c <- f$model$cabins[[class]]
        emit(paste("CABIN", class))
        emit(paste0("   ", paste(c$blocks, collapse = " ")))
        for (row in ints(c$from, c$to)) {
          blocks <- character()
          for (block in c$blocks) {
            marks <- character()
            for (letter in strsplit(block, "", fixed = TRUE)[[1L]]) {
              seat <- paste0(row, letter)
              if (seat %in% f$blocked) {
                mark <- "#"
              } else if (!is.null(f$occupied[[seat]])) {
                mark <- "X"
              } else {
                mark <- if (row %in% f$model$exits) "E" else "."
              }
              marks <- c(marks, mark)
            }
            blocks <- c(blocks, paste(marks, collapse = ""))
          }
          emit(paste0(sprintf("%2d ", row), paste(blocks, collapse = " ")))
        }
      }
    } else if (command %in% c("MANIFEST", "BOARDING")) {
      seated <- unassigned <- integer()
      infants <- 0L
      for (id in passengers(f)) {
        p <- person(id)
        if (p$type == "INFANT") {
          infants <- infants + 1L
        } else if (p$seat == "") {
          unassigned <- c(unassigned, id)
        } else {
          seated <- c(seated, id)
        }
      }
      if (command == "MANIFEST") {
        seated <- seat_order(f, seated)
        emit(paste("MANIFEST", f$id, "seated", length(seated), "unassigned", length(unassigned), "infants", infants))
        for (id in c(seated, unassigned)) {
          p <- person(id)
          parts <- c(if (p$seat == "") "---" else p$seat, p$class, p$pnr, p$name, p$type)
          if (p$infant != 0L) parts <- c(parts, paste0("+", person(p$infant)$name))
          if (tier(p) != "NONE") parts <- c(parts, tier(p))
          if (bookings[[p$pnr]]$checked) parts <- c(parts, "CHECKED")
          if (p$volunteer) parts <- c(parts, "VOL")
          emit(paste(parts, collapse = " "))
        }
      } else {
        groups <- character(length(seated))
        keys <- matrix(0L, nrow = length(seated), ncol = 5L)
        for (index in seq_along(seated)) {
          p <- person(seated[index])
          s <- f$model$seats[[p$seat]]
          has_infant <- any(vapply(members(bookings[[p$pnr]]), function(id) person(id)$type == "INFANT", logical(1L)))
          letter <- utf8ToInt(s$letter)
          if (has_infant) {
            group <- "PRE"
            key <- c(0L, s$row, letter, 0L, 0L)
          } else if (p$class != "Y") {
            group <- "CABIN"
            key <- c(1L, s$row, letter, 0L, 0L)
          } else if (tier_order[[tier(p)]] <= 1L) {
            group <- "TIER"
            key <- c(2L, s$row, letter, 0L, 0L)
          } else {
            zone <- (s$row - f$model$cabins[["Y"]]$from) %/% 5L + 1L
            group <- paste0("ZONE", zone)
            key <- c(3L, -zone, match(s$kind, c("W", "M", "A")), -s$row, letter)
          }
          groups[index] <- group
          keys[index, ] <- key
        }
        order_ids <- order(keys[, 1L], keys[, 2L], keys[, 3L], keys[, 4L], keys[, 5L], method = "radix")
        emit(paste("BOARDING", f$id, length(seated)))
        for (number in seq_along(order_ids)) {
          index <- order_ids[number]
          p <- person(seated[index])
          emit(paste(number, groups[index], p$seat, p$pnr, p$name))
        }
      }
    } else if (command == "LOADFACTOR") {
      emit(paste("LOADFACTOR", f$id))
      total_seated <- total_seats <- 0L
      for (class in classes) {
        seats <- sum(!(f$model$cabins[[class]]$seats %in% f$blocked))
        seated <- sum(vapply(passengers(f), function(id) person(id)$class == class && person(id)$seat != "", logical(1L)))
        emit(paste(class, paste0(seated, "/", seats), load_text(seated, seats), "booked", paste0(booked(f, class), "/", f$limits[[class]])))
        total_seated <- total_seated + seated
        total_seats <- total_seats + seats
      }
      emit(paste("ALL", paste0(total_seated, "/", total_seats), load_text(total_seated, total_seats)))
    } else if (command == "BALANCE") {
      weight <- moment <- 0L
      for (id in passengers(f)) {
        p <- person(id)
        if (p$seat != "") {
          w <- if (p$type == "ADULT") 80L else 40L
          if (p$infant != 0L) w <- w + 10L
          weight <- weight + w
          moment <- moment + w * (f$model$seats[[p$seat]]$row - f$model$base)
        }
      }
      limit <- f$model$limit
      if (moment < -limit) {
        verdict <- "NOSE-HEAVY"
      } else if (moment > limit) {
        verdict <- "TAIL-HEAVY"
      } else {
        verdict <- "OK"
      }
      emit(paste("BALANCE", f$id, "weight", weight, "moment", moment, "limit", limit, verdict))
    } else if (command == "AVAIL") {
      class <- t[3L]
      c <- cabin(f, class)
      counts <- c(W = 0L, M = 0L, A = 0L, EXIT = 0L)
      free <- 0L
      for (seat in c$seats) {
        if (!(seat %in% f$blocked) && is.null(f$occupied[[seat]])) {
          s <- f$model$seats[[seat]]
          free <- free + 1L
          counts[s$kind] <- counts[s$kind] + 1L
          if (s$row %in% f$model$exits) counts["EXIT"] <- counts["EXIT"] + 1L
        }
      }
      emit(paste("AVAIL", f$id, class, "free", free, "W", counts[["W"]], "M", counts[["M"]], "A", counts[["A"]], "EXIT", counts[["EXIT"]]))
    }
  }
  output
}
input <- file("stdin", open = "r")
count <- as.integer(readLines(input, n = 1L))
for (index in seq_len(count)) {
  line <- readLines(input, n = 1L)
  output <- tryCatch(execute(line), error = function(error) paste("ERROR", conditionMessage(error)))
  if (length(output)) cat(paste(output, collapse = "\n"), "\n", sep = "")
}
close(input)
