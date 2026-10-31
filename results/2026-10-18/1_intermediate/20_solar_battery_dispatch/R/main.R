setting_names <- strsplit(paste(
  "CAPACITY INITIAL CHARGE DISCHARGE CEFF DEFF RESERVE COST",
  "EXPORT FEEDIN FIXED DEMAND PVSCALE"
), " ")[[1]]
setting_ranges <- setNames(list(
  c(1, 100000), c(0, 100), c(1, 20000), c(1, 20000), c(1, 100),
  c(1, 100), c(0, 100), c(0, 100000), c(0, 100000), c(0, 10000),
  c(0, 100000), c(0, 100000), c(0, 300)
), setting_names)
strategy_ranges <- list(TOU = c(1, 100), PEAKSHAVE = c(0, 100000), BACKUP = c(0, 100))
flow_names <- strsplit(paste(
  "PV>LOAD PV>BATTERY PV>GRID PV>CURTAIL",
  "BATTERY>LOAD BATTERY>GRID GRID>LOAD GRID>BATTERY"
), " ")[[1]]
report_names <- strsplit(paste(
  "DAILY BILL SAVINGS BYPERIOD DAYTYPE PROFILE FLOWS",
  "SELFSUFF CYCLES USAGE HISTOGRAM"
), " ")[[1]]

fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("command_error", "error", "condition")))
}

text_value <- function(value) {
  if (is.numeric(value)) sprintf("%.0f", value) else as.character(value)
}

emit <- function(...) {
  parts <- unlist(lapply(list(...), text_value), use.names = FALSE)
  cat(paste(parts, collapse = " "), "\n", sep = "")
}

money <- function(value) {
  sprintf("%s%.0f.%02.0f", if (value < 0) "-" else "",
          abs(value) %/% 100, abs(value) %% 100)
}

percentage <- function(a, b) money(if (b == 0) 0 else (10000 * a) %/% b)

decimal <- function(a, b, places) {
  scale <- 10^places
  value <- (a * scale) %/% b
  sprintf(paste0("%.0f.%0", places, ".0f"), value %/% scale, value %% scale)
}

ceil_div <- function(a, b) (a + b - 1) %/% b
bar <- function(width) paste0("|", strrep("#", width), strrep(".", 20 - width), "|")

table_row <- function(values, widths) {
  cells <- mapply(function(value, width) sprintf("%*s", width, text_value(value)),
                  values, widths, USE.NAMES = FALSE)
  cat(paste(cells, collapse = ""), "\n", sep = "")
}

arity <- function(args, expected) {
  if (length(args) != expected) fail("wrong number of arguments")
}

parameter_range <- function(item) {
  if (!item %in% setting_names) fail(paste("unknown parameter", item))
  setting_ranges[[item]]
}

valid_day <- function(token, data) {
  day <- as.numeric(token)
  if (day < 1 || day > data$days) fail("invalid day")
  day
}

values_range <- function(args, bounds) {
  values <- as.numeric(args)
  low <- values[1]
  high <- values[2]
  step <- values[3]
  if (low < bounds[1] || high > bounds[2] || high < low || step < 1 ||
      (high - low) %/% step + 1 > 20) fail("invalid range")
  seq(low, high, by = step)
}

strategies <- function(tokens) {
  result <- list()
  index <- 1L
  while (index <= length(tokens)) {
    name <- tokens[index]
    index <- index + 1L
    parameter <- 0
    if (name %in% names(strategy_ranges)) {
      if (index > length(tokens)) fail(paste("missing parameter for", name))
      parameter <- as.numeric(tokens[index])
      index <- index + 1L
      bounds <- strategy_ranges[[name]]
      if (parameter < bounds[1] || parameter > bounds[2]) {
        fail(paste("invalid parameter for", name))
      }
    } else if (!name %in% c("SELF", "EXPORTPEAK")) {
      fail(paste("unknown strategy", name))
    }
    result[[length(result) + 1L]] <- list(name = name, parameter = parameter)
  }
  result
}

one_strategy <- function(tokens) {
  choices <- strategies(tokens)
  if (length(choices) != 1L) fail("wrong number of arguments")
  choices[[1]]
}

notation <- function(strategy) {
  if (strategy$name %in% names(strategy_ranges)) {
    paste(strategy$name, text_value(strategy$parameter))
  } else strategy$name
}

