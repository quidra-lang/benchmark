seconds_per_day <- 86400
neg_infinity <- -(2^52)
pos_infinity <- 2^52
month_names <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
weekday_names <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
common_month_days <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
floor_div <- function(a, b) a %/% b
modulo <- function(a, b) a - b * floor_div(a, b)
leap <- function(year) year %% 4 == 0 && year %% 100 != 0 || year %% 400 == 0
days_in_month <- function(year, month) {
  if (month == 2 && leap(year)) 29 else common_month_days[month]
}
days_before_year <- function(year) {
  previous <- year - 1
  previous * 365 + floor_div(previous, 4) - floor_div(previous, 100) + floor_div(previous, 400)
}
day_number <- function(year, month, day) {
  days <- days_before_year(year) - days_before_year(1970) + day - 1
  if (month > 1) for (earlier in seq_len(month - 1)) days <- days + days_in_month(year, earlier)
  days
}
weekday <- function(number) modulo(number + 4, 7)
date_of_day <- function(number) {
  year <- 1970 + floor_div(number, 366)
  while (day_number(year, 1, 1) > number) year <- year - 1
  while (day_number(year + 1, 1, 1) <= number) year <- year + 1
  month <- 1
  day <- number - day_number(year, 1, 1) + 1
  while (day > days_in_month(year, month)) {
    day <- day - days_in_month(year, month)
    month <- month + 1
  }
  c(year, month, day)
}
time_value <- function(year, month, day, hour, minute, second) {
  day_number(year, month, day) * seconds_per_day + hour * 3600 + minute * 60 + second
}
split_time <- function(value) {
  date <- date_of_day(floor_div(value, seconds_per_day))
  rest <- modulo(value, seconds_per_day)
  c(date, floor_div(rest, 3600), modulo(floor_div(rest, 60), 60), modulo(rest, 60))
}
day_spec_value <- function(spec, year, month) {
  if (spec$kind == "last") {
    last <- day_number(year, month, days_in_month(year, month))
    return(last - modulo(weekday(last) - spec$weekday, 7))
  }
  base <- day_number(year, month, spec$day)
  if (spec$kind == "after") return(base + modulo(spec$weekday - weekday(base), 7))
  if (spec$kind == "before") return(base - modulo(weekday(base) - spec$weekday, 7))
  base
}
