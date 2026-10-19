rate_settings <- c(
  "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
  "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
)
setting_order <- c(
  rate_settings, "SSBASE", "ADDBASE", "UIBASE",
  "RETIRECAP", "ALLOWANCE", "NIGHT"
)
initial_settings <- list(
  STATE = 500, SUPP = 2200, SSRATE = 620, MEDRATE = 145,
  ADDMED = 90, UIRATE = 270, MATCH = 5000, MATCHMAX = 600,
  GARNCAP = 2500, SSBASE = 16860000, ADDBASE = 20000000,
  UIBASE = 700000, RETIRECAP = 2300000, ALLOWANCE = 15000,
  NIGHT = 100
)
fields <- c(
  "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
  "sales", "commission", "earnings", "bonus", "gross", "retirement",
  "health", "federal", "supplemental", "state", "social", "medicare",
  "garnishment", "net", "employer_social", "employer_medicare",
  "unemployment", "match", "employer", "W", "Y", "F", "J"
)
weekdays <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

number <- function(text) as.numeric(text)
cents <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1]]
  100 * number(parts[1]) + number(parts[2])
}
money <- function(value) sprintf("%.0f.%02d", floor(value / 100), as.integer(value %% 100))
rate_text <- function(value) paste0(money(value), "%")
duration <- function(value) sprintf("%.0f:%02d", floor(value / 60), as.integer(value %% 60))
clock <- function(value) sprintf("%02d:%02d", as.integer(floor(value / 60)), as.integer(value %% 60))
weekday <- function(day) weekdays[(day - 1) %% 7 + 1]
period_of <- function(day) floor((day - 1) / 14) + 1

fail <- function(reason) {
  error <- structure(
    list(message = reason, call = NULL),
    class = c("PayrollError", "error", "condition")
  )
  stop(error)
}

empty_totals <- function() as.list(setNames(rep(0, length(fields)), fields))

sum_stubs <- function(stubs) {
  result <- empty_totals()
  for (stub in stubs) {
    for (field in fields) result[[field]] <- result[[field]] + stub[[field]]
  }
  result
}

sorted_ids <- function(env) sort(as.numeric(ls(envir = env, all.names = TRUE)))
sorted_codes <- function(env) sort(ls(envir = env, all.names = TRUE))

progressive <- function(table, amount) {
  limits <- sorted_ids(table)
  numerator <- 0
  for (i in seq_along(limits)) {
    lower <- limits[i]
    if (lower >= amount) break
    upper <- if (i < length(limits)) limits[i + 1] else amount
    numerator <- numerator + get(as.character(lower), envir = table) *
                 (min(amount, upper) - lower)
  }
  floor(numerator / 10000)
}

new_employee <- function(id, department, kind, base) {
  employee <- new.env(parent = emptyenv())
  employee$id <- id
  employee$department <- department
  employee$kind <- kind
  employee$base <- base
  employee$active <- TRUE
  employee$retirement <- 0
  employee$health <- 0
  employee$allowances <- 0
  employee$extra <- 0
  employee$garnishments <- list()
  employee$bonus <- 0
  employee$pto_balance <- 0
  employee$shifts <- list()
  employee$pto <- list()
  employee$leave <- numeric()
  employee$sales <- list()
  employee$stubs <- list()
  employee$ytd <- empty_totals()
  employee$periods <- 0
  employee
}

garnishment_balance <- function(employee) {
  sum(vapply(employee$garnishments, function(x) x[2], numeric(1)))
}

new_payroll <- function() {
  payroll <- new.env(parent = emptyenv())
  payroll$settings <- initial_settings
  payroll$brackets <- new.env(parent = emptyenv(), hash = TRUE)
  payroll$tiers <- new.env(parent = emptyenv(), hash = TRUE)
  payroll$holidays <- numeric()
  payroll$employees <- new.env(parent = emptyenv(), hash = TRUE)
  payroll$closed <- 0
  payroll$output <- character()
  payroll
}

emit <- function(payroll, indent = 0, ...) {
  parts <- unlist(list(...), use.names = FALSE)
  payroll$output <- c(
    payroll$output,
    paste0(strrep(" ", indent), paste(as.character(parts), collapse = " "))
  )
}

