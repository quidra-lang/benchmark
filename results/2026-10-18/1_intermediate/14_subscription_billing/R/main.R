period_lengths <- c(WEEKLY = 7, MONTHLY = 30, YEARLY = 360)

object <- function(...) list2env(list(...), parent = emptyenv())
has <- function(environment, key) exists(key, envir = environment, inherits = FALSE)
money <- function(value) {
  absolute <- abs(value)
  paste0(if (value < 0) "-" else "", sprintf("%.0f", floor(absolute / 100)),
         ".", sprintf("%02d", absolute %% 100))
}
cents <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1]]
  as.numeric(parts[1]) * 100 + as.numeric(parts[2])
}
integer_text <- function(value) sprintf("%.0f", value)
signed_money <- function(value) paste0(if (value > 0) "+" else "", money(value))
percentage <- function(value) paste0(money(value), "%")

service <- object(
  day = 1, plans = new.env(hash = TRUE, parent = emptyenv()),
  taxes = new.env(hash = TRUE, parent = emptyenv()),
  customers = new.env(hash = TRUE, parent = emptyenv()),
  coupons = new.env(hash = TRUE, parent = emptyenv()),
  subscriptions = list(), invoices = list(), events = list(), output = character()
)

emit <- function(..., indent = 0) {
  parts <- unlist(list(...), use.names = FALSE)
  service$output <- c(service$output, paste0(
    strrep(" ", indent), paste(as.character(parts), collapse = " ")
  ))
}
notice <- function(...) emit("day", service$day, ..., indent = 2)
fail <- function(message) stop(message, call. = FALSE)

require_plan <- function(name) {
  if (!has(service$plans, name)) fail(paste("unknown plan", name))
  get(name, envir = service$plans, inherits = FALSE)
}
require_customer <- function(name) {
  if (!has(service$customers, name)) fail(paste("unknown customer", name))
  get(name, envir = service$customers, inherits = FALSE)
}
redeemable_coupon <- function(name) {
  if (!has(service$coupons, name)) fail(paste("unknown coupon", name))
  coupon <- get(name, envir = service$coupons, inherits = FALSE)
  if (!is.null(coupon$maximum) && coupon$redemptions == coupon$maximum)
    fail(paste("coupon exhausted", name))
  coupon
}
require_subscription <- function(text, allowed = NULL) {
  number <- as.numeric(text)
  if (number < 1 || number > length(service$subscriptions))
    fail(paste("unknown sub", text))
  sub <- service$subscriptions[[number]]
  if (!is.null(allowed) && !(sub$state %in% allowed))
    fail(paste("invalid state", text, sub$state))
  sub
}
require_invoice <- function(text) {
  number <- as.numeric(text)
  if (number < 1 || number > length(service$invoices))
    fail(paste("unknown invoice", text))
  service$invoices[[number]]
}

