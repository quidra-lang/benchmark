integer_divide <- function(a, b) {
  quotient <- floor(a / b)
  while (quotient * b > a) quotient <- quotient - 1
  while ((quotient + 1) * b <= a) quotient <- quotient + 1
  quotient
}

integer_text <- function(value) sprintf("%.0f", value)

text_line <- function(...) {
  paste(vapply(list(...), function(value) if (is.numeric(value)) integer_text(value) else value, character(1L)), collapse = " ")
}

read_rows <- function(name) {
  lines <- readLines(file.path("input", name), warn = FALSE)
  lapply(seq_len(length(lines) - 1L), function(index) list(line = index + 1L, fields = strsplit(lines[index + 1L], ",", fixed = TRUE)[[1L]]))
}

record_error <- function(errors, file, line, reason) {
  errors$lines <- c(errors$lines, paste0(file, " line ", line, ": ", reason))
}

script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("items", "bom", "lot_sizing", "capacity", "costing", "report")) source(file.path(source_dir, paste0(unit, ".R")))

DEMAND_KINDS <- c("MPS", "ORDER", "DEPENDENT")
ROOT_KINDS <- c("MPS", "ORDER", "SAFETY")
SUPPLY_KINDS <- c("STOCK", "RECEIPT", "ORDER")
MESSAGE_KINDS <- c("BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD")

read_params <- function() {
  result <- list()
  for (line in readLines("input/params.txt", warn = FALSE)) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    if (words[1L] == "horizon") result$horizon <- as.integer(words[2L])
    else if (words[1L] == "peg") result$peg_items <- words[-1L]
    else result$tree_quantity <- as.numeric(words[2L])
  }
  result
}

schedule_error <- function(id, week, quantity, items, horizon) {
  if (!id %in% names(items)) return(paste("unknown item", id))
  if (week < 1L || week > horizon) return(paste("week", week, "outside horizon"))
  if (quantity < 1) return(paste("bad quantity", integer_text(quantity)))
  NULL
}

read_schedule <- function(file, items, horizon, errors, unique_weeks) {
  valid <- list()
  seen <- character()
  for (row in read_rows(file)) {
    fields <- row$fields
    id <- fields[1L]
    week <- as.integer(fields[2L])
    quantity <- as.numeric(fields[3L])
    key <- paste(id, week, sep = "/")
    reason <- schedule_error(id, week, quantity, items, horizon)
    if (is.null(reason) && unique_weeks && key %in% seen) reason <- paste("duplicate", id, "week", week)
    if (!is.null(reason)) record_error(errors, file, row$line, reason)
    else {
      valid[[length(valid) + 1L]] <- list(item = id, week = week, quantity = quantity, line = row$line)
      seen <- c(seen, key)
    }
  }
  valid
}

read_inquiries <- function(items, horizon, errors) {
  valid <- list()
  seen <- character()
  for (row in read_rows("orders.csv")) {
    fields <- row$fields
    id <- fields[1L]
    item <- fields[2L]
    quantity <- as.numeric(fields[3L])
    week <- as.integer(fields[4L])
    reason <- if (id %in% seen) paste("duplicate order", id) else schedule_error(item, week, quantity, items, horizon)
    if (!is.null(reason)) record_error(errors, "orders.csv", row$line, reason)
    else {
      valid[[length(valid) + 1L]] <- list(id = id, item = item, quantity = quantity, week = week, line = row$line)
      seen <- c(seen, id)
    }
  }
  valid
}

new_demand <- function(item, kind, week, quantity, order_id = "", line = 0L, parent = "", parent_number = 0L) {
  list(item = item, kind = kind, week = week, quantity = quantity, order_id = order_id, line = line, parent = parent, parent_number = parent_number)
}

