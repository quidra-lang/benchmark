suppressPackageStartupMessages(library(gmp))

zero <- as.bigz(0L)

fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("bookkeeping_error", "error", "condition")))
}

emit <- function(...) cat(paste(...), "\n", sep = "")

money <- function(amount) {
  magnitude <- abs(amount)
  fraction <- as.character(magnitude %% 100L)
  paste0(if (amount < 0L) "-" else "", as.character(magnitude %/% 100L),
         ".", if (nchar(fraction) == 1L) "0" else "", fraction)
}

parse_cents <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1]]
  as.bigz(as.integer(parts[1])) * 100L + as.integer(parts[2])
}

sum_big <- function(values) {
  if (!length(values)) return(zero)
  sum(c_bigz(values))
}

leap <- function(year) year %% 4L == 0L && (year %% 100L != 0L || year %% 400L == 0L)

month_length <- function(year, month) {
  lengths <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)
  lengths[month] + as.integer(month == 2L && leap(year))
}

day_number <- function(year, month, day) {
  prior <- year - 1L
  result <- 365L * prior + prior %/% 4L - prior %/% 100L + prior %/% 400L + day - 730120L
  for (m in seq_len(month - 1L)) result <- result + month_length(year, m)
  result
}

date_parts <- function(number) {
  year <- 2000L
  while (number >= 365L + as.integer(leap(year))) {
    number <- number - 365L - as.integer(leap(year))
    year <- year + 1L
  }
  month <- 1L
  while (number >= month_length(year, month)) {
    number <- number - month_length(year, month)
    month <- month + 1L
  }
  c(year, month, number + 1L)
}

date_text <- function(number) {
  parts <- date_parts(number)
  sprintf("%04d-%02d-%02d", parts[1], parts[2], parts[3])
}

checked_date <- function(text) {
  parts <- as.integer(strsplit(text, "-", fixed = TRUE)[[1]])
  year <- parts[1]
  month <- parts[2]
  day <- parts[3]
  if (year < 2000L || year > 2099L || month < 1L || month > 12L || day < 1L) {
    fail(paste("invalid date", text))
  }
  if (day > month_length(year, month)) fail(paste("invalid date", text))
  day_number(year, month, day)
}

checked_range <- function(first, last) {
  start <- checked_date(first)
  end <- checked_date(last)
  if (start > end) fail(paste("invalid range", first, last))
  c(start, end)
}

months_after <- function(number, count) {
  parts <- date_parts(number)
  offset <- parts[2] - 1L + count
  year <- parts[1] + offset %/% 12L
  month <- offset %% 12L + 1L
  day_number(year, month, min(parts[3], month_length(year, month)))
}

new_books <- function() {
  books <- new.env(parent = emptyenv())
  books$accounts <- list()
  books$entries <- list()
  books$entry_positions <- list()
  books$templates <- list()
  books$draft <- NULL
  books$closes <- list()
  books$close_count <- 0L
  books$depreciation_count <- 0L
  books$interest_count <- 0L
  books$writeoff_count <- 0L
  books
}

sorted_names <- function(values) sort(names(values), method = "radix")

get_account <- function(books, code, required = NULL) {
  account <- books$accounts[[code]]
  if (is.null(account)) fail(paste("unknown account", code))
  if (!is.null(required) && account$kind != required) fail(paste("wrong type", code, required))
  account
}

get_entry <- function(books, id) {
  index <- books$entry_positions[[id]]
  if (is.null(index)) fail(paste("unknown entry", id))
  index
}

get_template <- function(books, name) {
  pattern <- books$templates[[name]]
  if (is.null(pattern)) fail(paste("unknown template", name))
  pattern
}

active_check <- function(books, codes) {
  for (code in codes) {
    if (!get_account(books, code)$active) fail(paste("inactive account", code))
  }
}

closed_text <- function(books) {
  if (!length(books$closes)) "none" else date_text(tail(books$closes, 1L)[[1]]$day)
}

check_closed <- function(books, day) {
  if (length(books$closes) && day <= tail(books$closes, 1L)[[1]]$day) {
    fail(paste("period closed", date_text(day)))
  }
}

ancestors <- function(books, code) {
  codes <- sorted_names(books$accounts)
  codes[codes != code & startsWith(code, codes)]
}

