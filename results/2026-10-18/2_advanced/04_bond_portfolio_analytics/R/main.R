script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("dates_calendar", "daycount", "schedule", "pricing", "curve")) source(file.path(source_dir, paste0(unit, ".R")))

BOND_TYPES <- c("FIXED", "ZERO", "AMORT", "FRN")
FREQUENCIES <- c(1L, 2L, 4L, 12L)
BUCKET_NAMES <- c("0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+")
OPTION_KEYS <- list(FIXED = c("EOM", "LONG", "CALL"), ZERO = c("EOM", "LONG"),
                    AMORT = c("EOM", "LONG", "SINK"), FRN = c("EOM", "LONG", "LAG", "CAP", "FLOOR"))

input_error <- function(reason) stop(structure(list(message = reason, call = NULL), class = c("input_error", "error", "condition")))

integer_divide <- function(a, b) {
  quotient <- floor(a / b)
  while (quotient * b > a) quotient <- quotient - 1
  while ((quotient + 1) * b <= a) quotient <- quotient + 1
  quotient
}

round_half_up <- function(a, b) integer_divide(2 * a + b, 2 * b)

integer_text <- function(value) sprintf("%.0f", value)

hundredths <- function(value) {
  if (value < 0) return(paste0("-", hundredths(-value)))
  whole <- integer_divide(value, 100)
  paste0(integer_text(whole), ".", sprintf("%02d", as.integer(value - whole * 100)))
}

decimals <- function(value, digits) {
  negative <- value < 0
  if (negative) value <- -value
  scale <- 1
  for (i in seq_len(digits)) scale <- scale * 10
  rounded <- floor(value * scale + 0.5)
  whole <- integer_divide(rounded, scale)
  fraction <- as.integer(rounded - whole * scale)
  paste0(if (negative && rounded > 0) "-" else "", integer_text(whole), ".", sprintf(paste0("%0", digits, "d"), fraction))
}

percent <- function(value) decimals(value * 100, 4L)
amount <- function(cents) decimals(cents / 100, 2L)
thousandths <- function(price) as.integer(gsub(".", "", price, fixed = TRUE))

read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)

read_rows <- function(name) {
  lines <- read_lines(name)
  lapply(seq.int(2L, length(lines)), function(number) list(line = number, fields = strsplit(lines[number], ",", fixed = TRUE)[[1L]]))
}

validate_rows <- function(rows, file, key_index, parser, errors) {
  seen <- character()
  valid <- list()
  for (row in rows) {
    key <- row$fields[key_index]
    record <- tryCatch(parser(row$fields, seen), input_error = function(error) {
      errors$lines <- c(errors$lines, paste0(file, ":", row$line, ": ", key, ": ", conditionMessage(error)))
      NULL
    })
    seen <- c(seen, key)
    if (!is.null(record)) valid[[length(valid) + 1L]] <- record
  }
  valid
}

read_params <- function() {
  params <- list(scenarios = list(), limits = list())
  lines <- read_lines("params.txt")
  for (number in seq_along(lines)) {
    words <- strsplit(lines[number], " ", fixed = TRUE)[[1L]]
    kind <- words[1L]
    if (kind == "valuation_date") params$valuation_date <- parse_date(words[2L])
    else if (kind == "settlement_days") params$settlement_days <- as.integer(words[2L])
    else if (kind == "scenario") {
      params$scenarios[[length(params$scenarios) + 1L]] <- list(line = number, name = words[2L], shifts = as.integer(words[-c(1L, 2L)]))
    } else params$limits[[length(params$limits) + 1L]] <- words[-1L]
  }
  params
}

parse_pillar <- function(fields, seen, settlement) {
  if (fields[1L] %in% seen) input_error("duplicate pillar")
  if (!valid_date(fields[1L])) input_error("invalid date")
  maturity <- parse_date(fields[1L])
  if (maturity <= settlement) input_error("pillar not after settlement")
  frequency <- as.integer(fields[3L])
  if (!frequency %in% FREQUENCIES) input_error("invalid frequency")
  list(maturity = maturity, coupon = as.integer(fields[2L]), frequency = frequency)
}