read_data <- function() {
  data <- read_params()
  errors <- new.env(parent = emptyenv())
  errors$lines <- character()
  data$items <- read_items(errors)
  data$bom <- read_bom(data$items, errors)
  data$centers <- read_workcenters(errors)
  data$routings <- read_routings(data$items, data$centers, data$bom, errors)
  mps <- read_schedule("mps.csv", data$items, data$horizon, errors, TRUE)
  receipts <- read_schedule("receipts.csv", data$items, data$horizon, errors, FALSE)
  data$inquiries <- read_inquiries(data$items, data$horizon, errors)
  data$errors <- errors$lines
  data$mps_demands <- lapply(mps, function(row) new_demand(row$item, "MPS", row$week, row$quantity))
  data$codes <- low_level_codes(data$bom, data$items)
  data$cumulative <- cumulative_lead_times(data$bom, data$items)
  ids <- sort(names(data$items), method = "radix")
  data$planning_order <- ids[order(data$codes[ids], seq_along(ids), method = "radix")]
  data$center_order <- sort(names(data$centers), method = "radix")
  data$weeks <- seq_len(data$horizon)
  data$receipts <- setNames(rep(list(list()), length(ids)), ids)
  data$scheduled <- setNames(rep(list(numeric(data$horizon)), length(ids)), ids)
  if (length(receipts)) receipts <- receipts[order(vapply(receipts, function(row) row$week, integer(1L)), vapply(receipts, function(row) row$line, integer(1L)))]
  for (row in receipts) {
    data$receipts[[row$item]] <- c(data$receipts[[row$item]], list(row))
    data$scheduled[[row$item]][row$week] <- data$scheduled[[row$item]][row$week] + row$quantity
  }
  data
}

run_mrp <- function(data, order_demands) {
  plans <- lapply(data$items, function(item) list(item = item, receipts = data$scheduled[[item$id]], demands = list(), gross = numeric(data$horizon),
                                               on_hand = numeric(data$horizon), net = numeric(data$horizon), planned_receipts = numeric(data$horizon),
                                               planned_releases = numeric(data$horizon), orders = list()))
  for (demand in c(data$mps_demands, order_demands)) plans[[demand$item]]$demands <- c(plans[[demand$item]]$demands, list(demand))
  for (id in data$planning_order) {
    plan <- plans[[id]]
    item <- plan$item
    for (demand in plan$demands) plan$gross[demand$week] <- plan$gross[demand$week] + demand$quantity
    projected <- item$on_hand
    for (week in data$weeks) {
      available <- projected + plan$receipts[week] - plan$gross[week]
      projected <- available
      if (available < item$safety_stock) {
        quantity <- lot_size(item, week, available, plan$receipts, plan$gross, data$horizon)
        release <- week - item$lead_time
        order <- list(item = id, number = length(plan$orders) + 1L, receipt = week, quantity = quantity, original_release = release, release = max(1L, release))
        plan$orders[[length(plan$orders) + 1L]] <- order
        plan$net[week] <- item$safety_stock - available
        plan$planned_receipts[week] <- quantity
        plan$planned_releases[order$release] <- plan$planned_releases[order$release] + quantity
        projected <- available + quantity
      }
      plan$on_hand[week] <- projected
    }
    plans[[id]] <- plan
    for (order in plan$orders) for (row in data$bom$children[[id]]) {
      demand <- new_demand(row$child, "DEPENDENT", order$release, need(row, order$quantity), parent = id, parent_number = order$number)
      plans[[row$child]]$demands <- c(plans[[row$child]]$demands, list(demand))
    }
  }
  loads <- setNames(rep(list(numeric(data$horizon)), length(data$centers)), names(data$centers))
  for (id in data$planning_order) {
    operations <- data$routings[[id]]
    for (order in plans[[id]]$orders) for (index in seq_along(operations)) {
      operation <- operations[[index]]
      week <- operation_week(order$receipt, data$items[[id]]$lead_time, index - 1L, length(operations))
      loads[[operation$center]][week] <- loads[[operation$center]][week] + operation_minutes(operation, order$quantity)
    }
  }
  overloads <- lapply(names(loads), function(center) pmax(0, loads[[center]] - data$centers[[center]]$available))
  names(overloads) <- names(loads)
  list(items = plans, loads = loads, overloads = overloads)
}

past_due_quantity <- function(plan) sum(vapply(plan$orders, function(order) if (order$original_release < 1L) order$quantity else 0, numeric(1L)))

material_reason <- function(data, current, trial) {
  for (id in data$planning_order) if (past_due_quantity(trial$items[[id]]) > past_due_quantity(current$items[[id]])) return(id)
  NULL
}

