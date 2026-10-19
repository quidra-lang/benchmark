options(scipen = 999)

stage_names <- c("RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY")
policy_parameters <- c(FIXED = 1, PASS = 0, BASESTOCK = 1, MINMAX = 2,
                       MOVAVG = 2, SMOOTH = 2, STERMAN = 4)
modes <- c(ORDERS = "order", INV = "inventory", BACK = "backlog")

fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("GameError", "error", "condition")))
}
conditionMessage.GameError <- function(error) error$message

integer <- function(value) sprintf("%.0f", value)
money <- function(value) {
  paste0(integer(floor(value / 100)), ".",
         sprintf("%02d", as.integer(value %% 100)))
}
decimal <- function(numerator, denominator, places) {
  scale <- 10^places
  whole <- floor(numerator / denominator)
  remainder <- numerator - whole * denominator
  fraction <- floor(remainder * scale / denominator)
  paste0(integer(whole), ".", sprintf(paste0("%0", places, "d"), as.integer(fraction)))
}
variation <- function(values) {
  length(values) * sum(values * values) - sum(values)^2
}
encode <- function(values, separator = ",") {
  paste(vapply(values, integer, character(1)), collapse = separator)
}
right <- function(value, width) {
  sprintf("%*s", width, as.character(value))
}
record_values <- function(records, name) {
  vapply(records, function(record) record[[name]], numeric(1))
}
record_sum <- function(records, name) {
  sum(record_values(records, name))
}
sum_costs <- function(simulation) {
  vapply(simulation$stages, function(stage) record_sum(stage$records, "cost"),
         numeric(1))
}

parse_policy <- function(tokens) {
  name <- tokens[1]
  if (!(name %in% names(policy_parameters))) fail(paste("unknown policy", name))
  count <- policy_parameters[[name]]
  if (length(tokens) - 1 != count)
    fail(paste(name, "needs", count, "parameters"))
  values <- numeric(count)
  for (i in seq_len(count)) {
    token <- tokens[i + 1]
    values[i] <- as.numeric(if (name == "STERMAN" && i <= 3)
      gsub(".", "", token, fixed = TRUE) else token)
  }
  valid <- switch(
    name,
    FIXED = 0 <= values[1] && values[1] <= 1000,
    PASS = TRUE,
    BASESTOCK = 0 <= values[1] && values[1] <= 10000,
    MINMAX = 0 <= values[1] && values[1] < values[2] && values[2] <= 10000,
    MOVAVG = 1 <= values[1] && values[1] <= 52 &&
      0 <= values[2] && values[2] <= 10000,
    SMOOTH = 1 <= values[1] && values[1] <= 10 &&
      0 <= values[2] && values[2] <= 10000,
    STERMAN = all(values[1:3] >= 0 & values[1:3] <= 100) &&
      0 <= values[4] && values[4] <= 10000
  )
  if (!valid) fail(paste("invalid parameter for", name))
  list(name = name, args = values, text = paste(tokens, collapse = " "))
}

new_stage <- function(initial) {
  stage <- new.env(parent = emptyenv())
  stage$inventory <- initial$inventory
  stage$backlog <- 0
  stage$shipping <- rep(initial$quantity, initial$shipping)
  stage$orders <- rep(initial$quantity, initial$orders)
  stage$policy <- initial$policy
  stage$expected <- 100 * initial$quantity
  stage$holding <- initial$holding
  stage$backlog_rate <- initial$backlog
  stage$lot <- 1
  stage$capacity <- NULL
  stage$records <- list()
  stage
}

new_simulation <- function(initials, demands) {
  simulation <- new.env(parent = emptyenv())
  simulation$initials <- initials
  simulation$week <- 0
  simulation$demands <- demands
  simulation$stages <- lapply(initials, new_stage)
  simulation$plant_backlog <- 0
  simulation$plant_capacity <- NULL
  simulation$plant_records <- list()
  simulation$visibility <- "OFF"
  simulation
}

clone_state <- function(state) {
  unserialize(serialize(state, NULL))
}

