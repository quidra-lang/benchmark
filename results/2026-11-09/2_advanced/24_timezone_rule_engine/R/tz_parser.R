field_error <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("field_error", "error", "condition")))
}
line_content <- function(raw) {
  position <- regexpr("#", raw, fixed = TRUE)[1]
  if (position > 0) raw <- substr(raw, 1, position - 1)
  sub(" +$", "", raw)
}
split_fields <- function(content) strsplit(sub("^ +", "", content), " +")[[1]]
is_continuation <- function(content) startsWith(content, " ")
is_number <- function(text, low, high) {
  nchar(text) >= low && nchar(text) <= high && grepl("^[0-9]+$", text)
}
hms_value <- function(text, max_parts) {
  if (endsWith(text, ":")) return(NULL)
  parts <- strsplit(text, ":", fixed = TRUE)[[1]]
  if (!length(parts) || length(parts) > max_parts || !is_number(parts[1], 1, 2)) return(NULL)
  value <- as.numeric(parts[1]) * 3600
  units <- c(60, 1)
  if (length(parts) > 1) for (i in 2:length(parts)) {
    if (!is_number(parts[i], 2, 2) || as.numeric(parts[i]) > 59) return(NULL)
    value <- value + as.numeric(parts[i]) * units[i - 1]
  }
  value
}
parse_year <- function(text) {
  if (!is_number(text, 4, 4) || as.numeric(text) < 1800 || as.numeric(text) > 2099) field_error("bad year")
  as.numeric(text)
}
parse_to <- function(text, from) {
  if (text == "only") return(from)
  if (text == "max") return(2099)
  if (!is_number(text, 4, 4) || as.numeric(text) < from || as.numeric(text) > 2099) field_error("bad year")
  as.numeric(text)
}
parse_month <- function(text) {
  value <- match(text, month_names)
  if (is.na(value)) field_error("bad month")
  as.numeric(value)
}
parse_weekday <- function(text) {
  value <- match(text, weekday_names)
  if (is.na(value)) field_error("bad day spec")
  value - 1
}
parse_day_of_month <- function(text, month) {
  if (!is_number(text, 1, 2) || startsWith(text, "0") || as.numeric(text) > common_month_days[month]) field_error("bad day spec")
  as.numeric(text)
}
parse_day_spec <- function(text, month) {
  if (startsWith(text, "last")) return(list(kind = "last", weekday = parse_weekday(substring(text, 5)), day = 0))
  for (operator in c(">=", "<=")) {
    position <- regexpr(operator, text, fixed = TRUE)[1]
    if (position > 0) {
      day <- parse_weekday(substr(text, 1, position - 1))
      number <- parse_day_of_month(substring(text, position + 2), month)
      return(list(kind = if (operator == ">=") "after" else "before", weekday = day, day = number))
    }
  }
  list(kind = "day", weekday = 0, day = parse_day_of_month(text, month))
}
parse_time <- function(text) {
  type <- "w"
  if (nchar(text) && substr(text, nchar(text), nchar(text)) %in% c("w", "s", "u")) {
    type <- substr(text, nchar(text), nchar(text))
    text <- substr(text, 1, nchar(text) - 1)
  }
  value <- hms_value(text, 3)
  if (is.null(value) || value > 86400) field_error("bad time")
  list(value = value, type = type)
}
parse_save <- function(text) {
  value <- hms_value(text, 2)
  if (is.null(value) || value > 7200) field_error("bad save")
  value
}
parse_letter <- function(text) {
  if (text == "-") return("")
  if (!grepl("^[A-Z]{1,5}$", text)) field_error("bad letter")
  text
}
parse_offset <- function(text) {
  sign <- 1
  if (startsWith(text, "-")) {
    sign <- -1
    text <- substring(text, 2)
  }
  value <- hms_value(text, 3)
  if (is.null(value) || value >= 57600) field_error("bad offset")
  sign * value
}
check_format <- function(text, uses_rules) {
  placeholders <- 0
  slashes <- 0
  i <- 1
  while (i <= nchar(text)) {
    symbol <- substr(text, i, i)
    if (symbol == "%") {
      if (i == nchar(text) || substr(text, i + 1, i + 1) != "s") field_error("bad format")
      placeholders <- placeholders + 1
      i <- i + 1
    } else if (symbol == "/") {
      slashes <- slashes + 1
    } else if (!grepl("^[A-Za-z0-9+-]$", symbol)) {
      field_error("bad format")
    }
    i <- i + 1
  }
  if (placeholders > 1 || slashes > 1 || placeholders > 0 && (slashes > 0 || !uses_rules) || slashes == 1 && (startsWith(text, "/") || endsWith(text, "/"))) field_error("bad format")
  invisible(NULL)
}
parse_until <- function(fields) {
  year <- parse_year(fields[1])
  month_text <- if (length(fields) > 1) fields[2] else "Jan"
  month <- parse_month(month_text)
  day_text <- if (length(fields) > 2) fields[3] else "1"
  day <- parse_day_spec(day_text, month)
  time <- if (length(fields) > 3) parse_time(fields[4]) else list(value = 0, type = "w")
  list(year_text = fields[1], month_text = month_text, day_text = day_text, time = time$value, type = time$type,
       value = day_spec_value(day, year, month) * seconds_per_day + time$value)
}