capacity_reason <- function(data, current, trial) {
  for (id in data$center_order) for (week in data$weeks) if (trial$overloads[[id]][week] > current$overloads[[id]][week]) return(paste(id, "week", week))
  NULL
}

promise_inquiries <- function(data, base) {
  current <- base
  promised <- promises <- list()
  for (inquiry in data$inquiries) {
    promise <- list(inquiry = inquiry, week = 0L, material_week = 0L, reason = "")
    for (week in seq.int(inquiry$week, data$horizon)) {
      demand <- new_demand(inquiry$item, "ORDER", week, inquiry$quantity, inquiry$id, inquiry$line)
      trial <- run_mrp(data, c(promised, list(demand)))
      reason <- material_reason(data, current, trial)
      if (is.null(reason)) {
        if (!promise$material_week) promise$material_week <- week
        reason <- capacity_reason(data, current, trial)
      }
      if (is.null(reason)) {
        promise$week <- week
        promised <- c(promised, list(demand))
        current <- trial
        break
      }
      if (week == inquiry$week) promise$reason <- reason
    }
    promises[[length(promises) + 1L]] <- promise
  }
  list(promises = promises, final = current)
}

parent_supply <- function(plans, demand) {
  parent <- plans[[demand$parent]]
  parent$supplies[[parent$order_supply_indices[demand$parent_number]]]
}

sorted_roots <- function(roots) {
  if (!length(roots)) return(roots)
  keys <- vapply(roots, function(root) paste(root$item, root$kind, root$week, root$order_id, sep = "\t"), character(1L))
  roots <- roots[!duplicated(keys)]
  roots[order(vapply(roots, function(root) root$item, character(1L)),
              vapply(roots, function(root) match(root$kind, ROOT_KINDS), integer(1L)),
              vapply(roots, function(root) root$week, integer(1L)),
              vapply(roots, function(root) root$order_id, character(1L)), method = "radix")]
}

peg_plan <- function(data, plan) {
  for (id in data$planning_order) {
    item_plan <- plan$items[[id]]
    item <- item_plan$item
    demands <- item_plan$demands
    if (length(demands)) demands <- demands[order(vapply(demands, function(demand) demand$week, integer(1L)),
                                                  vapply(demands, function(demand) match(demand$kind, DEMAND_KINDS), integer(1L)),
                                                  vapply(demands, function(demand) demand$line, integer(1L)),
                                                  vapply(demands, function(demand) demand$parent, character(1L)),
                                                  vapply(demands, function(demand) demand$parent_number, integer(1L)), method = "radix")]
    if (item$safety_stock > 0) demands <- c(list(new_demand(id, "SAFETY", 0L, item$safety_stock)), demands)
    supplies <- list()
    add_supply <- function(kind, week, quantity, line = 0L, order = NULL) {
      supplies[[length(supplies) + 1L]] <<- list(kind = kind, week = week, quantity = quantity, line = line, order = order,
                                               remaining = quantity, allocations = list(), roots = list())
    }
    if (item$on_hand > 0) add_supply("STOCK", 0L, item$on_hand)
    for (receipt in data$receipts[[id]]) add_supply("RECEIPT", receipt$week, receipt$quantity, receipt$line)
    for (order in item_plan$orders) add_supply("ORDER", order$receipt, order$quantity, order = order)
    if (length(supplies)) supplies <- supplies[order(vapply(supplies, function(supply) supply$week, integer(1L)),
                                                     vapply(supplies, function(supply) match(supply$kind, SUPPLY_KINDS), integer(1L)),
                                                     vapply(supplies, function(supply) supply$line, integer(1L)))]
    index <- 1L
    for (demand in demands) {
      remaining <- demand$quantity
      while (remaining > 0) {
        while (supplies[[index]]$remaining == 0) index <- index + 1L
        share <- min(remaining, supplies[[index]]$remaining)
        supplies[[index]]$allocations <- c(supplies[[index]]$allocations, list(list(demand = demand, share = share)))
        supplies[[index]]$remaining <- supplies[[index]]$remaining - share
        remaining <- remaining - share
      }
    }
    order_indices <- which(vapply(supplies, function(supply) supply$kind == "ORDER", logical(1L)))
    for (supply_index in order_indices) {
      roots <- list()
      for (allocation in supplies[[supply_index]]$allocations) {
        demand <- allocation$demand
        roots <- c(roots, if (demand$kind == "DEPENDENT") parent_supply(plan$items, demand)$roots else list(demand))
      }
      supplies[[supply_index]]$roots <- sorted_roots(roots)
    }
    item_plan$supplies <- supplies
    item_plan$order_supply_indices <- order_indices
    plan$items[[id]] <- item_plan
  }
  plan
}