signal <- function(simulation, index, week, current = NULL) {
  if (simulation$visibility == "ON") return(simulation$demands[week])
  if (!is.null(current) && week == simulation$week + 1)
    return(current[index])
  simulation$stages[[index]]$records[[week]]$incoming
}

set_policy <- function(simulation, index, policy) {
  stage <- simulation$stages[[index]]
  stage$policy <- policy
  if (policy$name == "STERMAN") {
    previous <- if (simulation$week > 0)
      signal(simulation, index, simulation$week) else
        simulation$initials[[index]]$quantity
    stage$expected <- 100 * previous
  }
}

positions <- function(simulation) {
  supply <- numeric(4)
  position <- numeric(4)
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    upstream <- if (index < 4)
      simulation$stages[[index + 1]]$backlog else simulation$plant_backlog
    line <- sum(stage$orders) + upstream + sum(stage$shipping)
    supply[index] <- line
    position[index] <- stage$inventory + line - stage$backlog
  }
  list(supply = supply, position = position)
}

policy_order <- function(simulation, index, incoming, line, position) {
  stage <- simulation$stages[[index]]
  name <- stage$policy$name
  args <- stage$policy$args
  week <- simulation$week + 1
  demand <- signal(simulation, index, week, incoming)
  if (name == "FIXED") return(args[1])
  if (name == "PASS") return(incoming[index])
  if (name == "BASESTOCK") return(max(0, args[1] - position))
  if (name == "MINMAX")
    return(if (position <= args[1]) args[2] - position else 0)
  if (name == "MOVAVG") {
    count <- min(args[1], week)
    observations <- vapply(seq.int(week - count + 1, week),
                           function(u) signal(simulation, index, u, incoming), numeric(1))
    forecast <- floor(sum(observations) / count)
    delay <- simulation$initials[[index]]$shipping +
      simulation$initials[[index]]$orders
    return(max(0, args[2] + forecast * delay - position))
  }
  if (name == "SMOOTH") {
    return(max(0, demand + floor((args[2] - position) / args[1])))
  }
  theta <- args[1]
  alpha <- args[2]
  beta <- args[3]
  target <- args[4]
  stage$expected <- floor((100 * theta * demand +
                             (100 - theta) * stage$expected) / 100)
  net <- stage$inventory - stage$backlog
  max(0, floor((100 * stage$expected +
                  alpha * (100 * (target - net) - beta * line)) / 10000))
}

simulation_step <- function(simulation) {
  received <- numeric(4)
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    received[index] <- stage$shipping[1]
    stage$shipping <- stage$shipping[-1]
    stage$inventory <- stage$inventory + received[index]
  }
  incoming <- c(simulation$demands[simulation$week + 1],
                vapply(simulation$stages[1:3], function(stage)
                  stage$orders[1], numeric(1)))
  plant_incoming <- simulation$stages[[4]]$orders[1]
  for (stage in simulation$stages) stage$orders <- stage$orders[-1]

  records <- list()
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    before <- stage$backlog
    requested <- before + incoming[index]
    shipped <- min(stage$inventory, requested)
    if (!is.null(stage$capacity)) shipped <- min(shipped, stage$capacity)
    stage$inventory <- stage$inventory - shipped
    stage$backlog <- requested - shipped
    if (index > 1) {
      downstream <- simulation$stages[[index - 1]]
      downstream$shipping <- c(downstream$shipping, shipped)
    }
    records[[index]] <- list(
      received = received[index], incoming = incoming[index], shipped = shipped,
      before = before,
      ontime = min(max(0, shipped - before), incoming[index]),
      inventory = stage$inventory, backlog = stage$backlog
    )
  }
  requested <- simulation$plant_backlog + plant_incoming
  produced <- if (is.null(simulation$plant_capacity))
    requested else min(requested, simulation$plant_capacity)
  simulation$plant_backlog <- requested - produced
  factory <- simulation$stages[[4]]
  factory$shipping <- c(factory$shipping, produced)

  pipeline <- positions(simulation)
  orders <- vapply(1:4, function(i)
    policy_order(simulation, i, incoming, pipeline$supply[i],
                 pipeline$position[i]), numeric(1))
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    quantity <- floor((orders[index] + stage$lot - 1) / stage$lot) * stage$lot
    stage$orders <- c(stage$orders, quantity)
    record <- records[[index]]
    record$order <- quantity
    record$holding <- stage$holding * stage$inventory
    record$backlog_cost <- stage$backlog_rate * stage$backlog
    record$cost <- record$holding + record$backlog_cost
    stage$records[[length(stage$records) + 1]] <- record
    records[[index]] <- record
  }
  simulation$plant_records[[length(simulation$plant_records) + 1]] <-
    list(incoming = plant_incoming, produced = produced,
         backlog = simulation$plant_backlog)
  simulation$week <- simulation$week + 1
  records
}