read_data <- function(input) {
  tokens <- function() strsplit(readLines(input, n = 1L, warn = FALSE), " ", fixed = TRUE)[[1]]
  battery <- as.numeric(tokens()[-1])
  grid <- as.numeric(tokens()[-1])
  settings <- setNames(c(battery, grid, 100), setting_names)
  count <- as.numeric(tokens()[2])
  periods <- character(count)
  prices <- numeric(count)
  for (i in seq_len(count)) {
    fields <- tokens()
    periods[i] <- fields[1]
    prices[i] <- as.numeric(fields[2])
  }
  divisions <- matrix(0, nrow = 2L, ncol = 24L)
  for (type in 1:2) {
    fields <- tokens()
    for (i in seq.int(2L, length(fields), by = 2L)) {
      first <- as.numeric(fields[i])
      last <- if (i + 2L <= length(fields)) as.numeric(fields[i + 2L]) - 1 else 23
      divisions[type, seq.int(first + 1, last + 1)] <- match(fields[i + 1L], periods)
    }
  }
  count <- as.numeric(tokens()[2])
  profiles <- list()
  for (i in seq_len(count)) {
    fields <- tokens()
    profiles[[paste(fields[1], fields[2])]] <- as.numeric(fields[-c(1, 2)])
  }
  days <- as.numeric(tokens()[2])
  loads <- generation <- matrix(0, nrow = days, ncol = 24L)
  for (day in seq_len(days)) {
    fields <- tokens()
    loads[day, ] <- (profiles[[paste("LOAD", fields[1])]] * as.numeric(fields[2])) %/% 100
    generation[day, ] <- (profiles[[paste("PV", fields[3])]] * as.numeric(fields[4])) %/% 100
  }
  holidays <- as.numeric(tokens()[-c(1, 2)])
  count <- as.numeric(tokens()[2])
  for (i in seq_len(count)) {
    values <- as.numeric(tokens())
    loads[values[1], values[2] + 1] <- values[3]
    generation[values[1], values[2] + 1] <- values[4]
  }
  weekdays <- c("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")
  day_numbers <- seq_len(days)
  weekend <- day_numbers %in% holidays | (day_numbers - 1) %% 7 >= 5
  day_names <- ifelse(day_numbers %in% holidays, "HOL", weekdays[(day_numbers - 1) %% 7 + 1])
  period_map <- divisions[ifelse(weekend, 2L, 1L), , drop = FALSE]
  hours <- cbind(day = rep(day_numbers, each = 24L), hour = rep(0:23, days),
                 period = as.vector(t(period_map)), load = as.vector(t(loads)),
                 pv = as.vector(t(generation)))
  list(data = list(days = days, periods = periods, hours = hours,
                   weekend = weekend, day_names = day_names),
       settings = settings, prices = prices)
}

net_cost <- function(records) sum(records[, "cost"]) - sum(records[, "income"])
day_records <- function(result, day) result$records[result$records[, "day"] == day, , drop = FALSE]
sufficiency <- function(result) {
  records <- result$records
  load <- sum(records[, "load"])
  percentage(max(0, load - sum(records[, "import"])), load)
}

