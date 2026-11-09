zero_rate <- function(curve, day) {
  count <- length(curve$days)
  if (day <= curve$days[1L]) return(curve$rates[1L])
  if (day >= curve$days[count]) return(curve$rates[count])
  index <- which(curve$days >= day)[1L]
  if (day == curve$days[index]) return(curve$rates[index])
  low <- index - 1L
  curve$rates[low] + (curve$rates[index] - curve$rates[low]) * ((day - curve$days[low]) / (curve$days[index] - curve$days[low]))
}

discount_factor <- function(curve, day, spread = 0) {
  rate <- zero_rate(curve, day) + spread
  years <- as.integer(day %/% 365L)
  remainder <- day %% 365L
  growth <- 1
  for (year in seq_len(years)) growth <- growth * (1 + rate)
  1 / (growth * (1 + rate * remainder / 365))
}

curve_value <- function(curve, flows, spread = 0) {
  total <- 0
  for (i in seq_len(nrow(flows))) total <- total + flows[i, 2L] * discount_factor(curve, flows[i, 1L], spread)
  total
}

forward_rate <- function(curve, start, end) {
  (discount_factor(curve, start) / discount_factor(curve, end) - 1) * 365 / (end - start)
}

shift_curve <- function(curve, deltas) list(days = curve$days, rates = curve$rates + deltas)
flat_curve <- function(rate) list(days = 0L, rates = rate)

bootstrap <- function(settlement, pillars) {
  curve <- list(days = integer(), rates = numeric())
  for (pillar in pillars) {
    dates <- coupon_schedule(settlement, pillar$maturity, pillar$frequency)
    flows <- matrix(0, nrow = length(dates) - 1L, ncol = 2L)
    for (i in seq_len(nrow(flows))) {
      fraction <- year_fraction("30/360", dates[i], dates[i + 1L])
      flows[i, ] <- c(dates[i + 1L] - settlement, pillar$coupon * fraction[1L] / (10000 * fraction[2L]))
    }
    flows[nrow(flows), 2L] <- flows[nrow(flows), 2L] + 1
    curve$days <- c(curve$days, pillar$maturity - settlement)
    rate <- bisection(function(trial) curve_value(list(days = curve$days, rates = c(curve$rates, trial)), flows), 0, 1, 1)
    curve$rates <- c(curve$rates, rate)
  }
  curve
}

z_spread <- function(curve, flows, target) bisection(function(spread) curve_value(curve, flows, spread), -0.5, 0.5, target)
