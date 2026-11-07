ATTRIBUTE_CHARTS <- c("p", "np", "c", "u")

center_line <- function(chart, lots) {
  defectives <- sum(vapply(lots, function(lot) lot$defectives, numeric(1L)))
  defects <- sum(vapply(lots, function(lot) lot$defects, numeric(1L)))
  inspected <- sum(vapply(lots, function(lot) lot$inspected, numeric(1L)))
  value <- switch(chart, p = defectives / inspected, np = defectives / length(lots), c = defects / length(lots), u = defects / inspected)
  list(chart = chart, value = value, fraction = defectives / inspected)
}

lot_point <- function(lot, center) {
  cl <- center$value
  if (center$chart == "p") {
    value <- lot$defectives / lot$inspected
    sigma <- sqrt(cl * (1 - cl) / lot$inspected)
  } else if (center$chart == "np") {
    value <- lot$defectives
    sigma <- sqrt(cl * (1 - center$fraction))
  } else if (center$chart == "c") {
    value <- lot$defects
    sigma <- sqrt(cl)
  } else {
    value <- lot$defects / lot$inspected
    sigma <- sqrt(cl / lot$inspected)
  }
  ucl <- cl + 3 * sigma
  lcl <- max(0, cl - 3 * sigma)
  list(value = value, ucl = ucl, lcl = lcl, z = (value - cl) / sigma,
       status = if (value > ucl) "high" else if (value < lcl) "low" else "ok")
}