validate_scenarios <- function(rows, count, errors) {
  seen <- character()
  scenarios <- list()
  for (row in rows) {
    reason <- if (row$name %in% seen) "duplicate scenario" else if (length(row$shifts) != count) "wrong number of shifts" else NULL
    if (is.null(reason)) scenarios[[length(scenarios) + 1L]] <- list(name = row$name, deltas = row$shifts * BASIS_POINT)
    else errors$lines <- c(errors$lines, paste0("params.txt:", row$line, ": ", row$name, ": ", reason))
    seen <- c(seen, row$name)
  }
  scenarios
}

parse_options <- function(kind, text) {
  options <- list(end_of_month = FALSE, long_stub = FALSE, lag = NULL, cap = NULL, floor = NULL, sinks = list(), calls = list())
  seen <- character()
  items <- if (text == "-") character() else strsplit(text, ";", fixed = TRUE)[[1L]]
  for (item in items) {
    separator <- regexpr("=", item, fixed = TRUE)[1L]
    key <- if (separator < 0L) item else substr(item, 1L, separator - 1L)
    value <- if (separator < 0L) "" else substring(item, separator + 1L)
    if (!key %in% OPTION_KEYS[[kind]] || (key %in% seen && !key %in% c("SINK", "CALL"))) input_error("invalid option")
    seen <- c(seen, key)
    if (key == "EOM") options$end_of_month <- TRUE
    else if (key == "LONG") options$long_stub <- TRUE
    else if (key %in% c("LAG", "CAP", "FLOOR")) options[[tolower(key)]] <- as.integer(value)
    else {
      parts <- strsplit(value, ":", fixed = TRUE)[[1L]]
      if (key == "SINK") options$sinks[[length(options$sinks) + 1L]] <- list(date = parts[1L], amount = as.numeric(parts[2L]))
      else options$calls[[length(options$calls) + 1L]] <- list(date = parts[1L], price = thousandths(parts[2L]))
    }
  }
  if (kind == "FRN") {
    cap <- if (is.null(options$cap)) 1200L else options$cap
    if (is.null(options$lag) || !options$lag %in% 1L:5L || cap > 1200L || (!is.null(options$floor) && options$floor > cap)) input_error("invalid option")
  }
  options
}

schedule_days <- function(items, schedule, reason) {
  days <- integer()
  for (item in items) {
    if (!valid_date(item$date)) input_error(reason)
    day <- parse_date(item$date)
    if (!day %in% schedule[-c(1L, length(schedule))] || (length(days) && day <= tail(days, 1L))) input_error(reason)
    days <- c(days, day)
  }
  days
}

build_periods <- function(bond, holidays, fixings) {
  opening <- bond$face
  count <- length(bond$schedule) - 1L
  periods <- vector("list", count)
  for (number in seq_len(count)) {
    start <- bond$schedule[number]
    end <- bond$schedule[number + 1L]
    fraction <- year_fraction(bond$daycount, start, end)
    rate <- if (bond$kind == "ZERO") 0L else bond$coupon
    if (bond$kind == "FRN") {
      reset <- business_days(adjust_date(start, bond$bdc, holidays), bond$options$lag, holidays, -1L)
      index <- findInterval(reset, fixings$dates)
      if (!index) input_error("missing fixing")
      rate <- fixings$rates[index] + bond$coupon
      if (!is.null(bond$options$floor)) rate <- max(rate, bond$options$floor)
      if (!is.null(bond$options$cap)) rate <- min(rate, bond$options$cap)
    }
    principal <- if (number == count) opening else if (as.character(end) %in% names(bond$sinks)) bond$sinks[[as.character(end)]] else 0
    coupon <- round_half_up(opening * rate * fraction[1L], 10000 * fraction[2L])
    periods[[number]] <- list(number = number, start = start, end = end, payment = adjust_date(end, bond$bdc, holidays),
                              numerator = fraction[1L], denominator = fraction[2L], rate = rate, opening = opening,
                              coupon = coupon, principal = principal, cash_flow = coupon + principal)
    opening <- opening - principal
  }
  periods
}