simulate <- function(data, strategy, settings, prices, outage = NULL) {
  capacity <- settings[["CAPACITY"]]
  ceff <- settings[["CEFF"]]
  deff <- settings[["DEFF"]]
  reserve_pct <- settings[["RESERVE"]]
  if (strategy$name == "BACKUP") reserve_pct <- max(reserve_pct, strategy$parameter)
  reserve <- (capacity * reserve_pct) %/% 100
  starting <- soc <- (capacity * settings[["INITIAL"]]) %/% 100
  low <- which.min(prices)
  high <- which.max(prices)
  arbitrage <- strategy$name == "EXPORTPEAK" && settings[["FEEDIN"]] > prices[low]
  fields <- c("day", "hour", "period", "load", "pv", "charge", "discharge", "drawn",
              "soc", "import", "export", "curtailed", "shortfall", "loss", flow_names,
              "cost", "income")
  records <- matrix(0, nrow = nrow(data$hours), ncol = length(fields),
                    dimnames = list(NULL, fields))
  for (i in seq_len(nrow(data$hours))) {
    input <- data$hours[i, ]
    pv <- (input[["pv"]] * settings[["PVSCALE"]]) %/% 100
    direct <- min(input[["load"]], pv)
    surplus <- pv - direct
    deficit <- input[["load"]] - direct
    x1 <- min(surplus, settings[["CHARGE"]], ceil_div(100 * (capacity - soc), ceff))
    stored1 <- (x1 * ceff) %/% 100
    soc <- soc + stored1
    surplus <- surplus - x1
    disconnected <- !is.null(outage) && input[["day"]] == outage[1] &&
      input[["hour"]] >= outage[2] && input[["hour"]] <= outage[3]
    target <- deficit
    if (!disconnected) {
      if (strategy$name == "TOU") {
        target <- if (input[["period"]] == high) deficit else 0
      } else if (strategy$name == "PEAKSHAVE") {
        target <- max(0, deficit - strategy$parameter)
      } else if (strategy$name == "EXPORTPEAK" && arbitrage &&
                 input[["period"]] == low && low != high) {
        target <- 0
      }
    }
    lower <- if (disconnected) 0 else reserve
    y1 <- min(ceil_div(100 * target, deff), settings[["DISCHARGE"]], max(0, soc - lower))
    d1 <- (y1 * deff) %/% 100
    soc <- soc - y1
    deficit <- deficit - d1
    x2 <- y2 <- d2 <- stored2 <- 0
    if (disconnected) {
      grid <- export_pv <- 0
      shortfall <- deficit
      curtailed <- surplus
    } else {
      grid <- deficit
      shortfall <- 0
      export_pv <- min(surplus, settings[["EXPORT"]])
      curtailed <- surplus - export_pv
      headroom <- settings[["CHARGE"]] - x1
      charge_target <- NULL
      if (strategy$name == "TOU" && input[["period"]] == low && low != high) {
        charge_target <- (capacity * strategy$parameter) %/% 100
      } else if (strategy$name == "PEAKSHAVE" && input[["period"]] == low) {
        charge_target <- capacity
        headroom <- min(headroom, max(0, strategy$parameter - grid))
      } else if (strategy$name == "BACKUP" && input[["period"]] == low) {
        charge_target <- reserve
      } else if (strategy$name == "EXPORTPEAK" && arbitrage &&
                 input[["period"]] == low && low != high) {
        charge_target <- capacity
      }
      if (!is.null(charge_target)) {
        x2 <- min(headroom, ceil_div(100 * max(0, charge_target - soc), ceff))
        stored2 <- (x2 * ceff) %/% 100
        soc <- soc + stored2
      }
      if (strategy$name == "EXPORTPEAK" && arbitrage && input[["period"]] == high && x1 == 0) {
        y2 <- min(ceil_div(100 * (settings[["EXPORT"]] - export_pv), deff),
                  settings[["DISCHARGE"]] - y1, max(0, soc - reserve))
        d2 <- (y2 * deff) %/% 100
        soc <- soc - y2
      }
    }
    imported <- grid + x2
    exported <- export_pv + d2
    loss <- x1 - stored1 + x2 - stored2 + y1 - d1 + y2 - d2
    flows <- c(direct, x1, export_pv, curtailed, d1, d2, grid, x2)
    records[i, ] <- c(input[1:3], input[["load"]], pv, x1 + x2, d1 + d2, y1 + y2,
                      soc, imported, exported, curtailed, shortfall, loss, flows,
                      (imported * prices[input[["period"]]]) %/% 100000,
                      (exported * settings[["FEEDIN"]]) %/% 100000)
  }
  peak <- max(records[, "import"])
  demand <- (peak * settings[["DEMAND"]]) %/% 1000
  list(strategy = strategy, settings = settings, prices = prices, records = records,
       starting = starting, reserve = reserve, peak = peak, demand = demand,
       bill = net_cost(records) + settings[["FIXED"]] + demand)
}

baseline <- function(data, settings, prices) {
  settings[["CAPACITY"]] <- 0
  simulate(data, list(name = "SELF", parameter = 0), settings, prices)
}