parent_code <- function(books, code) {
  parents <- ancestors(books, code)
  if (length(parents)) tail(parents, 1L) else "none"
}

top_account <- function(books, code) {
  parents <- ancestors(books, code)
  if (length(parents)) parents[1] else code
}

posting_line <- function(debit, code, amount, partner = NA_character_) {
  list(debit = debit, code = code, amount = amount, partner = partner)
}

line_difference <- function(line) if (line$debit) line$amount else -line$amount
line_codes <- function(lines) vapply(lines, function(line) line$code, character(1))

line_totals <- function(lines) {
  debit <- sum_big(lapply(lines, function(line) if (line$debit) line$amount else zero))
  credit <- sum_big(lapply(lines, function(line) if (line$debit) zero else line$amount))
  c(debit, credit)
}

total_pair <- function(totals, code) {
  values <- totals[[code]]
  if (is.null(values)) rep(zero, 2L) else values
}

difference <- function(totals, code) {
  values <- total_pair(totals, code)
  values[1] - values[2]
}

aggregate_entries <- function(books, first = 0L, last = 36524L, operating = FALSE) {
  totals <- list()
  for (entry in books$entries) {
    if (entry$day < first || entry$day > last ||
        (operating && entry$category %in% c("closing", "reopen"))) next
    for (line in entry$lines) {
      values <- total_pair(totals, line$code)
      side <- if (line$debit) 1L else 2L
      values[side] <- values[side] + line$amount
      totals[[line$code]] <- values
    }
  }
  totals
}

account_balance <- function(books, account, day = 36524L) {
  account$sign * difference(aggregate_entries(books, last = day), account$code)
}

daily_sum <- function(books, account, first, last) {
  changes <- rep(zero, last - first + 1L)
  opening <- zero
  for (entry in books$entries) {
    if (entry$day > last) next
    selected <- Filter(function(line) line$code == account$code, entry$lines)
    change <- account$sign * sum_big(lapply(selected, line_difference))
    if (entry$day < first) {
      opening <- opening + change
    } else {
      index <- entry$day - first + 1L
      changes[index] <- changes[index] + change
    }
  }
  sum(cumsum(changes) + opening)
}

posting_order <- function(books) {
  dates <- vapply(books$entries, function(entry) entry$day, integer(1))
  order(dates, seq_along(dates), method = "radix")
}

post_entry <- function(books, id, day, category, memo, lines) {
  index <- length(books$entries) + 1L
  books$entries[[index]] <- list(id = id, day = day, category = category, memo = memo,
                                  lines = lines, amount = line_totals(lines)[1],
                                  reversed_by = NULL, reverses = NULL)
  books$entry_positions[[id]] <- index
  index
}

reverse_entry <- function(books, index, day, category, memo) {
  original <- books$entries[[index]]
  lines <- lapply(original$lines, function(line) {
    line$debit <- !line$debit
    line
  })
  created <- post_entry(books, paste0(original$id, "-R"), day, category, memo, lines)
  books$entries[[index]]$reversed_by <- created
  books$entries[[created]]$reverses <- index
  created
}

posted_text <- function(entry) {
  paste("POST", entry$id, date_text(entry$day), "lines", length(entry$lines), "amount", money(entry$amount))
}

new_settlement <- function() list(items = list(), head = 1L, unapplied = zero)
open_items <- function(group) group$items[seq_along(group$items) >= group$head]

settlements_for <- function(books, account, day) {
  settlements <- list()
  for (index in posting_order(books)) {
    entry <- books$entries[[index]]
    if (entry$day > day) break
    for (line in entry$lines) {
      if (line$code != account$code || is.na(line$partner)) next
      group <- settlements[[line$partner]]
      if (is.null(group)) group <- new_settlement()
      value <- account$sign * line_difference(line)
      if (value > 0L) {
        used <- min(value, group$unapplied)
        group$unapplied <- group$unapplied - used
        if (value > used) {
          group$items[[length(group$items) + 1L]] <- list(entry = index, original = value, remaining = value - used)
        }
      } else {
        remaining <- -value
        while (remaining > 0L && group$head <= length(group$items)) {
          used <- min(remaining, group$items[[group$head]]$remaining)
          group$items[[group$head]]$remaining <- group$items[[group$head]]$remaining - used
          remaining <- remaining - used
          if (group$items[[group$head]]$remaining == 0L) group$head <- group$head + 1L
        }
        group$unapplied <- group$unapplied + remaining
      }
      settlements[[line$partner]] <- group
    }
  }
  settlements
}