parse_bond <- function(fields, seen, holidays, fixings) {
  code <- fields[1L]
  kind <- fields[2L]
  if (code %in% seen) input_error("duplicate id")
  if (!kind %in% BOND_TYPES) input_error("unknown type")
  if (!valid_date(fields[3L]) || !valid_date(fields[4L])) input_error("invalid date")
  issue <- parse_date(fields[3L])
  maturity <- parse_date(fields[4L])
  if (maturity <= issue) input_error("maturity not after issue")
  frequency <- as.integer(fields[6L])
  if (!frequency %in% FREQUENCIES) input_error("invalid frequency")
  if (!fields[7L] %in% DAY_COUNTS) input_error("unknown day count")
  if (!fields[8L] %in% BUSINESS_DAY_RULES) input_error("unknown business day rule")
  face <- as.numeric(fields[9L])
  if (face %% 100000 != 0 || face > 10000000) input_error("invalid face")
  coupon <- as.integer(fields[5L])
  if (coupon > 1200L || (kind == "ZERO" && coupon != 0L)) input_error("invalid coupon")
  options <- parse_options(kind, fields[10L])
  schedule <- coupon_schedule(issue, maturity, frequency, options$end_of_month, options$long_stub)
  sink_days <- schedule_days(options$sinks, schedule, "invalid sinking fund")
  sink_amounts <- vapply(options$sinks, function(item) item$amount, numeric(1L))
  if (any(sink_amounts == 0) || (kind == "AMORT" && (sum(sink_amounts) == 0 || sum(sink_amounts) >= face))) input_error("invalid sinking fund")
  call_days <- schedule_days(options$calls, schedule, "invalid call schedule")
  calls <- lapply(seq_along(call_days), function(i) {
    price <- options$calls[[i]]$price
    if (price < 100000L || price > 110000L) input_error("invalid call schedule")
    list(day = call_days[i], price = price)
  })
  bond <- list(code = code, kind = kind, issue = issue, maturity = maturity, coupon = coupon,
                frequency = frequency, daycount = fields[7L], bdc = fields[8L], face = face, options = options,
                schedule = schedule, sinks = setNames(as.list(sink_amounts), as.character(sink_days)), calls = calls)
  bond$periods <- build_periods(bond, holidays, fixings)
  bond
}

make_valuation <- function(bond, clean, settlement) {
  index <- which(vapply(bond$periods, function(period) period$end > settlement, logical(1L)))[1L]
  remaining <- bond$periods[seq.int(index, length(bond$periods))]
  current <- remaining[[1L]]
  outstanding <- current$opening
  fraction <- year_fraction(bond$daycount, current$start, settlement)
  accrued <- current$rate * fraction[1L] / (100 * fraction[2L])
  accrued_amount <- round_half_up(outstanding * current$rate * fraction[1L], 10000 * fraction[2L])
  clean_amount <- round_half_up(outstanding * clean, 100000)
  cash_flows <- Filter(function(period) period$cash_flow >= 1, remaining)
  flows <- do.call(rbind, lapply(cash_flows, function(period) c(period$payment - settlement, period$cash_flow)))
  fraction <- year_fraction(bond$daycount, settlement, current$end)
  pricer <- list(flows = vapply(remaining, function(period) period$cash_flow, numeric(1L)),
                 fraction = bond$frequency * fraction[1L] / fraction[2L], frequency = bond$frequency, outstanding = outstanding)
  list(bond = bond, clean = clean, remaining = remaining, cash_flows = cash_flows, flows = flows,
       outstanding = outstanding, accrued = accrued, accrued_amount = accrued_amount, clean_amount = clean_amount,
       unit_value = clean_amount + accrued_amount, target = clean / 1000 + accrued, pricer = pricer,
       next_payment = cash_flows[[1L]]$payment, workout = bond$maturity)
}