game <- new.env(parent = emptyenv())
game$initials <- list()
game$base <- numeric()
game$simulation <- NULL
game$snapshots <- new.env(hash = TRUE, parent = emptyenv())
game$output <- character()

emit <- function(...) {
  items <- vapply(list(...), as.character, character(1))
  game$output <- c(game$output, paste(items, collapse = " "))
}

stage_index <- function(text) {
  index <- match(text, stage_names)
  if (is.na(index)) fail(paste("unknown stage", text))
  index
}
target <- function(text) {
  if (text == "ALL") 1:4 else stage_index(text)
}
require_weeks <- function() {
  if (game$simulation$week == 0) fail("no weeks simulated")
}
range_check <- function(arguments, limit) {
  if (!length(arguments)) return(c(1, limit))
  first <- as.numeric(arguments[1])
  last <- as.numeric(arguments[2])
  if (!(1 <= first && first <= last && last <= limit))
    fail(paste("bad range", arguments[1], arguments[2]))
  c(first, last)
}
mode_check <- function(mode) {
  if (!(mode %in% c("ORDERS", "INV", "BACK", "NET")))
    fail(paste("unknown mode", mode))
}
values_for <- function(index, mode, simulation = game$simulation) {
  records <- simulation$stages[[index]]$records
  if (mode == "NET")
    return(record_values(records, "inventory") - record_values(records, "backlog"))
  record_values(records, modes[[mode]])
}
initialize <- function(demands = NULL) {
  if (!is.null(demands)) game$base <- demands
  game$simulation <- new_simulation(game$initials, game$base)
}
trial <- function(policies) {
  current <- game$simulation
  trial_state <- new_simulation(game$initials, current$demands)
  trial_state$visibility <- current$visibility
  trial_state$plant_capacity <- current$plant_capacity
  for (index in 1:4) {
    stage <- trial_state$stages[[index]]
    previous <- current$stages[[index]]
    stage$lot <- previous$lot
    stage$capacity <- previous$capacity
    stage$holding <- previous$holding
    stage$backlog_rate <- previous$backlog_rate
    set_policy(trial_state, index, policies[[index]])
  }
  while (trial_state$week < length(trial_state$demands)) simulation_step(trial_state)
  trial_state
}
set_demand <- function(values) {
  initialize(values)
  emit("DEMAND", "weeks", length(values), "total", sum(values),
       "min", min(values), "max", max(values))
}
generate <- function(arguments) {
  weeks <- as.numeric(arguments[1])
  base <- as.numeric(arguments[2])
  spread <- as.numeric(arguments[3])
  seed <- as.numeric(arguments[4])
  changes <- list()
  positions <- seq.int(5, length(arguments), by = 3)
  if (length(arguments) < 5) positions <- integer()
  for (position in positions) {
    change <- list(kind = arguments[position],
                   week = as.numeric(arguments[position + 1]),
                   amount = as.numeric(arguments[position + 2]))
    if (!(1 <= change$week && change$week <= weeks))
      fail(paste("week", change$week, "outside horizon"))
    changes[[length(changes) + 1]] <- change
  }
  levels <- numeric(weeks)
  for (week in seq_len(weeks)) {
    level <- base
    for (change in changes) {
      if (change$kind == "STEP" && week >= change$week)
        level <- level + change$amount
      else if (change$kind == "PULSE" && week == change$week)
        level <- level + change$amount
      else if (change$kind == "RAMP" && week >= change$week)
        level <- level + change$amount * (week - change$week + 1)
    }
    if (level < 0) fail(paste("negative level at week", week))
    levels[week] <- level
  }
  values <- numeric(weeks)
  for (week in seq_len(weeks)) {
    seed <- (48271 * seed) %% 2147483647
    values[week] <- levels[week] + seed %% spread
  }
  set_demand(values)
}