configure <- function(data, settings, prices) {
  emit("BATTERY capacity", settings[["CAPACITY"]], "initial", settings[["INITIAL"]],
       "charge", settings[["CHARGE"]], "discharge", settings[["DISCHARGE"]],
       "ceff", settings[["CEFF"]], "deff", settings[["DEFF"]],
       "reserve", settings[["RESERVE"]], "cost", settings[["COST"]])
  emit("GRID export", settings[["EXPORT"]], "feedin", settings[["FEEDIN"]],
       "fixed", settings[["FIXED"]], "demand", settings[["DEMAND"]])
  emit("SOLAR pvscale", settings[["PVSCALE"]])
  tariff <- paste(data$periods, text_value(prices), collapse = " ")
  emit("TARIFF", tariff, "cheapest", data$periods[which.min(prices)],
       "peak", data$periods[which.max(prices)])
}

hourly <- function(data, result, day) {
  emit("HOURLY day", day, data$day_names[day], "strategy", notation(result$strategy))
  emit("hour   load     pv charge  disch    soc import export   curt")
  records <- day_records(result, day)
  fields <- c("hour", "load", "pv", "charge", "discharge", "soc", "import", "export", "curtailed")
  widths <- c(4, rep(7, 8))
  for (i in seq_len(nrow(records))) table_row(records[i, fields], widths)
  totals <- as.list(colSums(records[, fields, drop = FALSE]))
  totals[[1]] <- "sum"
  totals[[6]] <- ""
  table_row(totals, widths)
}

daily <- function(data, result) {
  emit("DAILY strategy", notation(result$strategy))
  emit("day name    load      pv  import  export    curt     soc      cost")
  for (day in seq_len(data$days)) {
    records <- day_records(result, day)
    totals <- colSums(records)
    table_row(list(day, data$day_names[day], totals[["load"]], totals[["pv"]],
                   totals[["import"]], totals[["export"]], totals[["curtailed"]],
                   records[nrow(records), "soc"], money(net_cost(records))),
              c(3, 5, rep(8, 6), 10))
  }
  totals <- colSums(result$records)
  emit("TOTAL load", totals[["load"]], "pv", totals[["pv"]], "import", totals[["import"]],
       "export", totals[["export"]], "curtailed", totals[["curtailed"]],
       "cost", money(net_cost(result$records)))
}

billing <- function(data, result) {
  emit("BILL strategy", notation(result$strategy), "days", data$days)
  records <- result$records
  for (i in seq_along(data$periods)) {
    selected <- records[records[, "period"] == i, , drop = FALSE]
    emit("IMPORT", data$periods[i], sum(selected[, "import"]), "Wh", money(sum(selected[, "cost"])))
  }
  emit("EXPORT", sum(records[, "export"]), "Wh", money(-sum(records[, "income"])))
  emit("FIXED", money(result$settings[["FIXED"]]))
  emit("DEMAND", result$peak, "Wh", money(result$demand))
  emit("TOTAL", money(result$bill))
}

savings <- function(data, result) {
  original <- baseline(data, result$settings, result$prices)
  emit("SAVINGS strategy", notation(result$strategy))
  show <- function(name, before, after) {
    emit(name, money(before), "->", money(after), "saving", money(before - after))
  }
  for (i in seq_along(data$periods)) {
    before <- original$records[original$records[, "period"] == i, "cost"]
    after <- result$records[result$records[, "period"] == i, "cost"]
    show(data$periods[i], sum(before), sum(after))
  }
  show("EXPORT", -sum(original$records[, "income"]), -sum(result$records[, "income"]))
  show("DEMAND", original$demand, result$demand)
  show("TOTAL", original$bill, result$bill)
}

grouped_report <- function(command, data, result) {
  emit(command, "strategy", notation(result$strategy))
  records <- result$records
  if (command == "BYPERIOD") {
    for (i in seq_along(data$periods)) {
      selected <- records[records[, "period"] == i, , drop = FALSE]
      totals <- colSums(selected)
      emit(data$periods[i], "hours", nrow(selected), "load", totals[["load"]],
           "pv", totals[["pv"]], "charge", totals[["charge"]], "discharge", totals[["discharge"]],
           "import", totals[["import"]], "export", totals[["export"]])
    }
  } else {
    for (weekend in c(FALSE, TRUE)) {
      days <- sum(data$weekend == weekend)
      selected <- records[data$weekend[records[, "day"]] == weekend, , drop = FALSE]
      totals <- colSums(selected)
      cost <- net_cost(selected)
      emit(if (weekend) "WEEKEND" else "WEEKDAY", "days", days,
           "load", totals[["load"]] %/% days, "pv", totals[["pv"]] %/% days,
           "import", totals[["import"]] %/% days, "export", totals[["export"]] %/% days,
           "cost", money(sign(cost) * (abs(cost) %/% days)))
    }
  }
}