parse_price <- function(fields, seen, bonds, settlement) {
  code <- fields[1L]
  if (!code %in% names(bonds)) input_error("unknown bond")
  if (code %in% seen) input_error("duplicate price")
  bond <- bonds[[code]]
  if (!(bond$issue <= settlement && settlement < bond$maturity)) input_error("not outstanding")
  valuation <- make_valuation(bond, thousandths(fields[2L]), settlement)
  if (!(dirty_price(valuation$pricer, 0) > valuation$target && valuation$target > dirty_price(valuation$pricer, 1))) input_error("yield out of range")
  valuation
}

analyze_valuation <- function(valuation, curve, settlement) {
  valuation$ytm <- yield_to_maturity(valuation$pricer, valuation$target)
  valuation$risk <- yield_risk(valuation$pricer, valuation$ytm)
  valuation$ytw <- valuation$ytm
  for (call in valuation$bond$calls) {
    if (call$day <= settlement) next
    flows <- numeric()
    for (period in valuation$remaining) {
      flows <- c(flows, period$coupon)
      if (period$end == call$day) {
        flows[length(flows)] <- flows[length(flows)] + round_half_up(period$opening * call$price, 100000)
        break
      }
    }
    pricer <- valuation$pricer
    pricer$flows <- flows
    call_yield <- yield_to_maturity(pricer, valuation$target)
    if (call_yield < valuation$ytw) {
      valuation$ytw <- call_yield
      valuation$workout <- call$day
    }
  }
  principal_days <- 0
  for (i in seq_along(valuation$cash_flows)) principal_days <- principal_days + valuation$cash_flows[[i]]$principal * valuation$flows[i, 1L]
  valuation$wal <- principal_days / (365 * valuation$outstanding)
  valuation$curve_clean <- curve_value(curve, valuation$flows) * 100 / valuation$outstanding - valuation$accrued
  valuation$zspread <- z_spread(curve, valuation$flows, valuation$unit_value)
  valuation
}

parse_holding <- function(fields, bonds, valuations) {
  code <- fields[2L]
  if (!code %in% names(bonds)) input_error("unknown bond")
  if (!code %in% names(valuations)) input_error("no price")
  face <- as.numeric(fields[3L])
  units <- integer_divide(face, bonds[[code]]$face)
  if (units * bonds[[code]]$face != face) input_error("invalid face")
  list(portfolio = fields[1L], code = code, units = units,
       book = round_half_up(units * valuations[[code]]$outstanding * thousandths(fields[4L]), 100000))
}

position_value <- function(position) position$units * position$valuation$unit_value
position_face <- function(position) position$units * position$valuation$bond$face
position_outstanding <- function(position) position$units * position$valuation$outstanding
position_gain <- function(position) position$units * position$valuation$clean_amount - position$book
position_dv01 <- function(position) position$valuation$risk$dv01 * position$units * position$valuation$outstanding / 10000
position_pv <- function(position, curve) position$units * curve_value(curve, position$valuation$flows, position$valuation$zspread)

build_portfolios <- function(holdings, valuations) {
  positions <- list()
  for (holding in holdings) {
    key <- paste(holding$portfolio, holding$code, sep = "\t")
    if (!key %in% names(positions)) positions[[key]] <- list(portfolio = holding$portfolio, code = holding$code,
                                                            valuation = valuations[[holding$code]], units = 0, book = 0)
    positions[[key]]$units <- positions[[key]]$units + holding$units
    positions[[key]]$book <- positions[[key]]$book + holding$book
  }
  positions <- positions[sort(names(positions), method = "radix")]
  names <- sort(unique(vapply(positions, function(position) position$portfolio, character(1L))), method = "radix")
  lapply(names, function(name) list(name = name, positions = Filter(function(position) position$portfolio == name, positions)))
}