employee_of <- function(payroll, text, active = FALSE, kind = NULL) {
  id <- as.character(number(text))
  if (!exists(id, envir = payroll$employees, inherits = FALSE))
    fail(paste("unknown employee", text))
  employee <- get(id, envir = payroll$employees)
  if (active && !employee$active) fail(paste("terminated employee", text))
  if (!is.null(kind) && employee$kind != kind)
    fail(paste("not", tolower(kind), text))
  employee
}

day_check <- function(payroll, text) {
  day <- number(text)
  if (day < 1 || day > 364) fail(paste("invalid day", text))
  period <- period_of(day)
  if (period <= payroll$closed) fail(paste("period closed", period))
  day
}

period_check <- function(text) {
  period <- number(text)
  if (period < 1 || period > 26) fail(paste("invalid period", text))
  period
}

rate_check <- function(text) {
  rate <- cents(text)
  if (rate > 10000) fail(paste("invalid rate", text))
  rate
}

amount_check <- function(text) {
  amount <- cents(text)
  if (amount == 0) fail("invalid amount")
  amount
}

time_check <- function(text) {
  parts <- as.numeric(strsplit(text, ":", fixed = TRUE)[[1]])
  if (parts[1] > 23 || parts[2] > 59) fail(paste("invalid time", text))
  parts[1] * 60 + parts[2]
}

daily <- function(payroll, employee, day) {
  shifts <- employee$shifts[[as.character(day)]]
  if (is.null(shifts)) shifts <- list()
  worked <- 0
  night <- 0
  for (shift in shifts) {
    first <- shift[1]
    last <- shift[2]
    worked <- worked + last - first
    night <- night + max(0, min(last, 360) - first) +
             max(0, last - max(first, 1320))
  }
  pto <- employee$pto[[as.character(day)]]
  if (is.null(pto)) pto <- 0
  if (day %% 7 == 0 || day %in% payroll$holidays) {
    regular <- 0
    overtime <- 0
    double <- worked
  } else {
    regular <- min(worked, 480)
    overtime <- min(max(worked - 480, 0), 240)
    double <- max(worked - 720, 0)
  }
  list(worked = worked, values = c(regular, overtime, double, night, pto))
}

weekly <- function(payroll, employee, week) {
  totals <- rep(0, 5)
  for (day in (7 * week - 6):(7 * week)) {
    totals <- totals + daily(payroll, employee, day)$values
  }
  weekly_ot <- max(0, totals[1] - 2400)
  totals[1] <- totals[1] - weekly_ot
  totals[2] <- totals[2] + weekly_ot
  list(values = totals, overtime = weekly_ot)
}

breakdown <- function(payroll, employee, period) {
  weekly(payroll, employee, 2 * period - 1)$values +
    weekly(payroll, employee, 2 * period)$values
}