usage <- function(result) {
  records <- result$records
  low <- records[, "soc"] <= result$reserve
  runs <- rle(low)
  lengths <- ifelse(runs$values, runs$lengths, 0L)
  longest <- max(lengths)
  text <- c("USAGE charging", sum(records[, "charge"] > 0),
            "discharging", sum(records[, "drawn"] > 0),
            "idle", sum(records[, "charge"] == 0 & records[, "drawn"] == 0),
            "full", sum(records[, "soc"] == result$settings[["CAPACITY"]]),
            "low", sum(low), "longest", longest)
  if (longest > 0) {
    run <- which.max(lengths)
    start <- sum(runs$lengths[seq_len(run - 1L)]) + 1L
    text <- c(text, "from day", records[start, "day"], "hour", records[start, "hour"])
  }
  emit(text)
}

report <- function(command, data, result) {
  records <- result$records
  strategy <- notation(result$strategy)
  if (command == "DAILY") {
    daily(data, result)
  } else if (command == "BILL") {
    billing(data, result)
  } else if (command == "SAVINGS") {
    savings(data, result)
  } else if (command %in% c("BYPERIOD", "DAYTYPE")) {
    grouped_report(command, data, result)
  } else if (command == "PROFILE") {
    emit("PROFILE strategy", strategy, "days", data$days)
    emit("hour   load     pv import export    soc")
    fields <- c("load", "pv", "import", "export", "soc")
    for (hour in 0:23) {
      selected <- records[records[, "hour"] == hour, fields, drop = FALSE]
      table_row(c(hour, colSums(selected) %/% data$days), c(4, rep(7, 5)))
    }
  } else if (command == "FLOWS") {
    emit("FLOWS strategy", strategy)
    for (name in flow_names) emit(name, sum(records[, name]))
    emit("LOSSES", sum(records[, "loss"]))
    emit("STORED", records[nrow(records), "soc"] - result$starting)
  } else if (command == "SELFSUFF") {
    consumed <- sum(records[, "PV>LOAD"]) + sum(records[, "PV>BATTERY"])
    emit("SELFSUFF sufficiency", paste0(sufficiency(result), "%"),
         "consumption", paste0(percentage(consumed, sum(records[, "pv"])), "%"))
  } else if (command == "CYCLES") {
    drawn <- sum(records[, "drawn"])
    capacity <- result$settings[["CAPACITY"]]
    a <- drawn
    b <- capacity
    while (b != 0) {
      remainder <- a %% b
      a <- b
      b <- remainder
    }
    fraction <- paste0(text_value(drawn %/% a), "/", text_value(capacity %/% a))
    emit("CYCLES", fraction, decimal(drawn, capacity, 3),
         "drawn", drawn, "losses", sum(records[, "loss"]))
  } else if (command == "USAGE") {
    usage(result)
  } else if (command == "HISTOGRAM") {
    emit("HISTOGRAM strategy", strategy)
    bands <- pmin(9, (10 * records[, "soc"]) %/% result$settings[["CAPACITY"]])
    counts <- tabulate(bands + 1L, nbins = 10L)
    for (i in 0:9) {
      emit(paste0(sprintf("%3.0f", 10 * i), "%"),
           bar((20 * counts[i + 1L]) %/% nrow(records)), counts[i + 1L])
    }
  }
}

outage_report <- function(data, result, day, first, last) {
  alternate <- simulate(data, result$strategy, result$settings, result$prices, c(day, first, last))
  start <- (day - 1) * 24 + first + 1
  before <- if (start == 1) alternate$starting else alternate$records[start - 1, "soc"]
  emit("OUTAGE day", day, "hours", paste0(text_value(first), "-", text_value(last)),
       "strategy", notation(result$strategy), "soc", before)
  emit("hour   load     pv  disch    soc  short   curt")
  records <- alternate$records[seq.int(start, (day - 1) * 24 + last + 1), , drop = FALSE]
  fields <- c("hour", "load", "pv", "discharge", "soc", "shortfall", "curtailed")
  for (i in seq_len(nrow(records))) table_row(records[i, fields], c(4, rep(7, 6)))
  load <- sum(records[, "load"])
  shortfall <- sum(records[, "shortfall"])
  served <- if (load == 0) "100.00" else percentage(load - shortfall, load)
  emit("TOTAL load", load, "unserved", shortfall, "served", paste0(served, "%"),
       "bill", money(alternate$bill))
}