portfolio_value <- function(portfolio, curve) {
  total <- 0
  for (position in portfolio$positions) total <- total + position_pv(position, curve)
  total
}

analyze_portfolio <- function(portfolio, curve, scenarios, settlement) {
  positions <- portfolio$positions
  portfolio$total_value <- sum(vapply(positions, position_value, numeric(1L)))
  ytm <- modified <- convexity <- zspread <- dv01 <- 0
  flows <- matrix(numeric(), ncol = 2L)
  ladder <- list()
  for (position in positions) {
    value <- position_value(position)
    valuation <- position$valuation
    ytm <- ytm + value * valuation$ytm
    modified <- modified + value * valuation$risk$modified
    convexity <- convexity + value * valuation$risk$convexity
    zspread <- zspread + value * valuation$zspread
    dv01 <- dv01 + position_dv01(position)
    for (i in seq_len(nrow(valuation$flows))) flows <- rbind(flows, c(valuation$flows[i, 1L], position$units * valuation$flows[i, 2L]))
    for (period in valuation$cash_flows) {
      year <- as.character(civil_date(period$payment)[1L])
      if (!year %in% names(ladder)) ladder[[year]] <- c(coupon = 0, principal = 0)
      ladder[[year]] <- ladder[[year]] + position$units * c(period$coupon, period$principal)
    }
  }
  portfolio$ytm <- ytm / portfolio$total_value
  portfolio$modified <- modified / portfolio$total_value
  portfolio$convexity <- convexity / portfolio$total_value
  portfolio$zspread <- zspread / portfolio$total_value
  portfolio$dv01 <- dv01
  portfolio$cash_yield <- bisection(function(rate) curve_value(flat_curve(rate), flows), 0, 1, portfolio$total_value)
  portfolio$base_values <- vapply(positions, position_pv, numeric(1L), curve = curve)
  portfolio$base_value <- 0
  for (value in portfolio$base_values) portfolio$base_value <- portfolio$base_value + value
  durations <- numeric(length(curve$rates) + 1L)
  for (index in seq_along(durations)) {
    shifts <- rep(0, length(curve$rates))
    if (index == 1L) shifts[] <- BASIS_POINT else shifts[index - 1L] <- BASIS_POINT
    down <- portfolio_value(portfolio, shift_curve(curve, -shifts))
    up <- portfolio_value(portfolio, shift_curve(curve, shifts))
    durations[index] <- (down - up) / (2 * BASIS_POINT * portfolio$base_value)
  }
  portfolio$effective <- durations[1L]
  portfolio$key_rates <- durations[-1L]
  portfolio$ladder <- ladder[sort(names(ladder), method = "radix")]
  portfolio$results <- lapply(c(list(list(name = "BASE", deltas = rep(0, length(curve$rates)))), scenarios), function(scenario) {
    shifted <- shift_curve(curve, scenario$deltas)
    values <- vapply(positions, position_pv, numeric(1L), curve = shifted)
    total <- 0
    for (value in values) total <- total + value
    list(name = scenario$name, values = values, pnls = values - portfolio$base_values,
         total = total, pnl = total - portfolio$base_value)
  })
  portfolio
}

portfolio_income <- function(portfolio) {
  income <- 0
  for (position in portfolio$positions) for (i in seq_along(position$valuation$cash_flows)) {
    if (position$valuation$flows[i, 1L] <= 365L) income <- income + position$units * position$valuation$cash_flows[[i]]$coupon
  }
  income
}

group_line <- function(portfolio, label, name, members) {
  value <- duration <- dv01 <- 0
  for (position in members) {
    market <- position_value(position)
    value <- value + market
    duration <- duration + market * position$valuation$risk$modified
    dv01 <- dv01 + position_dv01(position)
  }
  paste(label, name, "positions", length(members), "value", hundredths(value), "weight", decimals(value * 100 / portfolio$total_value, 4L),
        "duration", decimals(duration / portfolio$total_value, 4L), "dv01", decimals(dv01, 2L))
}

