coupon_schedule <- function(issue, maturity, frequency, end_of_month = FALSE, long_stub = FALSE) {
  date <- civil_date(maturity)
  eom <- end_of_month && date[3L] == month_length(date[1L], date[2L])
  step <- 12L %/% frequency
  dates <- integer()
  boundary <- maturity
  while (boundary > issue) {
    dates <- c(dates, boundary)
    index <- 12L * date[1L] + date[2L] - 1L - step * length(dates)
    year <- index %/% 12L
    month <- index %% 12L + 1L
    day <- if (eom) month_length(year, month) else min(date[3L], month_length(year, month))
    boundary <- day_number(year, month, day)
  }
  if (long_stub && boundary != issue && length(dates) >= 2L) dates <- head(dates, -1L)
  c(issue, rev(dates))
}