new_plan <- function(name, price, cycle) {
  object(name = name, price = price, cycle = cycle,
         length = unname(period_lengths[[cycle]]), trial = 0, setup = 0,
         per_seat = FALSE, mode = NULL, tiers = list())
}
plan_fee <- function(plan, seats) if (plan$per_seat) plan$price * seats else plan$price
usage_charge <- function(plan, units) {
  total <- 0
  lower <- 0
  for (i in seq_along(plan$tiers)) {
    tier <- plan$tiers[[i]]
    upper <- tier$upper
    last <- i == length(plan$tiers)
    if (plan$mode == "VOLUME") {
      if (last || is.null(upper) || units <= upper)
        return(units * tier$unit + tier$flat)
    } else {
      if (units <= lower) break
      end <- if (last || is.null(upper)) units else min(units, upper)
      total <- total + (end - lower) * tier$unit + tier$flat
      if (last || is.null(upper)) break
      lower <- upper
    }
  }
  total
}
new_customer <- function(name, region) {
  object(name = name, region = region, method = "OK", balance = 0,
         log = list(), subscriptions = list(), invoices = list())
}
new_coupon <- function(name, kind, value, applications, maximum) {
  object(name = name, kind = kind, value = value, applications = applications,
         maximum = maximum, redemptions = 0)
}
new_subscription <- function(number, customer, plan, seats, coupon) {
  object(
    number = number, customer = customer, plan = plan, seats = seats,
    state = "NONE", start = NULL, end = NULL, trial_end = NULL,
    pause_start = NULL, pending = NULL, cancel_end = FALSE,
    cancel_on = NULL, canceled_on = NULL, coupon = coupon,
    remaining = if (is.null(coupon)) NULL else coupon$applications,
    usage = 0, invoices = list()
  )
}
subscription_period <- function(sub) paste0(sub$start, "-", sub$end)
item <- function(description, amount) list(description = description, amount = amount)
period_item <- function(plan, seats, start) {
  item(paste("charge", plan$name, "seats", seats,
             paste0(start, "-", start + plan$length)),
       plan_fee(plan, seats))
}
opening_items <- function(sub, start) {
  items <- list(period_item(sub$plan, sub$seats, start))
  if (sub$plan$setup > 0) {
    items <- append(items, list(item(paste("setup", sub$plan$name), sub$plan$setup)))
  }
  items
}
usage_items <- function(sub, close = FALSE) {
  if (is.null(sub$plan$mode) || sub$usage == 0) return(list())
  units <- sub$usage
  result <- list(item(paste("usage", sub$plan$name, integer_text(units), "units"),
                      usage_charge(sub$plan, units)))
  if (close) sub$usage <- 0
  result
}
coupon_usable <- function(sub, subtotal) {
  subtotal > 0 && !is.null(sub$coupon) &&
    (is.null(sub$remaining) || sub$remaining > 0)
}
tax_rate <- function(region) {
  if (has(service$taxes, region))
    get(region, envir = service$taxes, inherits = FALSE)
  else 0
}
invoice_totals <- function(sub, items) {
  subtotal <- sum(vapply(items, function(x) x$amount, numeric(1)))
  discount <- 0
  if (coupon_usable(sub, subtotal)) {
    coupon <- sub$coupon
    discount <- if (coupon$kind == "PERCENT")
      floor(subtotal * coupon$value / 10000)
    else min(subtotal, coupon$value)
  }
  tax <- floor((subtotal - discount) * tax_rate(sub$customer$region) / 10000)
  total <- subtotal - discount + tax
  credit <- min(sub$customer$balance, total)
  c(subtotal = subtotal, discount = discount, tax = tax, total = total,
    credit = credit, due = total - credit)
}
new_invoice <- function(number, sub, day, kind, items, totals) {
  object(
    number = number, subscription = sub, customer = sub$customer, day = day,
    kind = kind, items = items, subtotal = totals[["subtotal"]],
    discount = totals[["discount"]], tax = totals[["tax"]],
    total = totals[["total"]], credit = totals[["credit"]],
    due = totals[["due"]], paid = 0, refunded = 0,
    outstanding = totals[["due"]], attempts = 0, retries = numeric()
  )
}
invoice_state <- function(inv) if (inv$outstanding > 0) "OPEN" else "PAID"

