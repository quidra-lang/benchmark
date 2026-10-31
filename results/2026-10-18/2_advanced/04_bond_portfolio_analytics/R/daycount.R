DAY_COUNTS <- c("30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT")

year_fraction <- function(convention, start, end) {
  if (convention == "ACT/360") return(c(end - start, 360L))
  if (convention == "ACT/365F") return(c(end - start, 365L))
  first <- civil_date(start)
  last <- civil_date(end)
  if (convention == "ACT/ACT") {
    numerator <- 0L
    year <- first[1L]
    while (start < end) {
      boundary <- min(day_number(year + 1L, 1L, 1L), end)
      numerator <- numerator + (boundary - start) * if (is_leap(year)) 365L else 366L
      start <- boundary
      year <- year + 1L
    }
    return(c(numerator, 133590L))
  }
  if (convention == "30/360") {
    first_february <- first[2L] == 2L && first[3L] == month_length(first[1L], 2L)
    last_february <- last[2L] == 2L && last[3L] == month_length(last[1L], 2L)
    if (first_february && last_february) last[3L] <- 30L
    if (first_february) first[3L] <- 30L
    if (last[3L] == 31L && first[3L] >= 30L) last[3L] <- 30L
    if (first[3L] == 31L) first[3L] <- 30L
  } else {
    first[3L] <- min(first[3L], 30L)
    last[3L] <- min(last[3L], 30L)
  }
  c(360L * (last[1L] - first[1L]) + 30L * (last[2L] - first[2L]) + last[3L] - first[3L], 360L)
}