show_status <- function() {
  simulation <- game$simulation
  emit("STATUS", "week", simulation$week, "of", length(simulation$demands))
  pipeline <- positions(simulation)
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    text <- paste(stage_names[index], "inv", integer(stage$inventory),
                  "back", integer(stage$backlog),
                  "transit", encode(stage$shipping),
                  "pending", encode(stage$orders),
                  "supply", integer(pipeline$supply[index]),
                  "position", integer(pipeline$position[index]),
                  "policy", stage$policy$text)
    if (stage$policy$name == "STERMAN")
      text <- paste(text, "expect", money(stage$expected))
    emit(text)
  }
  emit("PLANT", "back", simulation$plant_backlog)
}

show_week <- function(week) {
  simulation <- game$simulation
  emit("WEEK", week, "demand", simulation$demands[week])
  for (index in 1:4) {
    record <- simulation$stages[[index]]$records[[week]]
    emit(stage_names[index], "recv", record$received, "in", record$incoming,
         "ship", record$shipped, "inv", record$inventory,
         "back", record$backlog, "order", record$order,
         "cost", money(record$cost))
  }
  plant <- simulation$plant_records[[week]]
  emit("PLANT", "in", plant$incoming, "made", plant$produced,
       "back", plant$backlog)
}

show_table <- function(index, first, last) {
  records <- game$simulation$stages[[index]]$records
  emit("TABLE", stage_names[index], paste0(first, "-", last))
  labels <- c("week", "in", "ship", "recv", "inv", "back", "order", "cost")
  widths <- c(4, 6, 6, 6, 6, 6, 6, 9)
  emit(paste(mapply(right, labels, widths, USE.NAMES = FALSE), collapse = " "))
  for (week in seq.int(first, last)) {
    record <- records[[week]]
    values <- c(week, record$incoming, record$shipped, record$received,
                record$inventory, record$backlog, record$order, money(record$cost))
    emit(paste(mapply(right, as.character(values), widths, USE.NAMES = FALSE),
               collapse = " "))
  }
}

show_costs <- function() {
  simulation <- game$simulation
  emit("COSTS", "week", simulation$week)
  total_holding <- 0
  total_backlog <- 0
  for (index in 1:4) {
    stage <- simulation$stages[[index]]
    holding <- record_sum(stage$records, "holding")
    backlog <- record_sum(stage$records, "backlog_cost")
    total_holding <- total_holding + holding
    total_backlog <- total_backlog + backlog
    emit(stage_names[index], "holding", money(holding),
         "backlog", money(backlog), "total", money(holding + backlog))
  }
  emit("TOTAL", "holding", money(total_holding),
       "backlog", money(total_backlog),
       "total", money(total_holding + total_backlog))
}

fill_text <- function(records) {
  ordered <- record_sum(records, "incoming")
  ontime <- record_sum(records, "ontime")
  fill <- if (ordered == 0) "n/a" else paste0(decimal(ontime * 100, ordered, 2), "%")
  list(ordered = ordered, ontime = ontime, fill = fill)
}

show_bullwhip <- function() {
  simulation <- game$simulation
  n <- simulation$week
  demands <- simulation$demands[seq_len(n)]
  demand_var <- variation(demands)
  emit("BULLWHIP", "weeks", paste0("1-", n), "demand",
       "mean", decimal(sum(demands), n, 4),
       "var", decimal(demand_var, n * n, 4))
  previous <- demand_var
  for (index in 1:4) {
    values <- record_values(simulation$stages[[index]]$records, "order")
    current <- variation(values)
    emit(stage_names[index], "mean", decimal(sum(values), n, 4),
         "var", decimal(current, n * n, 4),
         "ratio", if (demand_var == 0) "n/a" else decimal(current, demand_var, 4),
         "step", if (previous == 0) "n/a" else decimal(current, previous, 4))
    previous <- current
  }
}