calculate <- function(payroll, employee, period) {
  stub <- empty_totals()
  settings <- payroll$settings
  ytd <- employee$ytd
  if (employee$kind == "HOURLY") {
    values <- breakdown(payroll, employee, period)
    for (i in seq_along(c("R", "O", "D", "N", "P"))) {
      field <- c("R", "O", "D", "N", "P")[i]
      stub[[field]] <- values[i]
    }
    weighted <- 2 * (stub$R + stub$P) + 3 * stub$O + 4 * stub$D
    stub$earnings <- floor((weighted * employee$base +
                            2 * stub$N * settings$NIGHT) / 120)
  } else if (employee$kind == "SALARIED") {
    if (employee$active) {
      stub$salary <- floor(employee$base / 26)
      stub$leave <- sum(vapply(employee$leave, function(day)
        period_of(day) == period && !(day %in% payroll$holidays), logical(1)))
      stub$deduction <- stub$leave * floor(employee$base / 260)
      stub$earnings <- stub$salary - stub$deduction
    }
  } else {
    sales <- employee$sales[[as.character(period)]]
    if (is.null(sales)) sales <- 0
    stub$sales <- sales
    stub$commission <- progressive(payroll$tiers, stub$sales)
    stub$earnings <- stub$commission + if (employee$active) employee$base else 0
  }

  stub$bonus <- employee$bonus
  gross <- stub$earnings + stub$bonus
  if (gross == 0) return(NULL)
  stub$gross <- gross
  remaining <- gross

  deduct <- function(field, amount) {
    taken <- min(amount, remaining)
    stub[[field]] <<- taken
    remaining <<- remaining - taken
  }

  retirement_room <- max(0, settings$RETIRECAP - ytd$retirement)
  deduct("retirement", min(floor(gross * employee$retirement / 10000), retirement_room))
  deduct("health", employee$health)
  stub$W <- remaining
  base_taxable <- max(0, stub$earnings - stub$retirement - stub$health)
  taxable <- max(0, base_taxable - employee$allowances * settings$ALLOWANCE)
  deduct("federal", progressive(payroll$brackets, taxable) + employee$extra)
  deduct("supplemental", floor((stub$W - base_taxable) * settings$SUPP / 10000))
  deduct("state", floor(stub$W * settings$STATE / 10000))

  medicare_wages <- gross - stub$health
  social_wages <- min(medicare_wages, max(0, settings$SSBASE - ytd$Y))
  additional <- max(0, min(medicare_wages,
                           ytd$F + medicare_wages - settings$ADDBASE))
  stub$F <- medicare_wages
  stub$Y <- social_wages
  deduct("social", floor(social_wages * settings$SSRATE / 10000))
  deduct("medicare", floor(medicare_wages * settings$MEDRATE / 10000) +
         floor(additional * settings$ADDMED / 10000))

  disposable <- remaining
  cap <- floor(disposable * settings$GARNCAP / 10000)
  balances <- numeric()
  garnishment <- 0
  for (order in employee$garnishments) {
    taken <- min(floor(disposable * order[1] / 10000),
                 order[2], cap - garnishment)
    garnishment <- garnishment + taken
    balances <- c(balances, order[2] - taken)
  }
  stub$garnishment <- garnishment
  stub$garnishment_balance <- sum(balances)
  stub$net <- remaining - garnishment
  stub$employer_social <- floor(social_wages * settings$SSRATE / 10000)
  stub$employer_medicare <- floor(medicare_wages * settings$MEDRATE / 10000)
  stub$J <- min(medicare_wages, max(0, settings$UIBASE - ytd$J))
  stub$unemployment <- floor(stub$J * settings$UIRATE / 10000)
  eligible_match <- min(stub$retirement,
                        floor(gross * settings$MATCHMAX / 10000))
  stub$match <- floor(eligible_match * settings$MATCH / 10000)
  stub$employer <- stub$employer_social + stub$employer_medicare +
                   stub$unemployment + stub$match
  if (employee$kind == "HOURLY") {
    stub$accrued <- min(960 - employee$pto_balance,
                        floor((stub$R + stub$O + stub$D) / 20))
  }
  stub$pto_balance <- employee$pto_balance + stub$accrued
  list(stub = stub, balances = balances)
}

hours_parts <- function(values) {
  labels <- c("reg", "ot", "dbl", "night", "pto")
  as.vector(rbind(labels, vapply(values, duration, character(1))))
}

stub_block <- function(payroll, employee, stub, indent) {
  if (employee$kind == "HOURLY") {
    values <- vapply(c("R", "O", "D", "N", "P"),
                     function(field) stub[[field]], numeric(1))
    emit(payroll, indent, "hours", hours_parts(values))
    emit(payroll, indent, "pto", "accrued", duration(stub$accrued),
         "balance", duration(stub$pto_balance))
  } else if (employee$kind == "SALARIED") {
    emit(payroll, indent, "salary", money(stub$salary), "leave", stub$leave,
         "deduction", money(stub$deduction))
  } else {
    emit(payroll, indent, "sales", money(stub$sales),
         "commission", money(stub$commission))
  }
  for (field in c(
    "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare"
  )) {
    label <- if (field == "social") "social-security" else field
    emit(payroll, indent, label, money(stub[[field]]))
  }
  emit(payroll, indent, "garnishment", money(stub$garnishment),
       "balance", money(stub$garnishment_balance))
  emit(payroll, indent, "net", money(stub$net))
  emit(payroll, indent, "employer", "social-security", money(stub$employer_social),
       "medicare", money(stub$employer_medicare),
       "unemployment", money(stub$unemployment), "match", money(stub$match))
}

print_stub <- function(payroll, employee, period, stub, department) {
  emit(payroll, 2, "STUB", employee$id, department, employee$kind, "period", period)
  stub_block(payroll, employee, stub, 4)
}