demand_text <- function(demand) {
  if (demand$kind == "SAFETY") return(text_line("SAFETY", demand$item))
  if (demand$kind == "MPS") return(text_line("MPS", demand$item, "week", demand$week))
  if (demand$kind == "ORDER") return(text_line("ORDER", demand$order_id, demand$item, "week", demand$week))
  text_line(demand$parent, "order", demand$parent_number, "week", demand$week)
}

supply_header <- function(supply) {
  if (supply$kind == "STOCK") return(text_line("STOCK quantity", supply$quantity))
  if (supply$kind == "RECEIPT") return(text_line("RECEIPT line", supply$line, "week", supply$week, "quantity", supply$quantity))
  order <- supply$order
  text_line("ORDER", order$number, "receipt", order$receipt, "release", order$release, "quantity", order$quantity)
}

grid_lines <- function(data, plan) {
  lines <- character()
  for (id in data$planning_order) {
    item_plan <- plan$items[[id]]
    item <- item_plan$item
    lines <- c(lines, text_line("ITEM", id, "LLC", data$codes[[id]], "LT", item$lead_time, "LOT", lot_label(item), "SS", item$safety_stock, "OH", item$on_hand, item$description),
                table_row("WEEK", data$weeks, 6L), table_row("GROSS", item_plan$gross, 6L), table_row("RECEIPTS", item_plan$receipts, 6L),
                table_row("ON_HAND", item_plan$on_hand, 6L), table_row("NET", item_plan$net, 6L), table_row("PLAN_RCPT", item_plan$planned_receipts, 6L), table_row("PLAN_REL", item_plan$planned_releases, 6L),
                text_line("TOTAL gross", sum(item_plan$gross), "receipts", sum(item_plan$receipts), "planned", sum(item_plan$planned_receipts), "orders", length(item_plan$orders), "ending", item_plan$on_hand[data$horizon]))
  }
  lines
}

depth_label <- function(depth) paste0(strrep(".", depth), depth)

where_used_lines <- function(data, id, depth = 1L, extension = 1) {
  lines <- character()
  for (row in data$bom$parents[[id]]) {
    cumulative <- extension * row$qty_per
    lines <- c(lines, text_line(depth_label(depth), row$parent, "qty", row$qty_per, "ext", cumulative), where_used_lines(data, row$parent, depth + 1L, cumulative))
  }
  lines
}

allocation_lines <- function(plans, supply, depth = 1L) {
  lines <- character()
  for (allocation in supply$allocations) {
    demand <- allocation$demand
    lines <- c(lines, paste0(strrep(" ", 2L * depth), text_line("ALLOC", allocation$share, demand_text(demand))))
    if (supply$kind == "ORDER" && demand$kind == "DEPENDENT") lines <- c(lines, allocation_lines(plans, parent_supply(plans, demand), depth + 1L))
  }
  lines
}

pegging_lines <- function(data, plan) {
  lines <- character()
  for (id in data$peg_items) {
    item_plan <- plan$items[[id]]
    lines <- c(lines, text_line("PEG", id, "orders", length(item_plan$orders)), where_used_lines(data, id))
    for (kind in SUPPLY_KINDS) for (supply in item_plan$supplies) {
      if (supply$kind != kind) next
      lines <- c(lines, supply_header(supply), allocation_lines(plan$items, supply))
      if (supply$remaining > 0) lines <- c(lines, paste0("  ", text_line("EXCESS", supply$remaining)))
      for (root in supply$roots) lines <- c(lines, paste0("  ROOT ", demand_text(root)))
    }
  }
  lines
}