show_peaks <- function() {
  simulation <- game$simulation
  emit("PEAKS", "weeks", paste0("1-", simulation$week))
  for (index in 1:4) {
    records <- simulation$stages[[index]]$records
    inventories <- record_values(records, "inventory")
    backlogs <- record_values(records, "backlog")
    max_inventory <- max(inventories)
    max_backlog <- max(backlogs)
    longest <- 0
    run <- 0
    first <- 0
    best_first <- 0
    best_last <- 0
    for (week in seq_along(backlogs)) {
      if (backlogs[week] > 0) {
        if (run == 0) first <- week
        run <- run + 1
        if (run > longest) {
          longest <- run
          best_first <- first
          best_last <- week
        }
      } else {
        run <- 0
      }
    }
    stockout <- if (longest)
      paste(longest, "weeks", paste0(best_first, "-", best_last)) else "0"
    emit(stage_names[index], "max_inv", max_inventory,
         "week", if (max_inventory) which.max(inventories) else "-",
         "max_back", max_backlog,
         "week", if (max_backlog) which.max(backlogs) else "-",
         "longest_stockout", stockout)
  }
}

show_leadtime <- function(index) {
  simulation <- game$simulation
  stage <- simulation$stages[[index]]
  initial <- game$initials[[index]]
  nominal <- initial$shipping + initial$orders
  cumulative <- cumsum(record_values(stage$records, "received")) -
    nominal * initial$quantity
  ordered <- 0
  count <- 0
  leads <- numeric()
  for (t in seq_along(stage$records)) {
    record <- stage$records[[t]]
    ordered <- ordered + record$order
    if (record$order == 0) next
    count <- count + 1
    if (t < length(stage$records)) {
      for (u in seq.int(t + 1, length(stage$records))) {
        if (cumulative[u] >= ordered) {
          leads <- c(leads, u - t)
          break
        }
      }
    }
  }
  emit("LEADTIME", stage_names[index], "nominal", nominal,
       "orders", count, "completed", length(leads),
       "open", count - length(leads),
       "min", if (length(leads)) min(leads) else "-",
       "avg", if (length(leads)) decimal(sum(leads), length(leads), 2) else "-",
       "max", if (length(leads)) max(leads) else "-")
}

show_plot <- function(index, mode, first, last) {
  values <- values_for(index, mode)[seq.int(first, last)]
  maximum <- max(values)
  if (mode == "NET") {
    emit("PLOT", stage_names[index], mode, paste0(first, "-", last),
         "min", min(values), "max", maximum)
    scale <- max(abs(values))
    for (i in seq_along(values)) {
      week <- first + i - 1
      value <- values[i]
      size <- if (scale) floor(abs(value) * 25 / scale) else 0
      left <- if (value < 0)
        paste0(strrep(" ", 25 - size), strrep("-", size)) else strrep(" ", 25)
      right_bar <- if (value > 0) strrep("+", size) else ""
      emit(paste0(right(week, 3), " ", left, "|", right_bar, " ", integer(value)))
    }
  } else {
    emit("PLOT", stage_names[index], mode, paste0(first, "-", last),
         "max", maximum)
    for (i in seq_along(values)) {
      week <- first + i - 1
      value <- values[i]
      size <- if (maximum) floor(value * 50 / maximum) else 0
      emit(paste0(right(week, 3), " |", strrep("#", size), " ", integer(value)))
    }
  }
}

show_histogram <- function(index, mode, width) {
  simulation <- game$simulation
  bins <- floor(values_for(index, mode) / width)
  emit("HISTOGRAM", stage_names[index], mode, "width", width,
       "weeks", paste0("1-", simulation$week))
  for (bucket in seq.int(min(bins), max(bins))) {
    count <- sum(bins == bucket)
    text <- paste0(integer(bucket * width), "..",
                   integer(bucket * width + width - 1), " ", count)
    if (count) text <- paste(text, strrep("*", count))
    emit(text)
  }
}