balance_change <- function(customer, change, description) {
  if (change != 0) {
    customer$balance <- customer$balance + change
    customer$log <- append(customer$log, list(list(
      day = service$day, description = description,
      change = change, balance = customer$balance
    )))
  }
}
change_state <- function(sub, state) {
  old <- sub$state
  if (old == "PAST_DUE") {
    for (inv in sub$invoices) inv$retries <- numeric()
  }
  sub$state <- state
  notice("sub", sub$number, old, "->", state)
  service$events <- append(service$events,
                           list(list(day = service$day, number = sub$number,
                                     old = old, new = state)))
}
issue_invoice <- function(sub, kind, items) {
  totals <- invoice_totals(sub, items)
  inv <- new_invoice(length(service$invoices) + 1, sub, service$day, kind, items, totals)
  if (coupon_usable(sub, inv$subtotal) && !is.null(sub$remaining))
    sub$remaining <- sub$remaining - 1
  service$invoices <- append(service$invoices, list(inv))
  sub$invoices <- append(sub$invoices, list(inv))
  sub$customer$invoices <- append(sub$customer$invoices, list(inv))
  balance_change(sub$customer, -inv$credit, paste("applied invoice", inv$number))
  if (inv$due == 0) {
    result <- "PAID"
  } else if (sub$state == "UNPAID") {
    result <- "OPEN"
  } else {
    inv$attempts <- 1
    if (sub$customer$method == "OK") {
      inv$paid <- inv$due
      inv$outstanding <- 0
      result <- "PAID"
    } else {
      result <- "FAILED"
    }
  }
  notice("invoice", inv$number, "sub", sub$number, kind, "total", money(inv$total),
         "credit", money(inv$credit), "due", money(inv$due), result)
  if (result == "FAILED") {
    if (sub$state == "ACTIVE") change_state(sub, "PAST_DUE")
    if (sub$state == "PAST_DUE") inv$retries <- service$day + c(3, 5, 7)
  }
  invisible(inv)
}
payment_complete <- function(inv) {
  inv$retries <- numeric()
  sub <- inv$subscription
  if (sub$state %in% c("PAST_DUE", "UNPAID") &&
      all(vapply(sub$invoices, function(x) x$outstanding == 0, logical(1)))) {
    sub$cancel_on <- NULL
    change_state(sub, "ACTIVE")
  }
}
cancel_subscription <- function(sub) {
  change_state(sub, "CANCELED")
  sub$canceled_on <- service$day
  sub$pending <- NULL
  sub$cancel_end <- FALSE
  sub$cancel_on <- NULL
  items <- usage_items(sub, close = TRUE)
  if (length(items)) issue_invoice(sub, "final", items)
}
retry_invoice <- function(inv) {
  inv$retries <- inv$retries[-1]
  inv$attempts <- inv$attempts + 1
  retry_number <- inv$attempts - 1
  if (inv$customer$method == "OK") {
    inv$paid <- inv$paid + inv$outstanding
    inv$outstanding <- 0
    notice("retry", retry_number, "invoice", inv$number, "PAID")
    payment_complete(inv)
  } else {
    notice("retry", retry_number, "invoice", inv$number, "FAILED")
    if (length(inv$retries) == 0) {
      change_state(inv$subscription, "UNPAID")
      inv$subscription$cancel_on <- service$day + 14
    }
  }
}
advance_subscription <- function(sub) {
  if (sub$state %in% c("PAUSED", "CANCELED")) return(invisible(NULL))
  for (inv in sub$invoices) {
    if (length(inv$retries) && inv$retries[1] == service$day) retry_invoice(inv)
  }
  if (sub$state == "UNPAID" && !is.null(sub$cancel_on) &&
      sub$cancel_on == service$day) cancel_subscription(sub)
  if (sub$state == "TRIALING" && !is.null(sub$trial_end) &&
      sub$trial_end == service$day) {
    if (sub$cancel_end) {
      cancel_subscription(sub)
    } else {
      change_state(sub, "ACTIVE")
      sub$start <- service$day
      sub$end <- service$day + sub$plan$length
      issue_invoice(sub, "first", opening_items(sub, service$day))
    }
  }
  if (sub$state %in% c("ACTIVE", "PAST_DUE", "UNPAID") &&
      !is.null(sub$end) && sub$end == service$day) {
    if (sub$cancel_end) {
      cancel_subscription(sub)
    } else {
      items <- usage_items(sub, close = TRUE)
      if (!is.null(sub$pending)) {
        plan <- sub$pending$plan
        seats <- sub$pending$seats
        notice("sub", sub$number, sub$plan$name, "seats", sub$seats,
               "->", plan$name, "seats", seats)
        sub$plan <- plan
        sub$seats <- seats
        sub$pending <- NULL
      }
      sub$start <- service$day
      sub$end <- service$day + sub$plan$length
      items <- append(items, list(period_item(sub$plan, sub$seats, service$day)))
      issue_invoice(sub, "renewal", items)
    }
  }
}