show_hours <- function(payroll, employee, period) {
  emit(payroll, 0, "HOURS", employee$id, "period", period)
  found <- FALSE
  for (day in (14 * period - 13):(14 * period)) {
    shifts <- employee$shifts[[as.character(day)]]
    if (is.null(shifts)) shifts <- list()
    pto <- employee$pto[[as.character(day)]]
    if (length(shifts) == 0 && is.null(pto)) next
    if (length(shifts)) {
      shifts <- shifts[order(vapply(shifts, function(x) x[1], numeric(1)))]
    }
    result <- daily(payroll, employee, day)
    parts <- c("day", as.character(day), weekday(day))
    if (day %in% payroll$holidays) parts <- c(parts, "holiday")
    for (shift in shifts) {
      parts <- c(parts, paste0(clock(shift[1]), "-", clock(shift[2])))
    }
    parts <- c(parts, "total", duration(result$worked),
               hours_parts(result$values))
    emit(payroll, 2, parts)
    found <- TRUE
  }
  if (!found) emit(payroll, 2, "(none)")
  for (week in c(2 * period - 1, 2 * period)) {
    result <- weekly(payroll, employee, week)
    emit(payroll, 2, "week", week, hours_parts(result$values),
         "weekly-ot", duration(result$overtime))
  }
  emit(payroll, 2, "total", hours_parts(breakdown(payroll, employee, period)))
}

run <- function(payroll, period) {
  payroll$closed <- period
  emit(payroll, 0, "RUN", period, "days",
       paste0(14 * period - 13, "-", 14 * period))
  paid <- 0
  skipped <- 0
  stubs <- list()
  for (id in sorted_ids(payroll$employees)) {
    employee <- get(as.character(id), envir = payroll$employees)
    calculated <- calculate(payroll, employee, period)
    if (is.null(calculated)) {
      if (employee$active) skipped <- skipped + 1
      next
    }
    stub <- calculated$stub
    print_stub(payroll, employee, period, stub, employee$department)
    employee$bonus <- 0
    employee$pto_balance <- stub$pto_balance
    for (i in seq_along(calculated$balances)) {
      employee$garnishments[[i]][2] <- calculated$balances[i]
    }
    for (field in fields) {
      employee$ytd[[field]] <- employee$ytd[[field]] + stub[[field]]
    }
    employee$periods <- employee$periods + 1
    employee$stubs[[as.character(period)]] <- list(
      stub = stub, department = employee$department
    )
    stubs[[length(stubs) + 1]] <- stub
    paid <- paid + 1
  }
  totals <- sum_stubs(stubs)
  emit(payroll, 2, "TOTAL", "paid", paid, "skipped", skipped,
       "gross", money(totals$gross),
       "deductions", money(totals$gross - totals$net),
       "net", money(totals$net), "employer", money(totals$employer))
}

journal <- function(payroll, period) {
  stubs <- list()
  for (id in sorted_ids(payroll$employees)) {
    employee <- get(as.character(id), envir = payroll$employees)
    entry <- employee$stubs[[as.character(period)]]
    if (!is.null(entry)) stubs[[length(stubs) + 1]] <- entry$stub
  }
  total <- sum_stubs(stubs)
  rows <- list(
    c("debit", "wages", total$gross),
    c("debit", "employer-tax", total$employer_social + total$employer_medicare + total$unemployment),
    c("debit", "retirement-match", total$match),
    c("credit", "retirement", total$retirement + total$match),
    c("credit", "health", total$health),
    c("credit", "federal", total$federal + total$supplemental),
    c("credit", "state", total$state),
    c("credit", "fica", total$social + total$medicare + total$employer_social + total$employer_medicare),
    c("credit", "unemployment", total$unemployment),
    c("credit", "garnishment", total$garnishment),
    c("credit", "net-pay", total$net)
  )
  emit(payroll, 0, "JOURNAL", period, "stubs", length(stubs))
  debit <- 0
  credit <- 0
  for (row in rows) {
    amount <- number(row[3])
    emit(payroll, 2, row[1], row[2], money(amount))
    if (row[1] == "debit") debit <- debit + amount
    else credit <- credit + amount
  }
  emit(payroll, 2, "total", "debit", money(debit), "credit", money(credit))
}

