read_lines <- function(path) readLines(path, warn = FALSE)

read_params <- function() {
  values <- list()
  for (line in read_lines("input/params.txt")) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    values[[fields[1L]]] <- fields[-1L]
  }
  number <- function(key) as.numeric(values[[key]][1L])
  list(reference_day = number("REFERENCE_DAY"), snapshot_day = number("SNAPSHOT_DAY"),
    outcome_days = number("OUTCOME_DAYS"), k_min = as.numeric(values$K_RANGE[1L]),
    k_max = as.numeric(values$K_RANGE[2L]), methods = values$METHODS, restarts = number("RESTARTS"),
    max_iterations = number("MAX_ITERATIONS"), seed = number("SEED"), subsamples = number("SUBSAMPLES"),
    subsample_percent = number("SUBSAMPLE_PERCENT"), outlier_sd = number("OUTLIER_SD"),
    overdue_factor = number("OVERDUE_FACTOR"), order_bins = as.numeric(values$ORDER_BINS),
    top_categories = number("TOP_CATEGORIES"), top_customers = number("TOP_CUSTOMERS"),
    period_days = number("PERIOD_DAYS"), periods = number("PERIODS"))
}

read_transactions <- function() {
  seen <- new.env(hash = TRUE, parent = emptyenv())
  customers <- character()
  valid_rows <- list()
  duplicates <- free <- 0L
  lines <- read_lines("input/transactions.csv")[-1L]
  for (line in lines) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    row <- list(customer = fields[1L], day = as.numeric(fields[2L]), order_id = fields[3L],
                category = fields[4L], amount = as.numeric(fields[5L]))
    customers <- c(customers, row$customer)
    if (exists(line, seen, inherits = FALSE)) duplicates <- duplicates + 1L
    else if (row$amount == 0) free <- free + 1L
    else valid_rows[[length(valid_rows) + 1L]] <- row
    assign(line, TRUE, seen)
  }
  list(row_count = length(lines), duplicates = duplicates, free = free,
       valid_rows = valid_rows, customers = unique(customers))
}

group_orders <- function(rows, first_day, last_day) {
  orders <- list()
  identifiers <- character()
  for (row in rows) {
    if (row$day < first_day || row$day > last_day) next
    index <- match(row$order_id, identifiers)
    if (is.na(index)) {
      index <- length(orders) + 1L
      identifiers <- c(identifiers, row$order_id)
      orders[[index]] <- list(id = row$order_id, customer = row$customer, day = row$day, net = 0, rows = list())
    }
    orders[[index]]$day <- min(orders[[index]]$day, row$day)
    orders[[index]]$net <- orders[[index]]$net + row$amount
    orders[[index]]$rows[[length(orders[[index]]$rows) + 1L]] <- row
  }
  orders
}

orders_by_customer <- function(orders) {
  groups <- list()
  for (order in orders) groups[[order$customer]] <- c(groups[[order$customer]], list(order))
  groups
}