cmd_plan <- function(args) {
  name <- args[1]
  if (has(service$plans, name)) fail(paste("duplicate plan", name))
  plan <- new_plan(name, cents(args[2]), args[3])
  options <- args[-(1:3)]
  position <- 1
  while (position <= length(options)) {
    option <- options[position]
    if (option == "TRIAL") {
      plan$trial <- as.numeric(options[position + 1])
      position <- position + 2
    } else if (option == "SETUP") {
      plan$setup <- cents(options[position + 1])
      position <- position + 2
    } else {
      if (option == "PERSEAT") plan$per_seat <- TRUE else plan$mode <- option
      position <- position + 1
    }
  }
  assign(name, plan, envir = service$plans)
  parts <- c("PLAN", name, args[3], args[2])
  if (plan$trial > 0) parts <- c(parts, "trial", plan$trial)
  if (plan$setup > 0) parts <- c(parts, "setup", money(plan$setup))
  if (plan$per_seat) parts <- c(parts, "perseat")
  if (!is.null(plan$mode)) parts <- c(parts, tolower(plan$mode))
  emit(parts)
}
cmd_tier <- function(args) {
  plan <- require_plan(args[1])
  if (is.null(plan$mode)) fail(paste("not metered", plan$name))
  upper <- if (args[2] == "INF") NULL else as.numeric(args[2])
  if (length(plan$tiers)) {
    previous <- plan$tiers[[length(plan$tiers)]]$upper
    if (is.null(previous) || (!is.null(upper) && upper <= previous))
      fail(paste("tier order", plan$name))
  }
  plan$tiers <- append(plan$tiers,
                       list(list(upper = upper, unit = cents(args[3]),
                                 flat = cents(args[4]))))
  emit("TIER", plan$name, length(plan$tiers), "upto", args[2],
       "unit", args[3], "flat", args[4])
}
cmd_tax <- function(args) {
  value <- as.numeric(args[2])
  assign(args[1], value, envir = service$taxes)
  emit("TAX", args[1], percentage(value))
}
cmd_customer <- function(args) {
  if (has(service$customers, args[1]))
    fail(paste("duplicate customer", args[1]))
  assign(args[1], new_customer(args[1], args[2]), envir = service$customers)
  emit("CUSTOMER", args[1], "region", args[2])
}
cmd_coupon <- function(args) {
  name <- args[1]
  if (has(service$coupons, name)) fail(paste("duplicate coupon", name))
  application <- args[4]
  applications <- if (application == "ONCE") 1 else NULL
  position <- 5
  if (application == "REPEATING") {
    applications <- as.numeric(args[position])
    position <- position + 1
  }
  maximum <- if (position <= length(args)) as.numeric(args[position + 1]) else NULL
  value <- if (args[2] == "PERCENT") as.numeric(args[3]) else cents(args[3])
  coupon <- new_coupon(name, args[2], value, applications, maximum)
  assign(name, coupon, envir = service$coupons)
  parts <- c("COUPON", name, tolower(args[2]),
             if (args[2] == "PERCENT") percentage(value) else money(value),
             tolower(application))
  if (application == "REPEATING") parts <- c(parts, applications)
  if (!is.null(maximum)) parts <- c(parts, "max", maximum)
  emit(parts)
}
cmd_paymethod <- function(args) {
  customer <- require_customer(args[1])
  customer$method <- args[2]
  emit("PAYMETHOD", customer$name, args[2])
}
cmd_credit <- function(args) {
  customer <- require_customer(args[1])
  value <- cents(args[2])
  if (value == 0) fail("invalid amount")
  balance_change(customer, value, "grant")
  emit("CREDIT", customer$name, "amount", args[2], "balance", money(customer$balance))
}
cmd_day <- function(args) {
  target <- as.numeric(args[1])
  if (target <= service$day) fail(paste("invalid day", args[1]))
  emit("DAY", target)
  for (day in seq.int(service$day + 1, target)) {
    service$day <- day
    for (sub in service$subscriptions) advance_subscription(sub)
  }
}
cmd_subscribe <- function(args) {
  customer <- require_customer(args[1])
  plan <- require_plan(args[2])
  seats <- 1
  has_seats <- FALSE
  coupon_name <- NULL
  options <- args[-(1:2)]
  if (length(options)) {
    for (i in seq.int(1, length(options), by = 2)) {
      if (options[i] == "SEATS") {
        seats <- as.numeric(options[i + 1])
        has_seats <- TRUE
      } else {
        coupon_name <- options[i + 1]
      }
    }
  }
  if (has_seats && !plan$per_seat) fail(paste("not per-seat", plan$name))
  if (seats == 0) fail("invalid seats")
  coupon <- if (is.null(coupon_name)) NULL else redeemable_coupon(coupon_name)
  sub <- new_subscription(length(service$subscriptions) + 1, customer, plan, seats, coupon)
  if (!is.null(coupon)) coupon$redemptions <- coupon$redemptions + 1
  service$subscriptions <- append(service$subscriptions, list(sub))
  customer$subscriptions <- append(customer$subscriptions, list(sub))
  parts <- c("SUBSCRIBE", "sub", sub$number, customer$name, plan$name, "seats", seats)
  if (!is.null(coupon)) parts <- c(parts, "coupon", coupon$name)
  emit(parts)
  if (plan$trial > 0) {
    sub$trial_end <- service$day + plan$trial
    change_state(sub, "TRIALING")
  } else {
    change_state(sub, "ACTIVE")
    sub$start <- service$day
    sub$end <- service$day + plan$length
    issue_invoice(sub, "first", opening_items(sub, service$day))
  }
}
cmd_change <- function(args) {
  sub <- require_subscription(args[1], c("ACTIVE", "TRIALING"))
  if (args[2] == "PLAN") {
    plan <- require_plan(args[3])
    seats <- if (plan$per_seat) sub$seats else 1
  } else {
    plan <- sub$plan
    if (!plan$per_seat) fail(paste("not per-seat", plan$name))
    seats <- as.numeric(args[3])
    if (seats == 0) fail("invalid seats")
  }
  if (identical(plan, sub$plan) && seats == sub$seats)
    fail(paste("no change", args[1]))
  old_plan <- sub$plan
  old_seats <- sub$seats
  head <- c("CHANGE", "sub", sub$number, old_plan$name, "seats", old_seats,
            "->", plan$name, "seats", seats)
  sub$pending <- NULL
  upgrade <- plan_fee(plan, seats) * old_plan$length >
    plan_fee(old_plan, old_seats) * plan$length
  if (sub$state == "TRIALING") {
    sub$plan <- plan
    sub$seats <- seats
    emit(c(head, "now"))
  } else if (upgrade) {
    emit(c(head, "now"))
    days <- sub$end - service$day
    items <- usage_items(sub, close = TRUE)
    items <- append(items, list(
      item(paste("unused", old_plan$name, "seats", old_seats, days, "days"),
           -floor(plan_fee(old_plan, old_seats) * days / old_plan$length)),
      item(paste("remaining", plan$name, "seats", seats, days, "days"),
           floor(plan_fee(plan, seats) * days / plan$length))
    ))
    sub$plan <- plan
    sub$seats <- seats
    issue_invoice(sub, "upgrade", items)
  } else {
    sub$pending <- list(plan = plan, seats = seats)
    emit(c(head, "at", sub$end))
  }
}
cmd_pause <- function(args) {
  sub <- require_subscription(args[1], "ACTIVE")
  emit("PAUSE", "sub", sub$number)
  sub$pause_start <- service$day
  change_state(sub, "PAUSED")
}
cmd_resume <- function(args) {
  sub <- require_subscription(args[1], "PAUSED")
  elapsed <- service$day - sub$pause_start
  sub$end <- sub$end + elapsed
  sub$pause_start <- NULL
  emit("RESUME", "sub", sub$number, "shift", elapsed, "period", subscription_period(sub))
  change_state(sub, "ACTIVE")
}
cmd_cancel <- function(args) {
  sub <- require_subscription(args[1])
  if (args[2] == "END") {
    if (!(sub$state %in% c("ACTIVE", "TRIALING")))
      fail(paste("invalid state", args[1], sub$state))
    if (sub$cancel_end) fail(paste("already canceling", args[1]))
    sub$cancel_end <- TRUE
    day <- if (sub$state == "TRIALING") sub$trial_end else sub$end
    emit("CANCEL", "sub", sub$number, "end", day)
  } else {
    if (sub$state == "CANCELED")
      fail(paste("invalid state", args[1], sub$state))
    refund <- 0
    if (sub$state %in% c("ACTIVE", "PAUSED")) {
      start <- if (sub$state == "ACTIVE") service$day else sub$pause_start
      refund <- floor(plan_fee(sub$plan, sub$seats) *
                        (sub$end - start) / sub$plan$length)
    }
    balance_change(sub$customer, refund, paste("cancel sub", sub$number))
    emit("CANCEL", "sub", sub$number, "now", "credit", money(refund))
    cancel_subscription(sub)
  }
}
cmd_usage <- function(args) {
  sub <- require_subscription(args[1], c("ACTIVE", "PAST_DUE"))
  if (is.null(sub$plan$mode)) fail(paste("not metered", sub$plan$name))
  quantity <- as.numeric(args[2])
  if (quantity == 0) fail("invalid units")
  sub$usage <- sub$usage + quantity
  emit("USAGE", "sub", sub$number, "units", integer_text(quantity), "total", integer_text(sub$usage))
}
cmd_apply <- function(args) {
  sub <- require_subscription(args[1])
  if (sub$state == "CANCELED")
    fail(paste("invalid state", args[1], sub$state))
  coupon <- redeemable_coupon(args[2])
  coupon$redemptions <- coupon$redemptions + 1
  sub$coupon <- coupon
  sub$remaining <- coupon$applications
  emit("APPLY", "sub", sub$number, "coupon", coupon$name)
}
cmd_pay <- function(args) {
  inv <- require_invoice(args[1])
  if (inv$outstanding == 0) fail(paste("already paid", args[1]))
  emit("PAY", "invoice", inv$number, "amount", money(inv$outstanding))
  inv$paid <- inv$paid + inv$outstanding
  inv$outstanding <- 0
  payment_complete(inv)
}
cmd_refund <- function(args) {
  inv <- require_invoice(args[1])
  value <- cents(args[2])
  if (value == 0) fail("invalid amount")
  maximum <- inv$total - inv$refunded
  if (value > maximum)
    fail(paste("refund exceeds", args[1], money(maximum)))
  applied <- min(value, inv$outstanding)
  inv$refunded <- inv$refunded + value
  inv$outstanding <- inv$outstanding - applied
  balance_change(inv$customer, value - applied, paste("refund invoice", inv$number))
  emit("REFUND", "invoice", inv$number, "amount", args[2],
       "applied", money(applied), "balance", money(inv$customer$balance))
  if (applied > 0 && inv$outstanding == 0) payment_complete(inv)
}