difference <- function(data, result, day, strategy) {
  alternate <- simulate(data, strategy, result$settings, result$prices)
  emit("DIFF day", day, data$day_names[day], notation(result$strategy), "vs", notation(strategy))
  emit("hour   imp1   imp2   exp1   exp2   soc1   soc2")
  left <- day_records(result, day)
  right <- day_records(alternate, day)
  for (i in seq_len(nrow(left))) {
    table_row(c(left[i, "hour"], left[i, "import"], right[i, "import"],
                left[i, "export"], right[i, "export"], left[i, "soc"], right[i, "soc"]),
              c(4, rep(7, 6)))
  }
  cost1 <- net_cost(left)
  cost2 <- net_cost(right)
  emit("TOTAL cost1", money(cost1), "cost2", money(cost2), "difference", money(cost2 - cost1))
}

comparisons <- function(command, args, data, settings, prices) {
  if (command == "COMPARE") {
    choices <- strategies(args)
    if (length(choices) == 0L) fail("wrong number of arguments")
    base <- baseline(data, settings, prices)$bill
    results <- lapply(choices, function(strategy) simulate(data, strategy, settings, prices))
    bills <- vapply(results, function(result) result$bill, numeric(1))
    ordering <- order(bills, seq_along(results))
    emit("COMPARE baseline", money(base))
    for (rank in seq_along(ordering)) {
      result <- results[[ordering[rank]]]
      emit(paste0(rank, "."), notation(result$strategy), "bill", money(result$bill),
           "saving", money(base - result$bill), "sufficiency", paste0(sufficiency(result), "%"))
    }
  } else if (command == "SIZE") {
    arity(args, 3L)
    values <- values_range(args, c(1, 100000))
    base <- baseline(data, settings, prices)$bill
    best <- NULL
    for (capacity in values) {
      changed <- settings
      changed[["CAPACITY"]] <- capacity
      result <- simulate(data, list(name = "SELF", parameter = 0), changed, prices)
      saving <- base - result$bill
      cost <- (capacity * settings[["COST"]]) %/% 1000
      payback <- if (saving > 0) decimal(cost, saving, 1) else "never"
      emit("SIZE", capacity, "bill", money(result$bill), "saving", money(saving),
           "cost", money(cost), "payback", payback)
      if (saving > 0 && (is.null(best) || cost * best$saving < best$cost * saving)) {
        best <- list(capacity = capacity, cost = cost, saving = saving)
      }
    }
    emit("BEST", if (is.null(best)) "none" else best$capacity)
  } else {
    if (length(args) < 5L) fail("wrong number of arguments")
    item <- args[1]
    bounds <- parameter_range(item)
    values <- values_range(args[2:4], bounds)
    strategy <- one_strategy(args[5:length(args)])
    best <- NULL
    for (value in values) {
      changed <- settings
      changed[[item]] <- value
      result <- simulate(data, strategy, changed, prices)
      base <- baseline(data, changed, prices)$bill
      emit("SWEEP", item, value, "bill", money(result$bill), "saving", money(base - result$bill),
           "sufficiency", paste0(sufficiency(result), "%"))
      if (is.null(best) || result$bill < best$bill) best <- list(value = value, bill = result$bill)
    }
    emit("BEST", best$value)
  }
}