bucket_index <- function(days) {
  matches <- which(days < c(365L, 1095L, 1825L, 3650L))
  if (length(matches)) matches[1L] else 5L
}

portfolio_lines <- function(portfolio, settlement) {
  positions <- portfolio$positions
  lines <- paste("portfolio", portfolio$name)
  for (position in positions) {
    valuation <- position$valuation
    value <- position_value(position)
    lines <- c(lines, paste("position", position$code, "face", hundredths(position_face(position)),
                            "outstanding", hundredths(position_outstanding(position)), "clean", decimals(valuation$clean / 1000, 6L),
                            "value", hundredths(value), "weight", decimals(value * 100 / portfolio$total_value, 4L),
                            "book", hundredths(position$book), "gain", hundredths(position_gain(position)),
                            "ytm", percent(valuation$ytm), "modified", decimals(valuation$risk$modified, 4L), "dv01", decimals(position_dv01(position), 2L)))
  }
  face <- sum(vapply(positions, position_face, numeric(1L)))
  outstanding <- sum(vapply(positions, position_outstanding, numeric(1L)))
  book <- sum(vapply(positions, function(position) position$book, numeric(1L)))
  gain <- sum(vapply(positions, position_gain, numeric(1L)))
  lines <- c(lines, paste("total positions", length(positions), "face", hundredths(face), "outstanding", hundredths(outstanding),
                          "value", hundredths(portfolio$total_value), "book", hundredths(book), "gain", hundredths(gain), "income", hundredths(portfolio_income(portfolio))),
              paste("risk ytm", percent(portfolio$ytm), "yield", percent(portfolio$cash_yield), "modified", decimals(portfolio$modified, 4L),
                    "convexity", decimals(portfolio$convexity, 4L), "zspread", percent(portfolio$zspread), "dv01", decimals(portfolio$dv01, 2L)),
              paste("curve effective", decimals(portfolio$effective, 4L), "krd", paste(vapply(portfolio$key_rates, decimals, character(1L), digits = 4L), collapse = " ")))
  for (kind in BOND_TYPES) lines <- c(lines, group_line(portfolio, "type", kind, Filter(function(position) position$valuation$bond$kind == kind, positions)))
  for (index in seq_along(BUCKET_NAMES)) {
    members <- Filter(function(position) bucket_index(position$valuation$bond$maturity - settlement) == index, positions)
    lines <- c(lines, group_line(portfolio, "bucket", BUCKET_NAMES[index], members))
  }
  total_coupon <- total_principal <- 0
  for (year in names(portfolio$ladder)) {
    values <- portfolio$ladder[[year]]
    lines <- c(lines, paste("ladder", year, "coupon", hundredths(values[1L]), "principal", hundredths(values[2L]), "total", hundredths(sum(values))))
    total_coupon <- total_coupon + values[1L]
    total_principal <- total_principal + values[2L]
  }
  lines <- c(lines, paste("ladder total coupon", hundredths(total_coupon), "principal", hundredths(total_principal), "total", hundredths(total_coupon + total_principal)))
  if (length(portfolio$results) > 1L) {
    results <- portfolio$results[-1L]
    worst <- results[[which.min(vapply(results, function(result) result$pnl, numeric(1L)))]]
    order <- head(order(worst$pnls, seq_along(positions), method = "radix"), 3L)
    losers <- vapply(order, function(index) paste(positions[[index]]$code, amount(worst$pnls[index])), character(1L))
    lines <- c(lines, paste("stress worst", worst$name, "pnl", amount(worst$pnl), "losers", paste(losers, collapse = " ")))
  }
  lines
}

scenario_lines <- function(portfolio) {
  lines <- character()
  for (result in portfolio$results) {
    for (index in seq_along(portfolio$positions)) lines <- c(lines, paste(portfolio$name, result$name, portfolio$positions[[index]]$code, amount(result$values[index]), amount(result$pnls[index]), sep = ","))
    lines <- c(lines, paste(portfolio$name, result$name, "*", amount(result$total), amount(result$pnl), sep = ","))
  }
  lines
}