emit_items <- function(items) {
  for (entry in items) emit(entry$description, money(entry$amount), indent = 2)
}
emit_totals <- function(totals) {
  emit("subtotal", money(totals[["subtotal"]]), "discount", money(totals[["discount"]]),
       "tax", money(totals[["tax"]]), "total", money(totals[["total"]]), indent = 2)
}
cmd_invoice <- function(args) {
  inv <- require_invoice(args[1])
  emit("INVOICE", inv$number, "sub", inv$subscription$number, inv$customer$name,
       "day", inv$day, inv$kind, invoice_state(inv))
  emit_items(inv$items)
  emit_totals(c(subtotal = inv$subtotal, discount = inv$discount,
                tax = inv$tax, total = inv$total))
  emit("credit", money(inv$credit), "due", money(inv$due), "paid", money(inv$paid),
       "refunded", money(inv$refunded), "outstanding", money(inv$outstanding), indent = 2)
}
cmd_sub <- function(args) {
  sub <- require_subscription(args[1])
  emit("SUB", sub$number, sub$customer$name, sub$plan$name, "seats", sub$seats, sub$state)
  if (sub$state == "TRIALING") emit("trial until", sub$trial_end, indent = 2)
  if (sub$state %in% c("ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"))
    emit("period", subscription_period(sub), indent = 2)
  if (sub$state == "PAUSED") emit("paused since", sub$pause_start, indent = 2)
  if (!is.null(sub$pending))
    emit("pending", sub$pending$plan$name, "seats", sub$pending$seats, indent = 2)
  if (sub$cancel_end) emit("cancel at end", indent = 2)
  if (!is.null(sub$cancel_on)) emit("cancel on", sub$cancel_on, indent = 2)
  if (sub$state == "CANCELED") emit("canceled on", sub$canceled_on, indent = 2)
  if (!is.null(sub$coupon)) {
    if (is.null(sub$remaining)) {
      emit("coupon", sub$coupon$name, "forever", indent = 2)
    } else if (sub$remaining > 0) {
      emit("coupon", sub$coupon$name, "left", sub$remaining, indent = 2)
    }
  }
  if (!is.null(sub$plan$mode) && sub$state != "CANCELED")
    emit("usage", integer_text(sub$usage), indent = 2)
  open <- vapply(Filter(function(x) x$outstanding > 0, sub$invoices),
                 function(x) x$number, numeric(1))
  if (length(open)) emit("open", open, indent = 2)
}
cmd_preview <- function(args) {
  sub <- require_subscription(args[1], c("TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"))
  day <- if (sub$state == "TRIALING") sub$trial_end else sub$end
  if (sub$cancel_end) {
    kind <- "final"
    items <- if (sub$state == "TRIALING") list() else usage_items(sub)
  } else if (sub$state == "TRIALING") {
    kind <- "first"
    items <- opening_items(sub, day)
  } else {
    kind <- "renewal"
    next_plan <- if (!is.null(sub$pending)) sub$pending$plan else sub$plan
    next_seats <- if (!is.null(sub$pending)) sub$pending$seats else sub$seats
    items <- append(usage_items(sub), list(period_item(next_plan, next_seats, day)))
  }
  emit("PREVIEW", "sub", sub$number, "day", day, kind)
  if (!length(items)) {
    emit("(none)", indent = 2)
    return(invisible(NULL))
  }
  emit_items(items)
  totals <- invoice_totals(sub, items)
  emit_totals(totals)
  emit("credit", money(totals[["credit"]]), "due", money(totals[["due"]]), indent = 2)
}
cmd_statement <- function(args) {
  customer <- require_customer(args[1])
  emit("STATEMENT", customer$name, "region", customer$region,
       "tax", percentage(tax_rate(customer$region)),
       "method", customer$method, "balance", money(customer$balance))
  for (sub in customer$subscriptions)
    emit("sub", sub$number, sub$plan$name, sub$state, indent = 2)
  for (inv in customer$invoices)
    emit("invoice", inv$number, "day", inv$day, "sub", inv$subscription$number,
         inv$kind, "total", money(inv$total),
         "outstanding", money(inv$outstanding), indent = 2)
  outstanding <- sum(vapply(customer$invoices, function(x) x$outstanding, numeric(1)))
  emit("outstanding", money(outstanding), indent = 2)
}
cmd_ledger <- function(args) {
  customer <- require_customer(args[1])
  emit("LEDGER", customer$name, "balance", money(customer$balance))
  if (!length(customer$log)) emit("(none)", indent = 2)
  for (entry in customer$log) {
    emit("day", entry$day, entry$description, signed_money(entry$change),
         "balance", money(entry$balance), indent = 2)
  }
}
cmd_mrr <- function(args) {
  by_plan <- new.env(parent = emptyenv(), hash = TRUE)
  for (sub in service$subscriptions) {
    if (!(sub$state %in% c("ACTIVE", "PAST_DUE"))) next
    fee <- plan_fee(sub$plan, sub$seats)
    monthly <- switch(
      sub$plan$cycle,
      MONTHLY = fee,
      YEARLY = floor(fee / 12),
      WEEKLY = floor(fee * 30 / 7)
    )
    name <- sub$plan$name
    if (!has(by_plan, name)) assign(name, c(count = 0, monthly = 0), envir = by_plan)
    entry <- get(name, envir = by_plan, inherits = FALSE)
    entry[["count"]] <- entry[["count"]] + 1
    entry[["monthly"]] <- entry[["monthly"]] + monthly
    assign(name, entry, envir = by_plan)
  }
  emit("MRR")
  count <- 0
  monthly <- 0
  for (name in sort(ls(by_plan))) {
    entry <- get(name, envir = by_plan, inherits = FALSE)
    emit(name, "subs", entry[["count"]], "mrr", money(entry[["monthly"]]), indent = 2)
    count <- count + entry[["count"]]
    monthly <- monthly + entry[["monthly"]]
  }
  emit("total subs", count, "mrr", money(monthly), indent = 2)
}
aging_parts <- function(amounts) {
  c("0-30", money(amounts[1]), "31-60", money(amounts[2]),
    "61+", money(amounts[3]), "sum", money(sum(amounts)))
}
cmd_aging <- function(args) {
  by_customer <- new.env(hash = TRUE, parent = emptyenv())
  totals <- numeric(3)
  for (inv in service$invoices) {
    if (inv$outstanding == 0) next
    age <- service$day - inv$day
    bucket <- if (age <= 30) 1 else if (age <= 60) 2 else 3
    name <- inv$customer$name
    if (!has(by_customer, name)) assign(name, numeric(3), envir = by_customer)
    amounts <- get(name, envir = by_customer, inherits = FALSE)
    amounts[bucket] <- amounts[bucket] + inv$outstanding
    totals[bucket] <- totals[bucket] + inv$outstanding
    assign(name, amounts, envir = by_customer)
  }
  emit("AGING", "day", service$day)
  for (name in sort(ls(by_customer))) {
    amounts <- get(name, envir = by_customer, inherits = FALSE)
    emit(name, aging_parts(amounts), indent = 2)
  }
  emit("total", aging_parts(totals), indent = 2)
}
cmd_dunning <- function(args) {
  emit("DUNNING")
  pending <- Filter(function(x) length(x$retries) > 0, service$invoices)
  for (inv in pending) {
    emit("invoice", inv$number, "sub", inv$subscription$number, inv$customer$name,
         "outstanding", money(inv$outstanding), "attempts", inv$attempts,
         "next", inv$retries[1], indent = 2)
  }
  if (!length(pending)) emit("(none)", indent = 2)
}
cmd_revenue <- function(args) {
  total <- function(key) sum(vapply(service$invoices, function(x) get(key, envir = x),
                                    numeric(1)))
  balances <- sum(vapply(ls(service$customers), function(key)
    get(key, envir = service$customers)$balance, numeric(1)))
  emit("REVENUE")
  emit("invoices", length(service$invoices), "subtotal", money(total("subtotal")),
       "discount", money(total("discount")), "tax", money(total("tax")),
       "total", money(total("total")), indent = 2)
  emit("credit", money(total("credit")), "paid", money(total("paid")),
       "refunded", money(total("refunded")),
       "outstanding", money(total("outstanding")),
       "balances", money(balances), indent = 2)
}
cmd_events <- function(args) {
  selected <- if (length(args)) require_subscription(args[1])$number else NULL
  if (is.null(selected)) emit("EVENTS") else emit("EVENTS", "sub", selected)
  matching <- Filter(function(x) is.null(selected) || x$number == selected,
                     service$events)
  for (event in matching)
    emit("day", event$day, "sub", event$number, event$old, "->", event$new, indent = 2)
  if (!length(matching)) emit("(none)", indent = 2)
}