section <- function(books, heading, kinds, sign, totals, earnings = NULL) {
  selected <- Filter(function(code) books$accounts[[code]]$kind %in% kinds, sorted_names(books$accounts))
  total <- sign * sum_big(lapply(selected, function(code) difference(totals, code)))
  if (!is.null(earnings)) total <- total + earnings
  emit(paste0("  ", heading), money(total))
  roots <- vapply(selected, function(code) top_account(books, code), character(1))
  for (root in sort(unique(roots), method = "radix")) {
    group <- selected[roots == root]
    values <- c_bigz(lapply(group, function(code) sign * difference(totals, code)))
    if (!any(values != 0L)) next
    emit(paste0("    ", root), books$accounts[[root]]$name, money(sum(values)))
    for (i in which(values != 0L)) {
      code <- group[i]
      emit(paste0("      ", code), books$accounts[[code]]$name, money(values[i]))
    }
  }
  if (!is.null(earnings)) emit("    current earnings", money(earnings))
  total
}

aging_columns <- function(values) {
  paste("0-30", money(values[1]), "31-60", money(values[2]), "61-90", money(values[3]),
        "91+", money(values[4]), "unapplied", money(values[5]), "balance", money(sum(values[1:4]) - values[5]))
}

post_draft <- function(books) {
  block <- books$draft
  if (is.null(block)) fail("no open entry")
  books$draft <- NULL
  journal <- block$kind == "journal"
  day <- 0L
  if (journal) {
    if (!is.null(books$entry_positions[[block$key]])) fail(paste("duplicate entry", block$key))
    day <- checked_date(block$date_token)
    check_closed(books, day)
  } else if (!is.null(books$templates[[block$key]])) {
    fail(paste("duplicate template", block$key))
  }
  if (length(block$lines) < 2L) fail(paste("too few lines", block$key))
  for (line in block$lines) {
    account <- get_account(books, line$code)
    if (journal && !account$active) fail(paste("inactive account", line$code))
    if (line$amount == 0L) fail(paste("zero amount", line$code))
  }
  values <- line_totals(block$lines)
  if (values[1] != values[2]) {
    fail(paste("unbalanced", block$key, "debit", money(values[1]), "credit", money(values[2])))
  }
  if (journal) {
    index <- post_entry(books, block$key, day, "journal", block$memo, block$lines)
    emit(posted_text(books$entries[[index]]))
  } else {
    books$templates[[block$key]] <- list(memo = block$memo, lines = block$lines, uses = 0L)
    emit("TEMPLATE", block$key, "lines", length(block$lines), "amount", money(values[1]))
  }
}