check_limit <- function(portfolio, words, settlement) {
  kind <- words[1L]
  positions <- portfolio$positions
  if (kind == "position_weight") {
    values <- vapply(positions, position_value, numeric(1L))
    index <- which.max(values)
    limit <- as.numeric(words[2L])
    parts <- paste(positions[[index]]$code, decimals(values[index] * 100 / portfolio$total_value, 4L), "limit", hundredths(limit))
    breach <- values[index] * 10000 > limit * portfolio$total_value
  } else if (kind == "type_weight") {
    members <- Filter(function(position) position$valuation$bond$kind == words[2L], positions)
    value <- sum(vapply(members, position_value, numeric(1L)))
    limit <- as.numeric(words[3L])
    parts <- paste(words[2L], decimals(value * 100 / portfolio$total_value, 4L), "limit", hundredths(limit))
    breach <- value * 10000 > limit * portfolio$total_value
  } else if (kind == "max_maturity") {
    years <- as.integer(words[2L])
    count <- sum(vapply(positions, function(position) position$valuation$bond$maturity - settlement > 365L * years, logical(1L)))
    parts <- paste(paste0(years, "Y"), "positions", count)
    breach <- count >= 1L
  } else if (kind == "min_yield") {
    limit <- as.numeric(words[2L])
    parts <- paste(percent(portfolio$ytm), "limit", hundredths(limit))
    breach <- portfolio$ytm * 10000 < limit
  } else if (kind == "duration") {
    low <- as.integer(words[2L])
    high <- as.integer(words[3L])
    parts <- paste(decimals(portfolio$modified, 4L), "range", hundredths(low), hundredths(high))
    breach <- portfolio$modified < low / 100 || portfolio$modified > high / 100
  } else {
    limit <- as.numeric(words[2L])
    parts <- paste(decimals(portfolio$dv01, 2L), "limit", hundredths(limit))
    breach <- portfolio$dv01 * 100 > limit
  }
  list(parts = parts, breach = breach)
}

compliance_lines <- function(portfolio, limits, settlement) {
  lines <- character()
  breaches <- 0L
  for (words in limits) {
    result <- check_limit(portfolio, words, settlement)
    breaches <- breaches + as.integer(result$breach)
    lines <- c(lines, paste(portfolio$name, words[1L], result$parts, if (result$breach) "BREACH" else "PASS"))
  }
  c(lines, paste(portfolio$name, "breaches", breaches))
}

cashflow_lines <- function(bonds) {
  lines <- "bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"
  for (code in sort(names(bonds), method = "radix")) for (period in bonds[[code]]$periods) {
    if (period$cash_flow < 1) next
    lines <- c(lines, paste(code, period$number, format_date(period$start), format_date(period$end), format_date(period$payment),
                            decimals(period$numerator / period$denominator, 6L), period$rate, integer_text(period$opening),
                            integer_text(period$coupon), integer_text(period$principal), sep = ","))
  }
  lines
}

analytics_lines <- function(valuations) {
  lines <- "bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"
  for (code in sort(names(valuations), method = "radix")) {
    value <- valuations[[code]]
    lines <- c(lines, paste(code, decimals(value$clean / 1000, 6L), decimals(value$accrued, 6L), decimals(value$target, 6L),
                            percent(value$ytm), percent(value$ytw), format_date(value$workout), format_date(value$next_payment),
                            decimals(value$wal, 4L), decimals(value$risk$macaulay, 4L), decimals(value$risk$modified, 4L),
                            decimals(value$risk$convexity, 4L), decimals(value$risk$dv01, 6L), decimals(value$curve_clean, 6L), percent(value$zspread), sep = ","))
  }
  lines
}