bom_tree_lines <- function(data) {
  lines <- character()
  for (id in sort(names(data$items), method = "radix")) {
    if (!length(data$bom$children[[id]]) || length(data$bom$parents[[id]])) next
    item <- data$items[[id]]
    lines <- c(lines, text_line("TREE", id, "quantity", data$tree_quantity), text_line("0", id, "ext 1 gross", data$tree_quantity, "lt", item$lead_time, "cum", data$cumulative[[id]], item$description))
    totals <- numeric()
    explode <- function(parent, gross, extension, depth) {
      for (row in data$bom$children[[parent]]) {
        child <- data$items[[row$child]]
        child_extension <- extension * row$qty_per
        child_gross <- need(row, gross)
        if (!row$child %in% names(totals)) totals[row$child] <<- 0
        totals[row$child] <<- totals[row$child] + child_gross
        lines <<- c(lines, text_line(depth_label(depth), row$child, "qty", row$qty_per, "scrap", row$scrap, "ext", child_extension, "gross", child_gross,
                                     "lt", child$lead_time, "cum", data$cumulative[[row$child]], child$description))
        explode(row$child, child_gross, child_extension, depth + 1L)
      }
    }
    explode(id, data$tree_quantity, 1, 1L)
    for (child in sort(names(totals), method = "radix")) lines <- c(lines, text_line("SUM", child, totals[[child]]))
    path <- id
    current <- id
    while (length(data$bom$children[[current]])) {
      children <- data$bom$children[[current]]
      index <- which.max(vapply(children, function(row) data$cumulative[[row$child]], integer(1L)))
      current <- children[[index]]$child
      path <- c(path, current)
    }
    lines <- c(lines, text_line("CRITICAL", paste(path, collapse = " -> "), "cum", data$cumulative[[id]]))
  }
  lines
}

cost_lines <- function(data, plan, costs) {
  usages <- vapply(plan$items, function(item_plan) sum(item_plan$gross), numeric(1L))
  values <- vapply(names(usages), function(id) usages[[id]] * costs[[id]]$total, numeric(1L))
  names(values) <- names(usages)
  classes <- abc_classes(values)
  lines <- "item,material,labor,total,usage,value,class"
  for (id in sort(names(data$items), method = "radix")) {
    cost <- costs[[id]]
    lines <- c(lines, paste(id, money(cost$material), money(cost$labor), money(cost$total), integer_text(usages[[id]]), money(values[[id]]), classes[[id]], sep = ","))
  }
  lines
}

exception_lines <- function(data, plan) {
  messages <- character()
  for (id in data$planning_order) {
    item_plan <- plan$items[[id]]
    item <- item_plan$item
    if (item$on_hand < item$safety_stock) messages <- c(messages, text_line("BELOW_SAFETY", id, "on hand", item$on_hand, "safety", item$safety_stock))
    for (order in item_plan$orders) {
      if (order$original_release < 1L) messages <- c(messages, text_line("PAST_DUE", id, "order", order$number, "receipt", order$receipt, "release", order$original_release, "late", 1L - order$original_release, "quantity", order$quantity))
      else if (order$original_release == 1L) messages <- c(messages, text_line("RELEASE", id, "order", order$number, "receipt", order$receipt, "quantity", order$quantity))
    }
    balances <- item$on_hand - cumsum(item_plan$gross)
    covered <- 0
    for (receipt in data$receipts[[id]]) {
      weeks <- which(balances + covered < item$safety_stock)
      need_week <- if (length(weeks)) weeks[1L] else 0L
      detail <- text_line(id, "receipt line", receipt$line, "week", receipt$week, "quantity", receipt$quantity)
      if (!need_week) messages <- c(messages, text_line("CANCEL", detail))
      else if (need_week < receipt$week) messages <- c(messages, text_line("EXPEDITE", detail, "to", need_week))
      else if (need_week > receipt$week) messages <- c(messages, text_line("DEFER", detail, "to", need_week))
      covered <- covered + receipt$quantity
    }
    if (length(data$bom$children[[id]]) && !length(data$routings[[id]])) messages <- c(messages, text_line("NO_ROUTING", id))
    if (sum(item_plan$gross) == 0 && item$on_hand > 0) messages <- c(messages, text_line("NO_DEMAND", id, "on hand", item$on_hand))
  }
  for (center in data$center_order) for (week in data$weeks) if (plan$overloads[[center]][week] > 0) {
    messages <- c(messages, text_line("OVERLOAD", center, "week", week, "load", plan$loads[[center]][week], "available", data$centers[[center]]$available))
  }
  summary <- text_line("SUMMARY errors", length(data$errors))
  for (kind in MESSAGE_KINDS) summary <- text_line(summary, tolower(kind), sum(startsWith(messages, paste0(kind, " "))))
  c(if (length(data$errors)) paste0("ERROR ", data$errors) else character(), messages, summary)
}