command <- function(books, words) {
  op <- words[1]
  if (op == "ACCOUNT") {
    code <- words[2]
    if (!is.null(books$accounts[[code]])) fail(paste("duplicate account", code))
    kind <- words[3]
    family <- if (kind == "CONTRA_ASSET") "ASSET" else kind
    for (other in sorted_names(books$accounts)) {
      if ((startsWith(code, other) || startsWith(other, code)) && books$accounts[[other]]$family != family) {
        fail(paste("class mismatch", code, other))
      }
    }
    books$accounts[[code]] <- list(code = code, kind = kind, name = words[4], active = TRUE,
                                   sign = if (kind %in% c("ASSET", "EXPENSE")) 1L else -1L, family = family)
    emit("ACCOUNT", code, kind, words[4], "parent", parent_code(books, code))
  } else if (op == "DEACTIVATE") {
    account <- get_account(books, words[2])
    if (!account$active) fail(paste("already inactive", account$code))
    balance <- account_balance(books, account)
    if (balance != 0L) fail(paste("nonzero balance", account$code, money(balance)))
    books$accounts[[account$code]]$active <- FALSE
    emit("DEACTIVATE", account$code, account$name)
  } else if (op %in% c("JOURNAL", "TEMPLATE")) {
    if (!is.null(books$draft)) emit("DISCARD", books$draft$key, "lines", length(books$draft$lines))
    journal <- op == "JOURNAL"
    books$draft <- list(kind = if (journal) "journal" else "template", key = words[2],
                        date_token = if (journal) words[3] else NULL,
                        memo = if (journal) words[4] else words[3], lines = list())
  } else if (op %in% c("DR", "CR")) {
    if (is.null(books$draft)) fail("no open entry")
    partner <- if (length(words) == 4L) words[4] else NA_character_
    books$draft$lines[[length(books$draft$lines) + 1L]] <- posting_line(op == "DR", words[2], parse_cents(words[3]), partner)
  } else if (op == "POST") {
    post_draft(books)
  } else if (op == "DRAFT") {
    block <- books$draft
    if (is.null(block)) fail("no open entry")
    values <- line_totals(block$lines)
    emit("DRAFT", block$kind, block$key, "lines", length(block$lines), "debit", money(values[1]),
         "credit", money(values[2]), "difference", money(values[1] - values[2]))
  } else if (op == "REVERSE") {
    index <- get_entry(books, words[2])
    original <- books$entries[[index]]
    if (original$category %in% c("reversal", "closing", "reopen")) fail(paste("cannot reverse", original$id))
    if (!is.null(original$reversed_by)) fail(paste("already reversed", original$id))
    day <- checked_date(words[3])
    if (day < original$day) fail(paste("reverse before entry", original$id, date_text(original$day)))
    check_closed(books, day)
    active_check(books, line_codes(original$lines))
    created <- reverse_entry(books, index, day, "reversal", original$memo)
    posted <- books$entries[[created]]
    emit("REVERSE", original$id, "entry", posted$id, date_text(day), "amount", money(posted$amount))
  } else if (op == "RECUR") {
    pattern <- get_template(books, words[2])
    day <- checked_date(words[3])
    count <- as.integer(words[4])
    if (count == 0L) fail("invalid count")
    check_closed(books, day)
    active_check(books, line_codes(pattern$lines))
    emit("RECUR", words[2], "count", count)
    for (offset in seq_len(count) - 1L) {
      pattern$uses <- pattern$uses + 1L
      id <- paste0(words[2], "-", pattern$uses)
      index <- post_entry(books, id, months_after(day, offset), "recurring", pattern$memo, pattern$lines)
      emit(paste0("  ", posted_text(books$entries[[index]])))
    }
    books$templates[[words[2]]] <- pattern
  } else if (op == "DEPRECIATE") {
    day <- checked_date(words[2])
    check_closed(books, day)
    asset <- get_account(books, words[3], "ASSET")
    contra <- get_account(books, words[4], "CONTRA_ASSET")
    expense <- get_account(books, words[5], "EXPENSE")
    active_check(books, c(contra$code, expense$code))
    cost <- account_balance(books, asset, day)
    accumulated <- account_balance(books, contra, day)
    amount <- if (cost > 0L) min(cost %/% as.integer(words[6]), cost - accumulated) else zero
    if (amount <= 0L) fail(paste("nothing to depreciate", asset$code))
    books$depreciation_count <- books$depreciation_count + 1L
    id <- paste0("DEP-", books$depreciation_count)
    post_entry(books, id, day, "depreciation", "depreciation",
               list(posting_line(TRUE, expense$code, amount), posting_line(FALSE, contra$code, amount)))
    emit("DEPRECIATE", asset$code, "entry", id, date_text(day), "amount", money(amount),
         "accumulated", money(accumulated + amount), "book", money(cost - accumulated - amount))
  } else if (op == "INTEREST") {
    account <- get_account(books, words[2])
    if (!account$kind %in% c("ASSET", "LIABILITY")) fail(paste("not interest bearing", account$code))
    offset <- get_account(books, words[3], if (account$kind == "ASSET") "REVENUE" else "EXPENSE")
    period <- checked_range(words[4], words[5])
    check_closed(books, period[2])
    active_check(books, c(account$code, offset$code))
    total <- daily_sum(books, account, period[1], period[2])
    amount <- (total * as.integer(words[6])) %/% 3650000L
    if (amount <= 0L) fail(paste("no interest", account$code))
    books$interest_count <- books$interest_count + 1L
    id <- paste0("INT-", books$interest_count)
    debit <- if (account$kind == "ASSET") account$code else offset$code
    credit <- if (account$kind == "ASSET") offset$code else account$code
    post_entry(books, id, period[2], "interest", "interest",
               list(posting_line(TRUE, debit, amount), posting_line(FALSE, credit, amount)))
    days <- period[2] - period[1] + 1L
    emit("INTEREST", account$code, "entry", id, date_text(period[2]), "days", days,
         "average", money(total %/% days), "amount", money(amount))
  } else if (op == "WRITEOFF") {
    day <- checked_date(words[2])
    check_closed(books, day)
    account <- get_account(books, words[3], "ASSET")
    expense <- get_account(books, words[4], "EXPENSE")
    active_check(books, c(account$code, expense$code))
    age <- as.integer(words[5])
    settlements <- settlements_for(books, account, day)
    amounts <- list()
    for (partner in sorted_names(settlements)) {
      old <- Filter(function(item) day - books$entries[[item$entry]]$day > age, open_items(settlements[[partner]]))
      amount <- sum_big(lapply(old, function(item) item$remaining))
      if (amount > 0L) amounts[[partner]] <- amount
    }
    total <- sum_big(amounts)
    if (total == 0L) fail(paste("nothing to write off", account$code))
    lines <- list(posting_line(TRUE, expense$code, total))
    for (partner in names(amounts)) {
      lines[[length(lines) + 1L]] <- posting_line(FALSE, account$code, amounts[[partner]], partner)
    }
    books$writeoff_count <- books$writeoff_count + 1L
    id <- paste0("WO-", books$writeoff_count)
    post_entry(books, id, day, "writeoff", "writeoff", lines)
    emit("WRITEOFF", account$code, "entry", id, date_text(day), "partners", length(amounts), "amount", money(total))
    for (partner in names(amounts)) emit(paste0("  ", partner), money(amounts[[partner]]))
  } else if (op == "CLOSE") {
    day <- checked_date(words[2])
    check_closed(books, day)
    equity <- get_account(books, words[3], "EQUITY")
    active_check(books, equity$code)
    totals <- aggregate_entries(books, last = day)
    selected <- Filter(function(code) books$accounts[[code]]$kind %in% c("REVENUE", "EXPENSE") &&
                         difference(totals, code) != 0L, sorted_names(books$accounts))
    active_check(books, selected)
    lines <- lapply(selected, function(code) {
      delta <- difference(totals, code)
      posting_line(delta < 0L, code, abs(delta))
    })
    income <- -sum_big(lapply(selected, function(code) difference(totals, code)))
    if (income != 0L) lines[[length(lines) + 1L]] <- posting_line(income < 0L, equity$code, abs(income))
    books$close_count <- books$close_count + 1L
    index <- NULL
    if (length(lines)) {
      id <- paste0("CLOSE-", books$close_count)
      index <- post_entry(books, id, day, "closing", "closing", lines)
      emit("CLOSE", date_text(day), "entry", id, "lines", length(lines), "net income", money(income))
    } else {
      emit("CLOSE", date_text(day), "no entry")
    }
    books$closes[[length(books$closes) + 1L]] <- list(day = day, entry = index)
  } else if (op == "REOPEN") {
    if (!length(books$closes)) fail("nothing to reopen")
    record <- tail(books$closes, 1L)[[1]]
    detail <- "no entry"
    if (!is.null(record$entry)) {
      active_check(books, line_codes(books$entries[[record$entry]]$lines))
      created <- reverse_entry(books, record$entry, record$day, "reopen", "reopen")
      detail <- paste("entry", books$entries[[created]]$id)
    }
    books$closes <- head(books$closes, -1L)
    emit("REOPEN", date_text(record$day), detail, "closed", closed_text(books))
  } else if (op == "LEDGER") {
    account <- get_account(books, words[2])
    period <- checked_range(words[3], words[4])
    running <- account_balance(books, account, period[1] - 1L)
    debit <- credit <- zero
    emit("LEDGER", account$code, account$name, date_text(period[1]), date_text(period[2]))
    emit("  opening", money(running))
    for (index in posting_order(books)) {
      entry <- books$entries[[index]]
      if (entry$day < period[1] || entry$day > period[2]) next
      for (line in entry$lines) {
        if (line$code != account$code) next
        running <- running + account$sign * line_difference(line)
        if (line$debit) debit <- debit + line$amount else credit <- credit + line$amount
        emit(paste0("  ", date_text(entry$day)), entry$id, if (line$debit) "DR" else "CR",
             money(line$amount), "balance", money(running), entry$memo)
      }
    }
    days <- period[2] - period[1] + 1L
    average <- daily_sum(books, account, period[1], period[2]) %/% days
    emit("  ending", money(running), "debits", money(debit), "credits", money(credit), "days", days, "average", money(average))
  } else if (op == "ACTIVITY") {
    account <- get_account(books, words[2])
    year <- as.integer(words[3])
    total <- rep(zero, 2L)
    emit("ACTIVITY", account$code, account$name, year)
    for (month in seq_len(12L)) {
      first <- day_number(year, month, 1L)
      last <- first + month_length(year, month) - 1L
      values <- total_pair(aggregate_entries(books, first, last), account$code)
      total <- total + values
      emit(paste0("  ", sprintf("%04d-%02d", year, month)), "debit", money(values[1]),
           "credit", money(values[2]), "balance", money(account_balance(books, account, last)))
    }
    emit("  total debit", money(total[1]), "credit", money(total[2]))
  } else if (op == "TRIAL") {
    day <- checked_date(words[2])
    totals <- aggregate_entries(books, last = day)
    debit <- credit <- zero
    emit("TRIAL", date_text(day))
    for (code in sorted_names(books$accounts)) {
      delta <- difference(totals, code)
      if (delta == 0L) next
      emit(paste0("  ", code), books$accounts[[code]]$name, if (delta > 0L) "debit" else "credit", money(abs(delta)))
      if (delta > 0L) debit <- debit + delta else credit <- credit - delta
    }
    emit("  total debit", money(debit), "credit", money(credit))
  } else if (op == "INCOME") {
    period <- checked_range(words[2], words[3])
    totals <- aggregate_entries(books, period[1], period[2], operating = TRUE)
    emit("INCOME", date_text(period[1]), date_text(period[2]))
    revenue <- section(books, "REVENUE", "REVENUE", -1L, totals)
    expense <- section(books, "EXPENSE", "EXPENSE", 1L, totals)
    emit("  NET INCOME", money(revenue - expense))
  } else if (op == "BALANCE") {
    day <- checked_date(words[2])
    totals <- aggregate_entries(books, last = day)
    selected <- Filter(function(code) books$accounts[[code]]$kind %in% c("REVENUE", "EXPENSE"), names(books$accounts))
    earnings <- -sum_big(lapply(selected, function(code) difference(totals, code)))
    emit("BALANCE", date_text(day))
    assets <- section(books, "ASSETS", c("ASSET", "CONTRA_ASSET"), 1L, totals)
    liabilities <- section(books, "LIABILITIES", "LIABILITY", -1L, totals)
    equity <- section(books, "EQUITY", "EQUITY", -1L, totals, earnings)
    if (assets == liabilities + equity) emit("  check ok") else emit("  check mismatch", money(assets - liabilities - equity))
  } else if (op == "ROLLUP") {
    day <- checked_date(words[3])
    selected <- sorted_names(books$accounts)
    selected <- selected[startsWith(selected, words[2])]
    emit("ROLLUP", words[2], date_text(day))
    if (!length(selected)) {
      emit("  (none)")
      return(invisible(NULL))
    }
    totals <- aggregate_entries(books, last = day)
    postings <- rep(zero, 2L)
    for (code in selected) {
      account <- books$accounts[[code]]
      descendants <- selected[startsWith(selected, code)]
      depth <- sum(selected != code & startsWith(code, selected))
      subtotal <- account$sign * sum_big(lapply(descendants, function(other) difference(totals, other)))
      emit(paste0(strrep(" ", 2L * (1L + depth)), code), account$name,
           "own", money(account$sign * difference(totals, code)), "total", money(subtotal))
      postings <- postings + total_pair(totals, code)
    }
    emit("  postings debit", money(postings[1]), "credit", money(postings[2]))
  } else if (op %in% c("AGING", "ITEMS")) {
    account <- get_account(books, words[2])
    day <- checked_date(tail(words, 1L))
    settlements <- settlements_for(books, account, day)
    if (op == "ITEMS") {
      group <- settlements[[words[3]]]
      if (is.null(group)) group <- new_settlement()
      emit("ITEMS", account$code, account$name, words[3], date_text(day))
      items <- open_items(group)
      for (item in items) {
        entry <- books$entries[[item$entry]]
        emit(paste0("  ", date_text(entry$day)), entry$id, "amount", money(item$original),
             "open", money(item$remaining), "age", day - entry$day)
      }
      balance <- sum_big(lapply(items, function(item) item$remaining)) - group$unapplied
      emit("  unapplied", money(group$unapplied), "balance", money(balance))
    } else {
      emit("AGING", account$code, account$name, date_text(day))
      totals <- rep(zero, 5L)
      for (partner in sorted_names(settlements)) {
        group <- settlements[[partner]]
        items <- open_items(group)
        if (!length(items) && group$unapplied == 0L) next
        values <- rep(zero, 5L)
        for (item in items) {
          age <- day - books$entries[[item$entry]]$day
          bucket <- if (age <= 30L) 1L else if (age <= 60L) 2L else if (age <= 90L) 3L else 4L
          values[bucket] <- values[bucket] + item$remaining
        }
        values[5] <- group$unapplied
        totals <- totals + values
        emit(paste0("  ", partner), aging_columns(values))
      }
      emit("  total", aging_columns(totals))
    }
  } else if (op == "ENTRY") {
    entry <- books$entries[[get_entry(books, words[2])]]
    emit("ENTRY", entry$id, date_text(entry$day), entry$category, entry$memo)
    for (line in entry$lines) {
      detail <- paste(if (line$debit) "DR" else "CR", line$code, books$accounts[[line$code]]$name, money(line$amount))
      if (!is.na(line$partner)) detail <- paste(detail, line$partner)
      emit(paste0("  ", detail))
    }
    emit("  total", money(entry$amount))
    if (!is.null(entry$reverses)) emit("  reverses", books$entries[[entry$reverses]]$id)
    if (!is.null(entry$reversed_by)) emit("  reversed by", books$entries[[entry$reversed_by]]$id)
  } else if (op == "DAYBOOK") {
    period <- checked_range(words[2], words[3])
    count <- 0L
    total <- zero
    emit("DAYBOOK", date_text(period[1]), date_text(period[2]))
    for (index in posting_order(books)) {
      entry <- books$entries[[index]]
      if (entry$day < period[1] || entry$day > period[2]) next
      count <- count + 1L
      total <- total + entry$amount
      emit(paste0("  ", date_text(entry$day)), entry$id, entry$category, money(entry$amount), entry$memo)
    }
    emit("  total entries", count, "amount", money(total))
  } else if (op == "ACCOUNTS") {
    emit("ACCOUNTS")
    codes <- sorted_names(books$accounts)
    if (!length(codes)) emit("  (none)")
    totals <- aggregate_entries(books)
    for (code in codes) {
      account <- books$accounts[[code]]
      emit(paste0("  ", code), account$kind, account$name, "parent", parent_code(books, code),
           "balance", money(account$sign * difference(totals, code)), if (account$active) "active" else "inactive")
    }
  } else if (op == "TEMPLATES") {
    emit("TEMPLATES")
    template_names <- sorted_names(books$templates)
    if (!length(template_names)) emit("  (none)")
    for (name in template_names) {
      pattern <- books$templates[[name]]
      emit(paste0("  ", name), pattern$memo, "lines", length(pattern$lines),
           "amount", money(line_totals(pattern$lines)[1]), "used", pattern$uses)
    }
  } else if (op == "STATUS") {
    inactive <- sum(vapply(books$accounts, function(account) !account$active, logical(1)))
    open <- if (is.null(books$draft)) "none" else books$draft$key
    emit("STATUS accounts", length(books$accounts), "inactive", inactive, "entries", length(books$entries),
         "templates", length(books$templates), "closed", closed_text(books), "open", open)
  }
  invisible(NULL)
}

input <- file("stdin", open = "r")
count <- as.integer(readLines(input, n = 1L, warn = FALSE))
books <- new_books()
for (i in seq_len(count)) {
  words <- strsplit(readLines(input, n = 1L, warn = FALSE), " ", fixed = TRUE)[[1]]
  tryCatch(command(books, words), bookkeeping_error = function(problem) emit("ERROR", conditionMessage(problem)))
}
close(input)