curve_lines <- function(valuation_date, settlement, pillars, curve) {
  lines <- paste("valuation", format_date(valuation_date), "settlement", format_date(settlement))
  previous <- 0L
  for (index in seq_along(pillars)) {
    pillar <- pillars[[index]]
    days <- curve$days[index]
    lines <- c(lines, paste("pillar", format_date(pillar$maturity), "days", days, "frequency", pillar$frequency,
                            "par", hundredths(pillar$coupon), "zero", percent(curve$rates[index]), "df", decimals(discount_factor(curve, days), 6L),
                            "forward", percent(forward_rate(curve, previous, days))))
    previous <- days
  }
  for (year in seq_len(tail(curve$days, 1L) %/% 365L)) {
    days <- 365L * year
    lines <- c(lines, paste("grid", paste0(year, "Y"), "days", days, "zero", percent(zero_rate(curve, days)),
                            "df", decimals(discount_factor(curve, days), 6L), "forward", percent(forward_rate(curve, days - 365L, days))))
  }
  lines
}

main <- function() {
  params <- read_params()
  holidays <- vapply(read_lines("calendar.txt"), parse_date, integer(1L))
  fixing_rows <- read_rows("fixings.csv")
  fixings <- list(dates = vapply(fixing_rows, function(row) parse_date(row$fields[1L]), integer(1L)),
                  rates = vapply(fixing_rows, function(row) as.integer(row$fields[2L]), integer(1L)))
  settlement <- business_days(params$valuation_date, params$settlement_days, holidays)
  errors <- new.env(parent = emptyenv())
  errors$lines <- character()
  pillars <- validate_rows(read_rows("curve_quotes.csv"), "curve_quotes.csv", 1L, function(fields, seen) parse_pillar(fields, seen, settlement), errors)
  pillars <- pillars[order(vapply(pillars, function(pillar) pillar$maturity, integer(1L)))]
  scenarios <- validate_scenarios(params$scenarios, length(pillars), errors)
  bonds <- validate_rows(read_rows("bonds.csv"), "bonds.csv", 1L, function(fields, seen) parse_bond(fields, seen, holidays, fixings), errors)
  names(bonds) <- vapply(bonds, function(bond) bond$code, character(1L))
  valuations <- validate_rows(read_rows("prices.csv"), "prices.csv", 1L, function(fields, seen) parse_price(fields, seen, bonds, settlement), errors)
  names(valuations) <- vapply(valuations, function(value) value$bond$code, character(1L))
  holdings <- validate_rows(read_rows("holdings.csv"), "holdings.csv", 2L, function(fields, seen) parse_holding(fields, bonds, valuations), errors)
  curve <- bootstrap(settlement, pillars)
  valuations <- lapply(valuations, analyze_valuation, curve = curve, settlement = settlement)
  portfolios <- lapply(build_portfolios(holdings, valuations), analyze_portfolio, curve = curve, scenarios = scenarios, settlement = settlement)
  report <- scenario_output <- compliance <- character()
  for (portfolio in portfolios) {
    report <- c(report, portfolio_lines(portfolio, settlement))
    scenario_output <- c(scenario_output, scenario_lines(portfolio))
    compliance <- c(compliance, compliance_lines(portfolio, params$limits, settlement))
  }
  dir.create("output", showWarnings = FALSE)
  writeLines(errors$lines, "output/errors.txt", useBytes = TRUE)
  writeLines(cashflow_lines(bonds), "output/cashflows.csv", useBytes = TRUE)
  writeLines(analytics_lines(valuations), "output/analytics.csv", useBytes = TRUE)
  writeLines(curve_lines(params$valuation_date, settlement, pillars, curve), "output/curve.txt", useBytes = TRUE)
  writeLines(report, "output/portfolio.txt", useBytes = TRUE)
  writeLines(c("portfolio,scenario,bond,value,pnl", scenario_output), "output/scenarios.csv", useBytes = TRUE)
  writeLines(compliance, "output/compliance.txt", useBytes = TRUE)
}

main()