capacity_lines <- function(data, plan) {
  lines <- character()
  totals <- numeric()
  for (id in data$center_order) {
    center <- data$centers[[id]]
    loads <- plan$loads[[id]]
    overloads <- plan$overloads[[id]]
    leveled <- level_loads(loads, center$available)
    total <- sum(loads)
    totals[id] <- total
    available <- center$available * data$horizon
    peak <- if (total > 0) which.max(loads) else 0L
    lines <- c(lines, text_line("CENTER", id, "minutes", center$minutes, "efficiency", center$efficiency, "available", center$available, center$description),
                table_row("WEEK", data$weeks, 7L), table_row("LOAD", loads, 7L), table_row("UTIL", percent(loads, center$available), 7L),
                table_row("OVER", overloads, 7L), table_row("LEVELED", leveled, 7L),
                text_line("TOTAL load", total, "available", available, "utilization", percent(total, available), "overloaded", sum(overloads > 0),
                          "peak", peak, "backlog", max(0, leveled[1L] - center$available)))
  }
  ranked <- character()
  for (id in data$center_order) {
    before <- length(ranked)
    for (index in seq_along(ranked)) {
      other <- ranked[index]
      if (totals[[id]] * data$centers[[other]]$available > totals[[other]] * data$centers[[id]]$available) {
        before <- index - 1L
        break
      }
    }
    ranked <- append(ranked, id, after = before)
  }
  for (rank in seq_along(ranked)) {
    id <- ranked[rank]
    lines <- c(lines, text_line("RANK", rank, id, "load", totals[[id]], "utilization", percent(totals[[id]], data$centers[[id]]$available * data$horizon)))
  }
  lines
}

promise_lines <- function(data, promises, base, final) {
  lines <- character()
  counts <- c(on_time = 0L, late = 0L, rejected = 0L)
  for (promise in promises) {
    inquiry <- promise$inquiry
    status <- if (!promise$week) "rejected" else if (promise$week == inquiry$week) "on_time" else "late"
    counts[status] <- counts[status] + 1L
    head <- text_line("ORDER", inquiry$id, inquiry$item, "quantity", inquiry$quantity, "requested", inquiry$week)
    material <- if (promise$material_week) integer_text(promise$material_week) else "none"
    if (status == "rejected") {
      lines <- c(lines, text_line(head, "rejected material", material, "reason", promise$reason))
      next
    }
    if (status == "on_time") lines <- c(lines, text_line(head, "promised", promise$week))
    else lines <- c(lines, text_line(head, "promised", promise$week, "late", promise$week - inquiry$week, "material", material, "reason", promise$reason))
    for (id in data$planning_order) {
      item_plan <- final$items[[id]]
      for (index in item_plan$order_supply_indices) {
        supply <- item_plan$supplies[[index]]
        if (!any(vapply(supply$roots, function(root) root$kind == "ORDER" && root$order_id == inquiry$id, logical(1L)))) next
        order <- supply$order
        lines <- c(lines, paste0("  ", text_line("SUPPLY", id, "order", order$number, "receipt", order$receipt, "release", order$release, "quantity", order$quantity)))
      }
    }
  }
  for (id in data$planning_order) {
    before <- base$items[[id]]
    after <- final$items[[id]]
    changed <- which(before$planned_receipts != after$planned_receipts)
    if (length(changed)) lines <- c(lines, text_line("CHANGE", id, "from", changed[1L], "planned", sum(before$planned_receipts), "->", sum(after$planned_receipts), "orders", length(before$orders), "->", length(after$orders)))
  }
  c(lines, text_line("SUMMARY orders", length(promises), "on_time", counts[["on_time"]], "late", counts[["late"]], "rejected", counts[["rejected"]]))
}