main <- function() {
  input <- file("stdin", open = "r")
  on.exit(close(input))
  initial <- read_data(input)
  data <- initial$data
  settings <- initial$settings
  prices <- initial$prices
  result <- NULL
  repeat {
    line <- readLines(input, n = 1L, warn = FALSE)
    if (length(line) == 0L) break
    fields <- strsplit(line, " ", fixed = TRUE)[[1]]
    command <- fields[1]
    args <- fields[-1]
    if (command == "END") break
    tryCatch({
      if (command == "RUN") {
        strategy <- one_strategy(args)
        result <- simulate(data, strategy, settings, prices)
        records <- result$records
        emit("RUN", notation(strategy), "bill", money(result$bill),
             "import", sum(records[, "import"]), "export", sum(records[, "export"]),
             "soc", records[nrow(records), "soc"])
      } else if (command == "SET") {
        arity(args, 2L)
        item <- args[1]
        bounds <- parameter_range(item)
        value <- as.numeric(args[2])
        if (value < bounds[1] || value > bounds[2]) fail(paste("invalid value for", item))
        previous <- settings[[item]]
        settings[[item]] <- value
        emit("SET", item, previous, "->", value)
      } else if (command == "PRICE") {
        arity(args, 2L)
        index <- match(args[1], data$periods)
        if (is.na(index)) fail(paste("unknown period", args[1]))
        value <- as.numeric(args[2])
        if (value < 0 || value > 10000) fail(paste("invalid value for", args[1]))
        previous <- prices[index]
        prices[index] <- value
        emit("PRICE", args[1], previous, "->", value,
             "cheapest", data$periods[which.min(prices)], "peak", data$periods[which.max(prices)])
      } else if (command == "RESET") {
        arity(args, 0L)
        settings <- initial$settings
        prices <- initial$prices
        emit("RESET")
      } else if (command == "CONFIG") {
        arity(args, 0L)
        configure(data, settings, prices)
      } else if (command == "NOBATTERY") {
        arity(args, 0L)
        base <- baseline(data, settings, prices)
        totals <- colSums(base$records)
        emit("NOBATTERY bill", money(base$bill), "import", totals[["import"]],
             "export", totals[["export"]], "curtailed", totals[["curtailed"]], "peak", base$peak)
      } else if (command %in% c("COMPARE", "SIZE", "SWEEP")) {
        comparisons(command, args, data, settings, prices)
      } else if (command == "OUTAGE") {
        arity(args, 3L)
        day <- valid_day(args[1], data)
        hours <- as.numeric(args[2:3])
        if (hours[1] < 0 || hours[1] > hours[2] || hours[2] > 23) fail("invalid hours")
        if (is.null(result)) fail("no run")
        outage_report(data, result, day, hours[1], hours[2])
      } else if (command == "DIFF") {
        if (length(args) < 2L) fail("wrong number of arguments")
        day <- valid_day(args[1], data)
        strategy <- one_strategy(args[-1])
        if (is.null(result)) fail("no run")
        difference(data, result, day, strategy)
      } else if (command %in% c("HOURLY", "CHART")) {
        arity(args, 1L)
        day <- valid_day(args[1], data)
        if (is.null(result)) fail("no run")
        if (command == "HOURLY") {
          hourly(data, result, day)
        } else {
          emit("CHART day", day, data$day_names[day], "strategy", notation(result$strategy))
          capacity <- result$settings[["CAPACITY"]]
          records <- day_records(result, day)
          for (i in seq_len(nrow(records))) {
            soc <- records[i, "soc"]
            emit(sprintf("%2.0f", records[i, "hour"]), bar((20 * soc) %/% capacity),
                 paste0(percentage(soc, capacity), "%"))
          }
        }
      } else if (command == "PEAKS") {
        arity(args, 1L)
        count <- as.numeric(args[1])
        if (count < 1) fail("invalid count")
        if (is.null(result)) fail("no run")
        emit("PEAKS strategy", notation(result$strategy))
        records <- result$records[result$records[, "import"] > 0, , drop = FALSE]
        ordering <- order(-records[, "import"], records[, "day"], records[, "hour"])
        for (rank in seq_len(min(count, length(ordering)))) {
          record <- records[ordering[rank], ]
          emit(paste0(rank, "."), "day", record[["day"]], "hour", record[["hour"]],
               data$periods[record[["period"]]], "import", record[["import"]],
               "load", record[["load"]], "soc", record[["soc"]])
        }
        if (nrow(records) == 0L) emit("none")
      } else if (command %in% report_names) {
        arity(args, 0L)
        if (is.null(result)) fail("no run")
        report(command, data, result)
      } else {
        fail(paste("unknown command", command))
      }
    }, command_error = function(error) emit("ERROR", conditionMessage(error)))
  }
}

main()
