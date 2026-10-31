month_names <- c(
  "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December"
)
months <- list(c(2024, 2), c(2026, 8), c(2026, 11))
for (index in seq_along(months)) {
  year <- months[[index]][1]
  month <- months[[index]][2]
  if (index > 1) cat("\n")
  cat(sprintf("%s %d\nSu Mo Tu We Th Fr Sa\n", month_names[month], year))
  adjusted_year <- if (month < 3) year - 1 else year
  adjusted_month <- if (month < 3) month + 12 else month
  century <- adjusted_year %/% 100
  within <- adjusted_year %% 100
  weekday <- (1 + (13 * (adjusted_month + 1)) %/% 5 + within + within %/% 4 + century %/% 4 + 5 * century + 6) %% 7
  leap <- year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0)
  days <- if (month == 2 && leap) 29 else c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
  fields <- rep("  ", weekday)
  for (day in seq_len(days)) {
    fields <- c(fields, sprintf("%2d", day))
    if (length(fields) == 7 || day == days) {
      cat(paste(fields, collapse = " "), "\n", sep = "")
      fields <- character(0)
    }
  }
}
