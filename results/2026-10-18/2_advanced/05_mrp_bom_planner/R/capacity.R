read_workcenters <- function(errors) {
  centers <- list()
  for (row in read_rows("workcenters.csv")) {
    fields <- row$fields
    id <- fields[1L]
    efficiency <- as.numeric(fields[3L])
    reason <- if (id %in% names(centers)) paste("duplicate center", id) else if (efficiency < 50 || efficiency > 150) paste("bad efficiency", integer_text(efficiency)) else NULL
    if (!is.null(reason)) {
      record_error(errors, "workcenters.csv", row$line, reason)
      next
    }
    minutes <- as.numeric(fields[2L])
    centers[[id]] <- list(id = id, minutes = minutes, efficiency = efficiency,
                          available = integer_divide(minutes * efficiency, 100), description = fields[4L])
  }
  centers
}

read_routings <- function(items, centers, bom, errors) {
  routings <- setNames(rep(list(list()), length(items)), names(items))
  for (row in read_rows("routings.csv")) {
    fields <- row$fields
    id <- fields[1L]
    number <- as.integer(fields[2L])
    center <- fields[3L]
    run <- as.numeric(fields[5L])
    reason <- if (!id %in% names(items)) paste("unknown item", id) else if (!center %in% names(centers)) paste("unknown center", center) else if (!length(bom$children[[id]])) {
      paste("purchased item", id)
    } else if (run < 1) paste("bad run time", integer_text(run)) else if (any(vapply(routings[[id]], function(operation) operation$number == number, logical(1L)))) paste("duplicate", id, "operation", number) else NULL
    if (!is.null(reason)) {
      record_error(errors, "routings.csv", row$line, reason)
      next
    }
    routings[[id]] <- c(routings[[id]], list(list(item = id, number = number, center = center,
                                                setup = as.numeric(fields[4L]), run = run)))
  }
  lapply(routings, function(operations) operations[order(vapply(operations, function(operation) operation$number, integer(1L)))])
}

operation_week <- function(receipt, lead_time, index, count) max(receipt - lead_time + as.integer(integer_divide(index * lead_time, count)), 1L)
operation_minutes <- function(operation, quantity) operation$setup + quantity * operation$run

level_loads <- function(loads, available) {
  leveled <- numeric(length(loads))
  carry <- 0
  if (length(loads) >= 2L) for (week in seq.int(length(loads), 2L)) {
    total <- loads[week] + carry
    leveled[week] <- min(total, available)
    carry <- total - leveled[week]
  }
  leveled[1L] <- loads[1L] + carry
  leveled
}