run_command <- function(command, a) {
  simulation <- game$simulation
  if (command == "DEMAND") {
    set_demand(as.numeric(a))
  } else if (command == "GENERATE") {
    generate(a)
  } else if (command == "RUN") {
    if (simulation$week == length(simulation$demands))
      fail(paste("horizon reached at week", length(simulation$demands)))
    first <- simulation$week + 1
    count <- min(as.numeric(a[1]), length(simulation$demands) - simulation$week)
    total_cost <- 0
    for (i in seq_len(count)) {
      records <- simulation_step(simulation)
      for (index in 1:4) {
        record <- records[[index]]
        total_cost <- total_cost + record$cost
        if (record$before == 0 && record$backlog > 0)
          emit("STOCKOUT", stage_names[index], "week", simulation$week,
               "backlog", record$backlog)
        else if (record$before > 0 && record$backlog == 0)
          emit("RECOVER", stage_names[index], "week", simulation$week)
      }
    }
    emit("RUN", paste0(first, "-", simulation$week), "demand",
         sum(simulation$demands[seq.int(first, simulation$week)]),
         "cost", money(total_cost))
    if (simulation$week == length(simulation$demands))
      emit("HORIZON", simulation$week)
  } else if (command == "RESET") {
    initialize()
    emit("RESET", "week", 0)
  } else if (command == "SAVE") {
    assign(a[1], clone_state(simulation), envir = game$snapshots)
    emit("SAVE", a[1], "week", simulation$week)
  } else if (command == "LOAD") {
    if (!exists(a[1], envir = game$snapshots, inherits = FALSE))
      fail(paste("no snapshot", a[1]))
    game$simulation <- clone_state(get(a[1], envir = game$snapshots,
                                       inherits = FALSE))
    emit("LOAD", a[1], "week", game$simulation$week)
  } else if (command == "SET") {
    indices <- target(a[1])
    policy <- parse_policy(a[-1])
    for (index in indices) set_policy(simulation, index, policy)
    emit("SET", a[1], policy$text)
  } else if (command == "BATCH") {
    index <- stage_index(a[1])
    lot <- as.numeric(a[2])
    if (lot < 1 || lot > 100) fail(paste("invalid batch size", a[2]))
    simulation$stages[[index]]$lot <- lot
    emit("BATCH", a[1], lot)
  } else if (command == "CAPACITY") {
    index <- if (a[1] == "PLANT") NA_integer_ else stage_index(a[1])
    capacity <- if (a[2] == "OFF") NULL else as.numeric(a[2])
    if (!is.null(capacity) && capacity > 10000)
      fail(paste("invalid capacity", a[2]))
    if (is.na(index)) simulation$plant_capacity <- capacity
    else simulation$stages[[index]]$capacity <- capacity
    emit("CAPACITY", a[1], a[2])
  } else if (command == "COST") {
    index <- stage_index(a[1])
    holding <- as.numeric(a[2])
    backlog <- as.numeric(a[3])
    if (holding > 1000 || backlog > 1000) fail("invalid cost")
    stage <- simulation$stages[[index]]
    stage$holding <- holding
    stage$backlog_rate <- backlog
    emit("COST", a[1], "holding", holding, "backlog", backlog)
  } else if (command == "VISIBILITY") {
    if (!(a[1] %in% c("ON", "OFF"))) fail(paste("unknown visibility", a[1]))
    simulation$visibility <- a[1]
    emit("VISIBILITY", a[1])
  } else if (command == "SHOCK") {
    week <- as.numeric(a[1])
    value <- as.numeric(a[2])
    if (week < 1 || week > length(simulation$demands))
      fail(paste("week", a[1], "outside horizon"))
    if (week <= simulation$week) fail(paste("week", a[1], "already simulated"))
    old <- simulation$demands[week]
    simulation$demands[week] <- value
    emit("SHOCK", "week", week, old, "->", value)
  } else if (command == "STATUS") {
    show_status()
  } else if (command == "SETTINGS") {
    emit("SETTINGS")
    for (index in 1:4) {
      stage <- simulation$stages[[index]]
      initial <- game$initials[[index]]
      emit(stage_names[index], "holding", stage$holding,
           "backlog", stage$backlog_rate, "batch", stage$lot,
           "capacity", if (is.null(stage$capacity)) "OFF" else stage$capacity,
           "delays", initial$shipping, initial$orders)
    }
    emit("PLANT", "capacity",
         if (is.null(simulation$plant_capacity)) "OFF" else simulation$plant_capacity)
    emit("VISIBILITY", simulation$visibility)
  } else if (command == "WEEK") {
    require_weeks()
    week <- as.numeric(a[1])
    if (week < 1 || week > simulation$week) fail(paste("bad week", a[1]))
    show_week(week)
  } else if (command == "TABLE") {
    index <- stage_index(a[1])
    require_weeks()
    bounds <- range_check(a[-1], simulation$week)
    show_table(index, bounds[1], bounds[2])
  } else if (command == "CHAIN") {
    require_weeks()
    bounds <- range_check(a, simulation$week)
    first <- bounds[1]
    last <- bounds[2]
    emit("CHAIN", paste0(first, "-", last))
    header <- c(right("week", 4), right("demand", 6),
                vapply(stage_names, right, character(1), width = 11))
    emit(paste(header, collapse = " "))
    for (week in seq.int(first, last)) {
      orders <- vapply(simulation$stages, function(stage)
        stage$records[[week]]$order, numeric(1))
      entries <- c(right(week, 4), right(simulation$demands[week], 6),
                   vapply(orders, right, character(1), width = 11))
      emit(paste(entries, collapse = " "))
    }
  } else if (command == "DEMANDS") {
    bounds <- range_check(a, length(simulation$demands))
    values <- simulation$demands[seq.int(bounds[1], bounds[2])]
    emit("DEMANDS", paste0(bounds[1], "-", bounds[2]),
         "total", sum(values), "min", min(values), "max", max(values))
    emit(paste(values, collapse = " "))
  } else if (command == "COSTS") {
    show_costs()
  } else if (command == "SUMMARY") {
    require_weeks()
    emit("SUMMARY", "weeks", paste0("1-", simulation$week))
    for (index in 1:4) {
      records <- simulation$stages[[index]]$records
      orders <- record_values(records, "order")
      emit(stage_names[index],
           "avg_inv", decimal(record_sum(records, "inventory"), simulation$week, 2),
           "avg_back", decimal(record_sum(records, "backlog"), simulation$week, 2),
           "orders", sum(orders), "min", min(orders), "max", max(orders),
           "zero_weeks", sum(orders == 0))
    }
  } else if (command == "BALANCE") {
    emit("BALANCE", "week", simulation$week)
    for (index in 1:4) {
      stage <- simulation$stages[[index]]
      records <- stage$records
      emit(stage_names[index], "start", game$initials[[index]]$inventory,
           "received", record_sum(records, "received"),
           "shipped", record_sum(records, "shipped"),
           "end", stage$inventory, "owed", stage$backlog)
    }
    initial_goods <- sum(vapply(game$initials, function(initial)
      initial$inventory + initial$quantity * initial$shipping, numeric(1)))
    emit("SYSTEM", "initial", initial_goods,
         "produced", record_sum(simulation$plant_records, "produced"),
         "delivered", record_sum(simulation$stages[[1]]$records, "shipped"),
         "stock", sum(vapply(simulation$stages, function(stage) stage$inventory, numeric(1))),
         "transit", sum(vapply(simulation$stages, function(stage) sum(stage$shipping), numeric(1))))
  } else if (command == "FILLRATE") {
    require_weeks()
    emit("FILLRATE", "weeks", paste0("1-", simulation$week))
    for (index in 1:4) {
      records <- simulation$stages[[index]]$records
      result <- fill_text(records)
      stockouts <- sum(record_values(records, "backlog") > 0)
      emit(stage_names[index], "fill", result$fill, "ontime", result$ontime,
           "ordered", result$ordered, "stockout_weeks", stockouts,
           "service", paste0(decimal((simulation$week - stockouts) * 100,
                                    simulation$week, 2), "%"))
    }
  } else if (command == "BULLWHIP") {
    require_weeks()
    show_bullwhip()
  } else if (command == "PEAKS") {
    require_weeks()
    show_peaks()
  } else if (command == "LEADTIME") {
    index <- stage_index(a[1])
    require_weeks()
    show_leadtime(index)
  } else if (command %in% c("PLOT", "HISTOGRAM")) {
    index <- stage_index(a[1])
    mode_check(a[2])
    if (command == "HISTOGRAM") {
      width <- as.numeric(a[3])
      if (width < 1 || width > 100) fail(paste("invalid width", a[3]))
    }
    require_weeks()
    if (command == "PLOT") {
      bounds <- range_check(a[-(1:2)], simulation$week)
      show_plot(index, a[2], bounds[1], bounds[2])
    } else {
      show_histogram(index, a[2], width)
    }
  } else if (command == "COMPARE") {
    policies <- list()
    start <- 1
    for (end in seq_len(length(a) + 1)) {
      if (end == length(a) + 1 || a[end] == "/") {
        policies[[length(policies) + 1]] <- parse_policy(a[seq.int(start, end - 1)])
        start <- end + 1
      }
    }
    rows <- list()
    for (i in seq_along(policies)) {
      policy <- policies[[i]]
      simulation_trial <- trial(rep(list(policy), 4))
      cost <- sum(sum_costs(simulation_trial))
      fill <- fill_text(simulation_trial$stages[[1]]$records)$fill
      demand_var <- variation(simulation_trial$demands)
      factory_var <- variation(record_values(simulation_trial$stages[[4]]$records, "order"))
      ratio <- if (demand_var == 0) "n/a" else decimal(factory_var, demand_var, 4)
      rows[[i]] <- list(cost = cost, index = i, policy = policy$text,
                        fill = fill, ratio = ratio)
    }
    emit("COMPARE", length(policies), "weeks", length(simulation$demands))
    ordering <- order(vapply(rows, function(row) row$cost, numeric(1)),
                      vapply(rows, function(row) row$index, numeric(1)))
    for (rank in seq_along(ordering)) {
      row <- rows[[ordering[rank]]]
      emit(rank, row$policy, "total", money(row$cost),
           "fill", row$fill, "bullwhip", row$ratio)
    }
  } else if (command == "OPTIMIZE") {
    indices <- target(a[1])
    low <- as.numeric(a[2])
    high <- as.numeric(a[3])
    if (low > high) fail(paste("bad range", a[2], a[3]))
    if (high - low > 200) fail("range too large")
    best <- NULL
    for (value in seq.int(low, high)) {
      policies <- lapply(simulation$stages, function(stage) stage$policy)
      policy <- list(name = "BASESTOCK", args = value,
                     text = paste("BASESTOCK", value))
      for (index in indices) policies[[index]] <- policy
      simulation_trial <- trial(policies)
      costs <- sum_costs(simulation_trial)
      objective <- sum(costs[indices])
      row <- c(objective, value, sum(costs))
      if (is.null(best) || row[1] < best[1] ||
          (row[1] == best[1] && row[2] < best[2])) best <- row
    }
    emit("OPTIMIZE", a[1], "BASESTOCK", best[2],
         "cost", money(best[1]), "total", money(best[3]))
  } else {
    fail(paste("unknown command", command))
  }
}

settings <- lapply(1:4, function(index)
  strsplit(readLines(file("stdin"), n = 1), " ", fixed = TRUE)[[1]])
game$initials <- lapply(settings, function(tokens)
  list(inventory = as.numeric(tokens[2]),
       quantity = as.numeric(tokens[3]),
       shipping = as.numeric(tokens[4]),
       orders = as.numeric(tokens[5]),
       holding = as.numeric(tokens[6]),
       backlog = as.numeric(tokens[7]),
       policy = parse_policy(tokens[-(1:7)])))
initialize()
input <- file("stdin", "r")
repeat {
  line <- readLines(input, n = 1)
  if (!length(line) || line == "END") break
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  tryCatch(run_command(words[1], words[-1]),
           GameError = function(error) emit("ERROR", conditionMessage(error)))
}
close(input)
if (length(game$output)) cat(paste(game$output, collapse = "\n"), "\n", sep = "")
