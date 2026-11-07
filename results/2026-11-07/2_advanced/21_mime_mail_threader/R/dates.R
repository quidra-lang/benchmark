weekdays <- c("mon", "tue", "wed", "thu", "fri", "sat", "sun")
months <- c("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
named_zones <- c(ut = 0, gmt = 0, z = 0, est = -300, edt = -240, cst = -360, cdt = -300,
                 mst = -420, mdt = -360, pst = -480, pdt = -420)
leap <- function(year) year %% 4 == 0 && year %% 100 != 0 || year %% 400 == 0
year_days <- function(year) if (leap(year)) 366 else 365
month_days <- function(year, month) {
  if (month == 2L && leap(year)) return(29)
  c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
}
has_digits <- function(text, lengths) nchar(text) %in% lengths && grepl("^[0-9]+$", text)

parse_date <- function(value) {
  failure <- function(error) list(date = NULL, error = error)
  text <- remove_comments(value)
  if (is.null(text)) return(failure("bad Date syntax"))
  tokens <- split_words(gsub(",", " , ", text, fixed = TRUE))
  weekday <- NA_integer_
  if (length(tokens) >= 3L && tokens[2L] == ",") {
    weekday <- match(ascii_lower(tokens[1L]), weekdays) - 1L
    if (!is.na(weekday)) tokens <- tokens[-c(1L, 2L)]
  }
  if (length(tokens) != 5L) return(failure("bad Date syntax"))
  pieces <- strsplit(paste0(tokens[4L], ":X"), ":", fixed = TRUE)[[1L]]
  pieces <- pieces[-length(pieces)]
  month <- match(ascii_lower(tokens[2L]), months)
  zone <- tokens[5L]
  numeric_zone <- nchar(zone) == 5L && substr(zone, 1L, 1L) %in% c("+", "-") && has_digits(substring(zone, 2L), 4L)
  offset <- unname(named_zones[ascii_lower(zone)])
  if (!has_digits(tokens[1L], c(1L, 2L)) || is.na(month) || !has_digits(tokens[3L], c(2L, 4L)) ||
      !(length(pieces) %in% c(2L, 3L)) || any(!vapply(pieces, has_digits, logical(1), lengths = 2L)) ||
      !(numeric_zone || !is.na(offset))) return(failure("bad Date syntax"))
  day <- as.numeric(tokens[1L])
  year <- as.numeric(tokens[3L])
  if (nchar(tokens[3L]) == 2L) year <- year + if (year < 50) 2000 else 1900
  hour <- as.numeric(pieces[1L])
  minute <- as.numeric(pieces[2L])
  second <- if (length(pieces) == 3L) as.numeric(pieces[3L]) else 0
  if (numeric_zone) {
    hh <- as.numeric(substr(zone, 2L, 3L))
    mm <- as.numeric(substr(zone, 4L, 5L))
    if (hh > 23 || mm > 59) return(failure("Date out of range"))
    offset <- (hh * 60 + mm) * if (startsWith(zone, "-")) -1 else 1
  }
  if (year < 1970 || year > 2099 || day < 1 || day > month_days(year, month) ||
      hour > 23 || minute > 59 || second > 59) return(failure("Date out of range"))
  days <- 0
  if (year > 1970) for (current in seq.int(1970, year - 1)) days <- days + year_days(current)
  if (month > 1L) for (current in seq_len(month - 1L)) days <- days + month_days(year, current)
  days <- days + day - 1
  seconds <- days * 86400 + hour * 3600 + minute * 60 + second - offset * 60
  if (seconds < 0) return(failure("Date out of range"))
  if (!is.na(weekday) && (days + 3) %% 7 != weekday) return(failure("Date weekday mismatch"))
  list(date = seconds, error = "")
}

format_utc <- function(seconds) {
  days <- seconds %/% 86400
  rest <- seconds %% 86400
  year <- 1970
  while (days >= year_days(year)) {
    days <- days - year_days(year)
    year <- year + 1
  }
  month <- 1L
  while (days >= month_days(year, month)) {
    days <- days - month_days(year, month)
    month <- month + 1L
  }
  sprintf("%04d-%02d-%02d %02d:%02d:%02d", as.integer(year), month, as.integer(days + 1),
          as.integer(rest %/% 3600), as.integer((rest %% 3600) %/% 60), as.integer(rest %% 60))
}