report_line <- function(payroll, department, stubs) {
  totals <- sum_stubs(stubs)
  taxes <- totals$federal + totals$supplemental +
           totals$state + totals$social + totals$medicare
  emit(payroll, 2, department, "stubs", length(stubs),
       "gross", money(totals$gross),
       "pretax", money(totals$retirement + totals$health),
       "taxes", money(taxes), "garnishment", money(totals$garnishment),
       "net", money(totals$net), "employer", money(totals$employer))
}

command <- function(payroll, operation, a) {
  if (operation == "SET") {
    name <- a[1]
    if (is.null(payroll$settings[[name]])) fail(paste("unknown setting", name))
    value <- if (name %in% rate_settings) rate_check(a[2]) else cents(a[2])
    format <- if (name %in% rate_settings) rate_text else money
    previous <- payroll$settings[[name]]
    payroll$settings[[name]] <- value
    emit(payroll, 0, "SET", name, format(previous), "->", format(value))
  } else if (operation %in% c("BRACKET", "TIER")) {
    rate <- rate_check(a[2])
    table <- if (operation == "BRACKET") payroll$brackets else payroll$tiers
    lower <- cents(a[1])
    key <- as.character(lower)
    action <- if (exists(key, envir = table, inherits = FALSE)) "replaced" else "added"
    assign(key, rate, envir = table)
    emit(payroll, 0, operation, money(lower), rate_text(rate), action)
  } else if (operation == "EMP") {
    id <- number(a[1])
    key <- as.character(id)
    if (exists(key, envir = payroll$employees, inherits = FALSE))
      fail(paste("duplicate employee", a[1]))
    base <- amount_check(a[4])
    assign(key, new_employee(id, a[2], a[3], base), envir = payroll$employees)
    emit(payroll, 0, "EMP", id, a[2], a[3], money(base))
  } else if (operation %in% c("RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS")) {
    employee <- employee_of(payroll, a[1], active = TRUE)
    if (operation == "RATE") {
      base <- amount_check(a[2])
      previous <- employee$base
      employee$base <- base
      emit(payroll, 0, "RATE", employee$id, money(previous), "->", money(base))
    } else if (operation == "DEPT") {
      if (a[2] == employee$department) fail(paste("same department", a[2]))
      previous <- employee$department
      employee$department <- a[2]
      emit(payroll, 0, "DEPT", employee$id, previous, "->", a[2])
    } else if (operation == "BENEFIT") {
      rate <- rate_check(a[2])
      employee$retirement <- rate
      employee$health <- cents(a[3])
      emit(payroll, 0, "BENEFIT", employee$id, "retirement",
           rate_text(rate), "health", money(employee$health))
    } else if (operation == "W4") {
      employee$allowances <- number(a[2])
      employee$extra <- cents(a[3])
      emit(payroll, 0, "W4", employee$id, "allowances", employee$allowances,
           "extra", money(employee$extra))
    } else if (operation == "GARNISH") {
      rate <- rate_check(a[2])
      amount <- amount_check(a[3])
      employee$garnishments[[length(employee$garnishments) + 1]] <- c(rate, amount)
      emit(payroll, 0, "GARNISH", employee$id, "order", length(employee$garnishments),
           rate_text(rate), "balance", money(amount))
    } else if (operation == "TERM") {
      employee$active <- FALSE
      emit(payroll, 0, "TERM", employee$id)
    } else {
      amount <- amount_check(a[2])
      employee$bonus <- employee$bonus + amount
      emit(payroll, 0, "BONUS", employee$id, money(amount),
           "pending", money(employee$bonus))
    }
  } else if (operation == "HOLIDAY") {
    day <- day_check(payroll, a[1])
    if (day %in% payroll$holidays) fail(paste("duplicate holiday", a[1]))
    payroll$holidays <- c(payroll$holidays, day)
    emit(payroll, 0, "HOLIDAY", day, weekday(day))
  } else if (operation %in% c("TIME", "UNTIME", "PTO", "LEAVE", "SALES")) {
    kind <- if (operation == "LEAVE") "SALARIED" else if (operation == "SALES") "COMMISSION" else "HOURLY"
    employee <- employee_of(payroll, a[1], active = TRUE, kind = kind)
    day <- day_check(payroll, a[2])
    key <- as.character(day)
    if (operation == "TIME") {
      start_time <- time_check(a[3])
      end_time <- time_check(a[4])
      if (start_time >= end_time)
        fail(paste0("invalid shift ", a[3], "-", a[4]))
      shifts <- employee$shifts[[key]]
      if (is.null(shifts)) shifts <- list()
      if (length(shifts)) {
        shifts <- shifts[order(vapply(shifts, function(s) s[1], numeric(1)))]
      }
      for (shift in shifts) {
        if (start_time < shift[2] && shift[1] < end_time) {
          fail(paste("overlapping shift", paste0(clock(shift[1]), "-", clock(shift[2]))))
        }
      }
      worked <- sum(vapply(shifts, function(s) s[2] - s[1], numeric(1)))
      if (worked + end_time - start_time > 960)
        fail(paste("daily limit", a[1], a[2]))
      shifts[[length(shifts) + 1]] <- c(start_time, end_time)
      employee$shifts[[key]] <- shifts
      emit(payroll, 0, "TIME", employee$id, "day", day,
           paste0(clock(start_time), "-", clock(end_time)),
           duration(end_time - start_time))
    } else if (operation == "UNTIME") {
      start_time <- time_check(a[3])
      shifts <- employee$shifts[[key]]
      if (is.null(shifts)) shifts <- list()
      position <- which(vapply(shifts, function(s) s[1] == start_time, logical(1)))
      if (!length(position)) fail(paste("no shift", a[1], a[2], a[3]))
      shift <- shifts[[position[1]]]
      shifts <- shifts[-position[1]]
      employee$shifts[[key]] <- shifts
      emit(payroll, 0, "UNTIME", employee$id, "day", day,
           paste0(clock(shift[1]), "-", clock(shift[2])))
    } else if (operation == "PTO") {
      parts <- as.numeric(strsplit(a[3], ":", fixed = TRUE)[[1]])
      length_minutes <- parts[1] * 60 + parts[2]
      if (parts[2] > 59 || length_minutes < 1 || length_minutes > 480)
        fail(paste("invalid duration", a[3]))
      if (!is.null(employee$pto[[key]])) fail(paste("duplicate pto", a[1], a[2]))
      if (length_minutes > employee$pto_balance)
        fail(paste("insufficient pto", a[1], duration(employee$pto_balance)))
      employee$pto[[key]] <- length_minutes
      employee$pto_balance <- employee$pto_balance - length_minutes
      emit(payroll, 0, "PTO", employee$id, "day", day,
           duration(length_minutes), "balance", duration(employee$pto_balance))
    } else if (operation == "LEAVE") {
      if (day %% 7 %in% c(0, 6) || day %in% payroll$holidays)
        fail(paste("not workday", a[2]))
      if (day %in% employee$leave) fail(paste("duplicate leave", a[1], a[2]))
      employee$leave <- c(employee$leave, day)
      emit(payroll, 0, "LEAVE", employee$id, "day", day, weekday(day))
    } else {
      amount <- amount_check(a[3])
      period <- period_of(day)
      previous <- employee$sales[[as.character(period)]]
      if (is.null(previous)) previous <- 0
      employee$sales[[as.character(period)]] <- previous + amount
      emit(payroll, 0, "SALES", employee$id, "day", day, money(amount),
           "period", period, "total", money(previous + amount))
    }
  } else if (operation == "HOURS") {
    employee <- employee_of(payroll, a[1], kind = "HOURLY")
    show_hours(payroll, employee, period_check(a[2]))
  } else if (operation == "RUN") {
    period <- number(a[1])
    if (period != payroll$closed + 1 || period > 26)
      fail(paste("invalid period", a[1]))
    run(payroll, period)
  } else if (operation == "PREVIEW") {
    employee <- employee_of(payroll, a[1])
    period <- payroll$closed + 1
    calculated <- calculate(payroll, employee, period)
    emit(payroll, 0, "PREVIEW", employee$id, "period", period)
    if (is.null(calculated)) {
      emit(payroll, 2, "no pay")
    } else {
      print_stub(payroll, employee, period, calculated$stub, employee$department)
    }
  } else if (operation == "REPRINT") {
    employee <- employee_of(payroll, a[1])
    period <- period_check(a[2])
    entry <- employee$stubs[[as.character(period)]]
    if (is.null(entry)) fail(paste("no stub", a[1], a[2]))
    emit(payroll, 0, "REPRINT", employee$id, period)
    print_stub(payroll, employee, period, entry$stub, entry$department)
  } else if (operation == "YTD") {
    employee <- employee_of(payroll, a[1])
    emit(payroll, 0, "YTD", employee$id, employee$department, employee$kind,
         if (employee$active) "active" else "terminated",
         "periods", employee$periods)
    totals <- employee$ytd
    totals$pto_balance <- employee$pto_balance
    totals$garnishment_balance <- garnishment_balance(employee)
    stub_block(payroll, employee, totals, 2)
    emit(payroll, 2, "wages", "federal", money(totals$W),
         "social-security", money(totals$Y),
         "medicare", money(totals$F), "unemployment", money(totals$J))
    emit(payroll, 2, "retirement-room",
         money(max(0, payroll$settings$RETIRECAP - totals$retirement)),
         "pending-bonus", money(employee$bonus))
  } else if (operation == "JOURNAL") {
    period <- number(a[1])
    if (period < 1 || period > payroll$closed) fail(paste("no run", a[1]))
    journal(payroll, period)
  } else if (operation == "REPORT") {
    departments <- list()
    all_stubs <- list()
    for (id in sorted_ids(payroll$employees)) {
      employee <- get(as.character(id), envir = payroll$employees)
      for (entry in employee$stubs) {
        department <- entry$department
        if (is.null(departments[[department]])) departments[[department]] <- list()
        departments[[department]][[length(departments[[department]]) + 1]] <- entry$stub
        all_stubs[[length(all_stubs) + 1]] <- entry$stub
      }
    }
    emit(payroll, 0, "REPORT", "period", payroll$closed)
    for (department in sort(names(departments))) {
      report_line(payroll, department, departments[[department]])
    }
    report_line(payroll, "total", all_stubs)
  } else if (operation == "TOP") {
    count <- number(a[1])
    eligible <- list()
    for (id in sorted_ids(payroll$employees)) {
      employee <- get(as.character(id), envir = payroll$employees)
      if (employee$periods > 0) eligible[[length(eligible) + 1]] <- employee
    }
    if (length(eligible)) {
      order <- order(
        -vapply(eligible, function(e) e$ytd$gross, numeric(1)),
        vapply(eligible, function(e) e$id, numeric(1))
      )
      eligible <- eligible[order]
    }
    emit(payroll, 0, "TOP", count)
    if (length(eligible)) {
      for (i in seq_len(min(count, length(eligible)))) {
        employee <- eligible[[i]]
        emit(payroll, 2, i, employee$id, employee$department,
             "gross", money(employee$ytd$gross), "net", money(employee$ytd$net))
      }
    } else {
      emit(payroll, 2, "(none)")
    }
  } else if (operation == "EMPLOYEES") {
    emit(payroll, 0, "EMPLOYEES")
    ids <- sorted_ids(payroll$employees)
    for (id in ids) {
      employee <- get(as.character(id), envir = payroll$employees)
      emit(payroll, 2, id, employee$department, employee$kind, money(employee$base),
           if (employee$active) "active" else "terminated",
           "retirement", rate_text(employee$retirement), "health", money(employee$health),
           "allowances", employee$allowances, "extra", money(employee$extra),
           "bonus", money(employee$bonus))
      for (i in seq_along(employee$garnishments)) {
        order <- employee$garnishments[[i]]
        emit(payroll, 4, "garnish", i, rate_text(order[1]), "balance", money(order[2]))
      }
    }
    if (!length(ids)) emit(payroll, 2, "(none)")
  } else if (operation == "CONFIG") {
    emit(payroll, 0, "CONFIG")
    for (name in setting_order) {
      value <- payroll$settings[[name]]
      emit(payroll, 2, name,
           if (name %in% rate_settings) rate_text(value) else money(value))
    }
    for (label in c("bracket", "tier")) {
      table <- if (label == "bracket") payroll$brackets else payroll$tiers
      for (lower in sorted_ids(table)) {
        rate <- get(as.character(lower), envir = table)
        emit(payroll, 2, label, money(lower), rate_text(rate))
      }
    }
  }
}

lines <- readLines(file("stdin"), warn = FALSE)
payroll <- new_payroll()
count <- number(lines[1])
for (i in seq_len(count)) {
  words <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  operation <- words[1]
  a <- words[-1]
  tryCatch(
    command(payroll, operation, a),
    PayrollError = function(error) emit(payroll, 0, "ERROR", conditionMessage(error))
  )
}
cat(paste0(paste(payroll$output, collapse = "\n"), "\n"))