handlers <- list(
  PLAN = cmd_plan, TIER = cmd_tier, TAX = cmd_tax, CUSTOMER = cmd_customer,
  COUPON = cmd_coupon, PAYMETHOD = cmd_paymethod, CREDIT = cmd_credit,
  DAY = cmd_day, SUBSCRIBE = cmd_subscribe, CHANGE = cmd_change,
  PAUSE = cmd_pause, RESUME = cmd_resume, CANCEL = cmd_cancel,
  USAGE = cmd_usage, APPLY = cmd_apply, PAY = cmd_pay, REFUND = cmd_refund,
  INVOICE = cmd_invoice, SUB = cmd_sub, PREVIEW = cmd_preview,
  STATEMENT = cmd_statement, LEDGER = cmd_ledger, MRR = cmd_mrr,
  AGING = cmd_aging, DUNNING = cmd_dunning, REVENUE = cmd_revenue,
  EVENTS = cmd_events
)

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(lines[1])
for (i in seq_len(count)) {
  fields <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  command <- fields[1]
  arguments <- fields[-1]
  tryCatch(
    handlers[[command]](arguments),
    error = function(error) emit("ERROR", conditionMessage(error))
  )
}
if (length(service$output))
  cat(paste0(paste(service$output, collapse = "\n"), "\n"))
