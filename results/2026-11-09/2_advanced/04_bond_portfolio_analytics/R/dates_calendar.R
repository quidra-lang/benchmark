BUSINESS_DAY_RULES <- c("FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED")
is_leap <- function(year) year %% 4L == 0L && (year %% 100L != 0L || year %% 400L == 0L)
year_length <- function(year) if (is_leap(year)) 366L else 365L

month_length <- function(year, month) {
  if (month == 2L && is_leap(year)) return(29L)
  c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)[month]
}

split_date <- function(text) as.integer(strsplit(text, "-", fixed = TRUE)[[1L]])

valid_date <- function(text) {
  date <- split_date(text)
  date[1L] >= 2001L && date[1L] <= 2099L && date[2L] >= 1L && date[2L] <= 12L &&
    date[3L] >= 1L && date[3L] <= month_length(date[1L], date[2L])
}

day_number <- function(year, month, day) {
  number <- day - 1L
  if (year > 2000L) for (prior in seq.int(2000L, year - 1L)) number <- number + year_length(prior)
  if (month > 1L) for (prior in seq_len(month - 1L)) number <- number + month_length(year, prior)
  number
}

parse_date <- function(text) {
  date <- split_date(text)
  day_number(date[1L], date[2L], date[3L])
}

civil_date <- function(number) {
  year <- 2000L
  while (number >= year_length(year)) {
    number <- number - year_length(year)
    year <- year + 1L
  }
  month <- 1L
  while (number >= month_length(year, month)) {
    number <- number - month_length(year, month)
    month <- month + 1L
  }
  c(year, month, number + 1L)
}

format_date <- function(number) {
  date <- civil_date(number)
  sprintf("%04d-%02d-%02d", date[1L], date[2L], date[3L])
}

business_day <- function(day, holidays) (day + 5L) %% 7L < 5L && !day %in% holidays

business_days <- function(day, count, holidays, direction = 1L) {
  while (count > 0L) {
    day <- day + direction
    if (business_day(day, holidays)) count <- count - 1L
  }
  day
}

adjust_date <- function(day, convention, holidays) {
  if (convention == "UNADJUSTED") return(day)
  direction <- if (convention == "PRECEDING") -1L else 1L
  adjusted <- day
  while (!business_day(adjusted, holidays)) adjusted <- adjusted + direction
  if (convention == "MODIFIED_FOLLOWING" && civil_date(adjusted)[2L] != civil_date(day)[2L]) {
    adjusted <- day
    while (!business_day(adjusted, holidays)) adjusted <- adjusted - 1L
  }
  adjusted
}