release_lines <- function(data, plan) {
  orders <- list()
  for (id in data$planning_order) orders <- c(orders, Filter(function(order) order$release == 1L, plan$items[[id]]$orders))
  if (length(orders)) orders <- orders[order(vapply(orders, function(order) order$original_release, integer(1L)),
                                             vapply(orders, function(order) order$item, character(1L)),
                                             vapply(orders, function(order) order$number, integer(1L)), method = "radix")]
  available <- vapply(names(data$items), function(id) data$items[[id]]$on_hand + data$scheduled[[id]][1L], numeric(1L))
  names(available) <- names(data$items)
  lines <- character()
  made <- ready_count <- bought <- 0L
  purchase_total <- 0
  for (order in orders) {
    id <- order$item
    head <- text_line(id, "order", order$number, "receipt", order$receipt, "quantity", order$quantity)
    if (order$original_release < 1L) head <- text_line(head, "late", 1L - order$original_release)
    rows <- data$bom$children[[id]]
    if (!length(rows)) {
      value <- order$quantity * data$items[[id]]$material
      bought <- bought + 1L
      purchase_total <- purchase_total + value
      lines <- c(lines, text_line("BUY", head, "value", money(value)))
      next
    }
    requirements <- vapply(rows, need, numeric(1L), quantity = order$quantity)
    have <- vapply(rows, function(row) available[[row$child]], numeric(1L))
    ready <- all(requirements <= have)
    made <- made + 1L
    if (ready) ready_count <- ready_count + 1L
    lines <- c(lines, text_line("MAKE", head, if (ready) "READY" else "SHORT"))
    for (index in seq_along(rows)) lines <- c(lines, paste0("  ", text_line("PICK", rows[[index]]$child, "need", requirements[index], "available", have[index], "short", max(0, requirements[index] - have[index]))))
    if (ready) for (index in seq_along(rows)) available[[rows[[index]]$child]] <- available[[rows[[index]]$child]] - requirements[index]
    operations <- data$routings[[id]]
    for (index in seq_along(operations)) {
      operation <- operations[[index]]
      week <- operation_week(order$receipt, data$items[[id]]$lead_time, index - 1L, length(operations))
      lines <- c(lines, paste0("  ", text_line("OPERATION", operation$number, operation$center, "week", week, "minutes", operation_minutes(operation, order$quantity))))
    }
  }
  c(lines, text_line("SUMMARY make", made, "ready", ready_count, "short", made - ready_count, "buy", bought, "value", money(purchase_total)))
}

value_plan_lines <- function(data, plan, costs) {
  lines <- "week,inventory,purchases,labor"
  for (week in data$weeks) {
    inventory <- purchases <- labor <- 0
    for (id in data$planning_order) {
      item_plan <- plan$items[[id]]
      released <- item_plan$planned_releases[week]
      inventory <- inventory + item_plan$on_hand[week] * costs[[id]]$total
      if (length(data$bom$children[[id]])) labor <- labor + released * item_plan$item$labor
      else purchases <- purchases + released * item_plan$item$material
    }
    lines <- c(lines, paste(week, money(inventory), money(purchases), money(labor), sep = ","))
  }
  lines
}

main <- function() {
  data <- read_data()
  base <- run_mrp(data, list())
  result <- promise_inquiries(data, base)
  final <- peg_plan(data, result$final)
  costs <- standard_costs(data)
  write_report("mrp_grid.txt", grid_lines(data, final))
  write_report("pegging.txt", pegging_lines(data, final))
  write_report("bom_tree.txt", bom_tree_lines(data))
  write_report("cost_rollup.csv", cost_lines(data, final, costs))
  write_report("exceptions.txt", exception_lines(data, final))
  write_report("capacity.txt", capacity_lines(data, final))
  write_report("promises.txt", promise_lines(data, result$promises, base, final))
  write_report("releases.txt", release_lines(data, final))
  write_report("value_plan.csv", value_plan_lines(data, final, costs))
}

main()
