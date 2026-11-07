BASIS_POINT <- 0.0001

bisection <- function(f, low, high, target) {
  for (iteration in seq_len(80L)) {
    middle <- (low + high) / 2
    if (f(middle) > target) low <- middle else high <- middle
  }
  (low + high) / 2
}

present_values <- function(pricer, rate) {
  first <- 1 + pricer$fraction * rate / pricer$frequency
  growth <- 1 + rate / pricer$frequency
  factor <- 1
  values <- numeric(length(pricer$flows))
  for (i in seq_along(values)) {
    values[i] <- pricer$flows[i] / (first * factor)
    factor <- factor * growth
  }
  values
}

dirty_price <- function(pricer, rate) {
  total <- 0
  for (value in present_values(pricer, rate)) total <- total + value
  total * 100 / pricer$outstanding
}

yield_to_maturity <- function(pricer, target) bisection(function(rate) dirty_price(pricer, rate), 0, 1, target)

yield_risk <- function(pricer, rate) {
  values <- present_values(pricer, rate)
  total <- weighted <- curvature <- 0
  for (i in seq_along(values)) {
    years <- (i - 1L + pricer$fraction) / pricer$frequency
    total <- total + values[i]
    weighted <- weighted + years * values[i]
    curvature <- curvature + years * (years + 1 / pricer$frequency) * values[i]
  }
  growth <- 1 + rate / pricer$frequency
  macaulay <- weighted / total
  list(macaulay = macaulay, modified = macaulay / growth, convexity = curvature / (total * growth * growth),
       dv01 = (dirty_price(pricer, rate - BASIS_POINT) - dirty_price(pricer, rate + BASIS_POINT)) / 2)
}
